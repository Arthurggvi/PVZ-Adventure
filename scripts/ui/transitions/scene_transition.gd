## 统一场景遮幕与资源加载控制器；启动、世界地图与战斗共用一条管线。
## 不持有用户存档或业务状态，且不在全局创建第二份场景缓存。
extends CanvasLayer
## 场景与功能窗口共用的有限并发请求适配器，不建立另一份全局资源目录。
const ResourceBatch = preload("res://scripts/ui/transitions/resource_load_batch.gd")
## 场景内轻量绘制层，只保存展示快照，不参与资源与业务状态管理。
const LoadingPresentation = preload("res://scripts/ui/transitions/loading_presentation.gd")
## 目标根节点上的一次性视觉交接数据，与 prepared_resources 独立。
const PRESENTATION_META := &"loading_presentation_state"
## 当前场景揭幕完成，输入锁释放。
signal revealed
## 请求失败且准备恢复源场景；失败响应不得清空业务状态。
signal transition_failed
## 遮幕覆盖时间，单位为真实秒，不跟随游戏倍速。
@export_range(0.05, 1.0, 0.01) var cover_seconds := 0.16
## 新场景揭幕的真实时间，单位秒。
@export_range(0.05, 1.0, 0.01) var reveal_seconds := 0.36
## 场景入树时是否自动遮幕并等待可见首帧。
@export var reveal_on_ready := true
## 延迟展开花园内容的真实秒数，避免短切场闪烁提示。
@export var loading_hint_delay := 0.25

## 遮幕、加载、揭幕期间统一拒绝重复请求与底层输入。
var busy := false
## 唯一过渡动画，生命周期从属于本场景。
var _tween: Tween
## 请求时的源场景，仅用于验证旧式动作的真实离场。
var _source_scene: Node
## 入场揭幕前须经过的真实绘制帧数。
var _prepare_frames := 0
## 本次线程加载目标，空字符串表示当前没有待轮询任务。
var _pending_path := ""
## 目标场景被 SceneTree 接受后、目标 _ready 前的一次性交接回调。
var _after_switch: Callable
## 单调计时起点，单位微秒，仅用于进度提示显隐。
var _requested_at_usec := 0
## 当前资源批次；批次进度按读取、动态依赖两阶段映射到展示层。
var _load_batch: RefCounted
## 取消或失败后仍在后台收尾的请求，正常帧只轮询不等待。
var _retired_batches: Array[RefCounted] = []
## 遮幕与读取并行，只有两者都完成才能提交切场。
var _covered := false
## 已解析的目标场景，依赖准备期间保持强引用。
var _packed_target: PackedScene
## 本次请求准备好的动态资源，交接后由目标场景持有。
var _prepared_resources: Array[Resource] = []
## 目标脚本的首屏依赖协议每次只执行一次。
var _dependencies_requested := false
## 源场景已展开内容时，目标无需重新等待显示延迟。
var _hint_shown := false
## 目标仍在等待首屏与两帧屏障，继续按真实时间处理展示延迟。
var _awaiting_visual_ready := false
## 失败恢复不把进度推进到完成，业务回滚仍交给原有宿主。
var _request_failed := false
## 当前请求独享的展示节点；新请求重建，避免继承上次完成进度。
var _presentation: Control
## 负责输入拦截和统一遮幕的不透明层。
@onready var curtain: ColorRect = $Curtain

