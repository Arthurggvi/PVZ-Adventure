## 统一场景遮幕与资源加载控制器；启动、世界地图与战斗共用一条管线。
## 不持有用户存档或业务状态，且不在全局创建第二份场景缓存。
extends CanvasLayer
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
## 延迟显示加载百分比的秒数，避免短切场闪烁提示。
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
## Godot 资源加载百分比容器，范围 0 至 1。
var _loading_progress: Array[float] = []
## 负责输入拦截和统一遮幕的不透明层。
@onready var curtain: ColorRect = $Curtain
## 不可交互的进度文字，短切场保持隐藏。
@onready var loading_label: Label = $Curtain/LoadingLabel

## 初始化仅负责表现；Boot 场景可明确禁用入树揭幕。
func _ready() -> void:
	set_process(false)
	loading_label.hide()
	if not reveal_on_ready:
		curtain.modulate.a = 0.0
		curtain.hide()
		return
	busy = true
	curtain.show()
	curtain.modulate.a = 1.0
	if DisplayServer.get_name() == "headless":
		_reveal.call_deferred()
	else:
		_prepare_frames = 2
		RenderingServer.frame_post_draw.connect(_on_prepared_frame)

## 父场景可公开 is_visual_ready()，视觉未准备好时不计入两帧揭幕屏障。
func _on_prepared_frame() -> void:
	var host: Node = get_parent()
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
	_source_scene = get_tree().current_scene
	curtain.show()
	_tween = _fade_to(1.0, cover_seconds)
	_tween.tween_callback(_invoke.bind(action))
	return true

## [param scene_path] 只允许已存在的 res:// PackedScene；不允许其他文件路径。
## [param after_switch] 仅在目标被 SceneTree 接受后、_ready 前执行一次。
## 返回值只表示请求已接受；加载失败发出 transition_failed 并恢复输入。
func change_scene(scene_path: String, after_switch: Callable = Callable()) -> bool:
	if busy or not scene_path.begins_with("res://") or not ResourceLoader.exists(scene_path, "PackedScene"):
		return false
	busy = true
	_source_scene = get_tree().current_scene
	_after_switch = after_switch
	_requested_at_usec = Time.get_ticks_usec()
	_loading_progress.clear()
	loading_label.hide()
	curtain.show()
	_tween = _fade_to(1.0, cover_seconds)
	_tween.tween_callback(_start_threaded_load.bind(scene_path))
	return true

## 遮幕完全覆盖后才请求后台线程加载，不让同步读取阻塞可见过渡。
func _start_threaded_load(scene_path: String) -> void:
	var result: Error = ResourceLoader.load_threaded_request(scene_path, "PackedScene", true)
	if result != OK:
		_failed()
		return
	_pending_path = scene_path
	set_process(true)

## 每帧只查询加载状态；禁止在未完成时调用会阻塞的 load_threaded_get。
func _process(_delta: float) -> void:
	if _pending_path.is_empty():
		return
	_loading_progress.clear()
	var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(
		_pending_path, _loading_progress)
	match status:
		ResourceLoader.THREAD_LOAD_LOADED:
			_finish_threaded_load()
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_failed()
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			var elapsed := float(Time.get_ticks_usec() - _requested_at_usec) / 1000000.0
			if elapsed >= loading_hint_delay:
				loading_label.show()
				var amount: float = clampf(_loading_progress[0], 0.0, 1.0) if not _loading_progress.is_empty() else 0.0
				loading_label.text = "正在加载 %d%%" % roundi(amount * 100.0)

## 目标资源确认完成后唯一提交切场；交接发生于新场景入树前。
func _finish_threaded_load() -> void:
	var resource: PackedScene = ResourceLoader.load_threaded_get(_pending_path) as PackedScene
	_pending_path = ""
	set_process(false)
	if resource == null or not resource.can_instantiate():
		_failed()
		return
	var tree: SceneTree = get_tree()
	var status: Error = tree.change_scene_to_packed(resource)
	if status != OK:
		_failed()
		return
	if _after_switch.is_valid():
		_after_switch.call()
	_after_switch = Callable()

## 统一失败路径：取消等待、丢弃回调、通知宿主并重新揭开原画面。
func _failed() -> void:
	_pending_path = ""
	_after_switch = Callable()
	set_process(false)
	loading_label.hide()
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
	loading_label.hide()
	curtain.show()
	_tween = _fade_to(0.0, reveal_seconds)
	_tween.tween_callback(_finish_reveal)

## [param alpha] 目标遮幕透明度；[param seconds] 真实秒数，返回本次 Tween。
func _fade_to(alpha: float, seconds: float) -> Tween:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_ignore_time_scale(true)
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
	if not _pending_path.is_empty():
		# 仅退出时回收未完成的 Godot 线程加载；正常过渡绝不等待资源。
		var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(_pending_path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS or status == ResourceLoader.THREAD_LOAD_LOADED:
			ResourceLoader.load_threaded_get(_pending_path)
		_pending_path = ""
		_after_switch = Callable()