## 初始化仅负责表现；Boot 场景可明确禁用入树揭幕。
func _ready() -> void:
	set_process(false)
	_create_presentation("准备新的旅程")
	if not reveal_on_ready:
		curtain.modulate.a = 0.0
		curtain.hide()
		return
	_requested_at_usec = Time.get_ticks_usec()
	var host: Node = get_parent() # 快照由源场景在目标入树前放到目标根节点。
	if host != null and host.has_meta(PRESENTATION_META):
		var handoff: Dictionary = host.get_meta(PRESENTATION_META) # 只交接标量与展示数据，不保留源对象。
		_presentation.restore(handoff.get("presentation", {}))
		_requested_at_usec = int(handoff.get("requested_at_usec", _requested_at_usec))
		_hint_shown = bool(handoff.get("hint_shown", false))
		host.remove_meta(PRESENTATION_META)
	busy = true
	_awaiting_visual_ready = true
	set_process(true)
	curtain.show()
	curtain.modulate.a = 1.0
	if DisplayServer.get_name() == "headless":
		_prepare_headless.call_deferred()
	else:
		_prepare_frames = 2
		RenderingServer.frame_post_draw.connect(_on_prepared_frame)

## [param heading] 是当前目的地的友好标题；只重建表现，不影响资源请求与输入锁。
func _create_presentation(heading: String) -> void:
	if is_instance_valid(_presentation):
		curtain.remove_child(_presentation)
		_presentation.queue_free()
	_presentation = LoadingPresentation.new()
	_presentation.name = "LoadingPresentation"
	_presentation.configure(heading, "让阳光先铺满小路")
	_presentation.set_content_visible(false, true)
	curtain.add_child(_presentation)

## [param state] 为启动首屏的视觉快照；只在已接受请求时接管已存在的不透明首屏。
## 首屏原本就已覆盖，无需再次渐暗；不增加新的等待或修改成功回调。
func adopt_presentation(state: Dictionary) -> void:
	if not busy or _pending_path.is_empty():
		return
	_presentation.restore(state)
	_hint_shown = true
	curtain.show()
	curtain.modulate.a = 1.0
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_covered = true

## [param scene_path] 仅用于识别现有正式目的地；返回不暴露资源路径的加载标题。
func _heading_for(scene_path: String) -> String:
	var path: String = scene_path.to_lower() # 路径大小写不改变目的地文案。
	if path.contains("startmenu"):
		return "准备进入城镇"
	if path.contains("zombie_island") or path.contains("adventure_map"):
		return "准备展开地图"
	if path.contains("maingame"):
		return "准备进入关卡"
	return "准备新的旅程"

## 无显示后端仍等待宿主异步构造结束，仅省略真实渲染帧屏障。
func _prepare_headless() -> void:
	var host: Node = get_parent() # 与图形模式共用同一就绪契约。
	while is_instance_valid(host) and host.has_method("is_visual_ready") and not bool(host.call("is_visual_ready")):
		await get_tree().process_frame
		if not is_inside_tree():
			return
	_reveal()

## 父场景可公开 is_visual_ready()，视觉未准备好时不计入两帧揭幕屏障。
func _on_prepared_frame() -> void:
	var host: Node = get_parent() # 异步构造宿主满足自己的视觉就绪协议后才开始计帧。
	if host != null and host.has_method("is_visual_ready") and not bool(host.call("is_visual_ready")):
		return
	_prepare_frames -= 1
	if _prepare_frames <= 0:
		RenderingServer.frame_post_draw.disconnect(_on_prepared_frame)
		_reveal.call_deferred()

## [param action] 是保留给非场景动作的兼容入口；场景跳转必须使用 change_scene()。
## 返回是否接受请求，不以回调返回值推测异步场景结果。
func run(action: Callable) -> bool:
	if busy or not action.is_valid():
		return false
	busy = true
	_request_failed = false
	_create_presentation("准备新的旅程")
	_source_scene = get_tree().current_scene
	curtain.show()
	_tween = _fade_to(1.0, cover_seconds)
	_tween.tween_callback(_invoke.bind(action))
	return true

## [param scene_path] 只允许已存在的 res:// PackedScene；不允许其他文件路径。
## [param after_switch] 仅在目标被 SceneTree 接受后、_ready 前执行一次。
## [param resource_paths] 是本次目标的动态资源清单，读取与遮幕并行。
## 返回值只表示请求已接受；加载失败发出 transition_failed 并恢复输入。
func change_scene(scene_path: String, after_switch: Callable = Callable(),
		resource_paths: PackedStringArray = PackedStringArray()) -> bool:
	if busy or not scene_path.begins_with("res://") or not ResourceLoader.exists(scene_path, "PackedScene"):
		return false
	busy = true
	_source_scene = get_tree().current_scene
	_after_switch = after_switch
	_requested_at_usec = Time.get_ticks_usec()
	_pending_path = scene_path
	_covered = false
	_dependencies_requested = false
	_packed_target = null
	_prepared_resources.clear()
	_hint_shown = false
	_request_failed = false
	_awaiting_visual_ready = false
	_create_presentation(_heading_for(scene_path))
	curtain.show()
	_tween = _fade_to(1.0, cover_seconds)
	_tween.tween_callback(func(): _covered = true)
	# 根资源和显式动态依赖立即请求，与遮幕动画重叠。
	var paths: PackedStringArray = PackedStringArray([scene_path]) # 本次进入所需的根场景。
	paths.append_array(resource_paths)
	_load_batch = ResourceBatch.new()
	if _load_batch.start(paths) != OK:
		_failed.call_deferred()
	else:
		set_process(true)
	return true

## 每帧只查询加载状态；[param _delta] 不用于计时，避免游戏倍速改变展示延迟。
## 禁止在未完成时调用会阻塞的 load_threaded_get。
func _process(_delta: float) -> void:
	for retired: RefCounted in _retired_batches.duplicate(): # 失败请求继续异步回收。
		retired.poll()
		if not retired.is_running():
			_retired_batches.erase(retired)
	if busy and not _hint_shown and (_awaiting_visual_ready or not _pending_path.is_empty()):
		var elapsed: float = float(Time.get_ticks_usec() - _requested_at_usec) / 1000000.0 # 源与目标共用真实起点。
		if elapsed >= loading_hint_delay:
			_hint_shown = true
			_presentation.set_content_visible(true)
	if _load_batch == null or _pending_path.is_empty():
		set_process(_awaiting_visual_ready or not _retired_batches.is_empty())
		return
	var status: int = _load_batch.poll() # 整批资源完成不等于场景已经构造。
	var amount: float = _load_batch.progress() # 当前批次读取比例不能直接作为整个旅程的完成比例。
	_presentation.set_progress(0.65 + amount * 0.25 if _dependencies_requested else amount * 0.65)
	match status:
		ResourceLoader.THREAD_LOAD_LOADED:
			if not _dependencies_requested:
				_packed_target = _load_batch.get_resource(_pending_path) as PackedScene
				_prepared_resources.append_array(_load_batch.resources)
				_dependencies_requested = true
				if _packed_target == null:
					_failed()
					return
				var paths: PackedStringArray = _initial_resource_paths(_packed_target) # 场景脚本声明的首屏动态依赖。
				if not paths.is_empty():
					_presentation.set_detail("正在整理旅途所需")
					_load_batch = ResourceBatch.new()
					if _load_batch.start(paths) != OK:
						_failed()
					return
			_presentation.set_progress(0.90)
			# 重试前遗留的请求也须先异步回收，避免旧组件离树时被迫同步等待。
			if _covered and _retired_batches.is_empty():
				_finish_threaded_load()
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_failed()

## 读取 [param packed] 根脚本的可选首屏依赖；继承场景向基础场景查找，不实例化节点。
func _initial_resource_paths(packed: PackedScene) -> PackedStringArray:
	var state: SceneState = packed.get_state() # PackedScene 已在后台解析完毕。
	if state.get_node_count() == 0:
		return PackedStringArray()
	for index: int in state.get_node_property_count(0): # 根节点显式脚本优先。
		if state.get_node_property_name(0, index) == &"script":
			var script: Script = state.get_node_property_value(0, index) as Script # 不创建场景或业务对象。
			if script != null and script.has_method("get_initial_resource_paths"):
				return script.call("get_initial_resource_paths")
	var base: PackedScene = state.get_node_instance(0) # 继承场景可能在基础根上挂脚本。
	return _initial_resource_paths(base) if base != null else PackedStringArray()

## 目标资源确认完成后唯一提交切场；交接发生于新场景入树前。
func _finish_threaded_load() -> void:
	_presentation.set_progress(0.94)
	_presentation.set_detail("花园正在就位，很快就好")
	var resource: PackedScene = _packed_target # 已完成的场景，不在此处等待线程。
	_prepared_resources.append_array(_load_batch.resources)
	_load_batch = null
	_pending_path = ""
	set_process(not _retired_batches.is_empty())
	if resource == null or not resource.can_instantiate():
		_failed()
		return
	var tree: SceneTree = get_tree() # 旧场景离树后不再访问其 get_tree。
	var target: Node = resource.instantiate() # 只创建一次真实目标；主线程执行节点构造。
	if target == null:
		_failed()
		return
	target.set_meta(&"prepared_resources", _prepared_resources.duplicate())
	target.set_meta(PRESENTATION_META, {
		"presentation": _presentation.snapshot(),
		"requested_at_usec": _requested_at_usec,
		"hint_shown": _hint_shown,
	})
	var callback: Callable = _after_switch # 切场会同步触发旧组件 _exit_tree，先冻结交接回调。
	_after_switch = Callable()
	var status: Error = tree.change_scene_to_node(target) # Godot 4.7：把已构造目标交给 SceneTree。
	if status != OK:
		target.free()
		_failed()
		return
	if callback.is_valid():
		callback.call()

## 统一失败路径：取消等待、丢弃回调、通知宿主并重新揭开原画面。
func _failed() -> void:
	if _load_batch != null:
		_load_batch.cancel()
		if _load_batch.is_running():
			_retired_batches.append(_load_batch)
	_load_batch = null
	_pending_path = ""
	_packed_target = null
	_prepared_resources.clear()
	_after_switch = Callable()
	set_process(not _retired_batches.is_empty())
	_request_failed = true
	transition_failed.emit()
	_reveal()

## 旧式动作仅在实际离场时视为成功；假成功必须回到旧场景。
func _invoke(action: Callable) -> void:
	if not action.is_valid():
		_failed()
		return
	var tree: SceneTree = get_tree()
	var result: Variant = action.call()
	if ((result is bool and result) or (result is int and result == OK)) \
			and tree.current_scene != _source_scene:
		return
	_failed()

## 同一揭幕动作供新场景首次进入及失败恢复复用。
func _reveal() -> void:
	busy = true
	_awaiting_visual_ready = false
	set_process(not _retired_batches.is_empty())
	if not _request_failed:
		_presentation.finish()
	curtain.show()
	_tween = _fade_to(0.0, reveal_seconds)
	_tween.tween_callback(_finish_reveal)

## [param alpha] 目标遮幕透明度；[param seconds] 真实秒数，返回本次 Tween。
func _fade_to(alpha: float, seconds: float) -> Tween:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_ignore_time_scale(true) # 暂停与倍速均不影响揭幕。
	tween.tween_property(curtain, "modulate:a", alpha, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return tween

## 隐藏遮幕节点后才解除输入锁并发送可交互信号。
func _finish_reveal() -> void:
	curtain.hide()
	busy = false
	revealed.emit()

## 键鼠与手柄事件在加载期统一消费，防止穿透到旧场景。
func _input(_event: InputEvent) -> void:
	if busy:
		get_viewport().set_input_as_handled()

## 随源场景销毁时取消渲染回调与动画，不在全局驻留。
func _exit_tree() -> void:
	if RenderingServer.frame_post_draw.is_connected(_on_prepared_frame):
		RenderingServer.frame_post_draw.disconnect(_on_prepared_frame)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if _load_batch != null:
		_load_batch.finish_on_exit()
	for retired: RefCounted in _retired_batches: # 程序关闭时回收剩余引擎请求。
		retired.finish_on_exit()
	_retired_batches.clear()
	_pending_path = ""
	_after_switch = Callable()
