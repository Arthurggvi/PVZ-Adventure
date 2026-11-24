extends CanvasLayer
## 工具栏和建筑共用的功能门面/模态所有权；不保存独立解锁或玩家状态。
## 功能元数据，具体条件由原控制器注册。
const Features = preload("res://scripts/adventure/ui/toolbar_features.gd")
## 场景与窗口共用的后台资源批次，不持有全局缓存。
const ResourceBatch = preload("res://scripts/ui/transitions/resource_load_batch.gd")
## 允许在 Android 主线程窗口构造前记录最后执行步骤。
const Checkpoint = preload("res://scripts/ui/transitions/resource_load_checkpoint.gd")
## 立即接管输入、短请求克制展开的花园反馈，不预载业务界面。
const LoadingView = preload("res://scripts/adventure/ui/modal_loading_view.gd")
## 同一常驻工具栏视图。
var _view: AdventureToolbarView
## 唯一功能注册：id → unlock/open。
var _hooks: Dictionary = {}
## 当前场景是否属于工具栏宿主。
var _host_allowed := false
## 当前宿主是否允许输入（含导航/暂停/场景阻塞）。
var _interactive := false
## 唯一模态窗口引用。
var _modal: Control
## 模态所属功能；重复请求可关闭，切换功能时撤销旧请求。
var _modal_feature := ""
## 每次打开、取消、换档和离场都会改变的请求身份。
var _modal_request_id := 0
## 资源准备期间的批次，取消后移入回收列表继续非阻塞轮询。
var _modal_batch: ResourceBatch
## 请求所属场景、档案对象及玩家名，防止旧结果跨上下文出现。
var _request_scene: Node
## 请求打开时的玩家状态。
var _request_state: AdventureState
## 请求打开时的玩家名。
var _request_profile := ""
## 打开入口原有的键盘焦点，不把临时取消按钮当作窗口的返回目标。
var _request_focus: WeakRef
## 当前后台准备的脚本资源。
var _modal_script: Script
## 是否仍在等待资源或首批界面构造。
var _modal_loading := false
## 已构造但尚未公开的窗口，反馈继续持有输入。
var _building_modal: Control
## 窗口首屏内容构造的业务期限，不能终止正在同步执行的单个构造函数。
const BUILD_READY_TIMEOUT_MSEC := 12_000
## 已入树窗口的构造阶段起点，单位真实毫秒。
var _building_started_msec := 0
## 两阶段准备的资源由窗口持有至关闭，避免动态 load 再次读盘。
var _modal_resources: Array[Resource] = []

## 查询 [param feature_id] 的实时可用性；不触发解锁、领奖或保存。
func feature_status(feature_id: String) -> Dictionary:
	var hook: Dictionary = _hooks.get(feature_id,{}) # 权威注册项。
	if hook.is_empty():
		return {"known":false,"unlocked":false,"allowed":false,"reason":"尚未开放"}
	var unlocked: bool = hook.unlock.is_valid() and hook.unlock.call() == true # 查询既有条件。
	var reason := "" # 给场景入口的简短原因，不形成新状态。
	if not unlocked:
		var loaded: bool = Global.save_service != null and Global.save_service.is_current_profile_loaded() # 当前真实档案状态。
		var requirements := {"research": "领取「初次远征」奖励后开放", "library": "完成「千锤百炼」后开放",
			"shop": "完成「直捣黄龙」并与戴夫交谈后开放"} # 按功能说明进度条件。
		reason = requirements.get(feature_id, "尚未解锁") if loaded else "请先选择存档"
	var allowed: bool = _host_allowed and _interactive and unlocked # 普通功能窗口开启时仍接受工具栏切换。
	return {"known":true,"unlocked":unlocked,"allowed":allowed,"reason":reason}

## [param feature_id] 通过相同条件打开、关闭或替换窗口；返回是否接受请求。
func request_feature(feature_id: String) -> bool:
	var status: Dictionary = feature_status(feature_id) # 提交时重新检查，不能相信上帧hover。
	if not status.allowed:
		return false
	var hook: Dictionary = _hooks[feature_id] # 同一注册调用，不另建研究室或地图。
	if not hook.open.is_valid():
		return false
	if is_instance_valid(_modal) and _modal_feature != feature_id:
		_discard_current_modal()
	var result: Variant = hook.open.call() # 地图可返回失败，普通模态入口为void。
	return result if result is bool else true

## 背景建筑的整体阻塞状态；已有窗口关闭前禁止穿透。
func scene_entries_blocked() -> bool:
	return not _host_allowed or not _interactive or is_instance_valid(_modal)

## 查询 [param feature_id] 的现有窗口，供既有教学及关闭入口复用。
func modal_for(feature_id: String) -> Control:
	return _modal if not _modal_loading and is_instance_valid(_modal) and _modal_feature == feature_id else null

## 注册 [param feature_id] 的唯一条件与动作；本身不修改任何存档。
func register_feature(feature_id: String, unlock_check: Callable, open_action: Callable) -> bool:
	if not Features.is_known(feature_id) or not unlock_check.is_valid() or not open_action.is_valid():
		return false
	_hooks[feature_id] = {"unlock":unlock_check,"open":open_action}
	_refresh()
	return true

## 移除 [param feature_id] 的入口；不影响业务拥有的持久状态。
func unregister_feature(feature_id: String) -> void:
	_hooks.erase(feature_id)
	_refresh()

## [param feature_id] 绑定唯一模态；[param screen] 遵守closed/request_close契约。
func _toggle_modal(feature_id: String, screen_path: String) -> void:
	if not feature_status(feature_id).allowed:
		return
	if is_instance_valid(_modal):
		if _modal_feature == feature_id:
			_modal.request_close()
		return
	_modal_request_id += 1
	_modal_loading = true
	_request_scene = get_tree().current_scene
	_request_state = Global.global_game_state.adventure_state if Global.global_game_state != null else null
	_request_profile = Global.user_manager.curr_user_name
	var opener: Control = get_viewport().gui_get_focus_owner() # 反馈抢占焦点之前记录实际入口。
	_request_focus = weakref(opener) if is_instance_valid(opener) else null
	_modal_script = null
	_modal_resources.clear()
	_modal = LoadingView.new()
	_modal_feature = feature_id
	add_child(_modal)
	move_child(_view, get_child_count() - 1) # 加载中也保留工具栏入口，其他区域由反馈遮罩拦截。
	_modal.closed.connect(_release_modal.bind(_modal))
	_modal.tree_exited.connect(_release_modal.bind(_modal))
	_modal_batch = ResourceBatch.new()
	if _modal_batch.start(PackedStringArray([screen_path]), 12_000) != OK:
		_modal.show_error("暂时无法打开，请关闭后重试。")
		_retire_modal_batch()

## 控制器每帧调用；只消费已经完成的后台资源，从不等待未完成请求。
func _poll_modal_loading() -> void:
	if not _modal_loading:
		return
	if not _modal_context_matches():
		_cancel_modal_loading()
		if is_instance_valid(_modal):
			_modal.queue_free()
		_release_modal(_modal)
		return
	if is_instance_valid(_building_modal):
		if _interactive and (not _building_modal.has_method("is_content_ready") or _building_modal.call("is_content_ready")):
			_publish_modal()
		elif Time.get_ticks_msec() - _building_started_msec >= BUILD_READY_TIMEOUT_MSEC:
			# 取消旧窗口发布资格，保留可关闭的失败反馈。
			var stale_window: Control = _building_modal # 旧构造器退出不能覆盖现有失败反馈。
			_building_modal = null
			_modal_request_id += 1
			stale_window.queue_free()
			_modal.show_error("窗口准备超时，请返回后重试。")
		return
	if _modal_batch == null:
		return
	var status: int = _modal_batch.poll() # 状态查询不触发阻塞资源获取。
	_modal.set_resource_activity(_modal_batch.activity())
	_modal.set_progress(_modal_batch.progress() * 0.15 if _modal_script == null else 0.15 + _modal_batch.progress() * 0.70)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	if status != ResourceLoader.THREAD_LOAD_LOADED:
		_modal.show_error("暂时无法打开，请关闭后重试。")
		_retire_modal_batch()
		return
	_modal_resources.append_array(_modal_batch.resources)
	_modal_batch = null
	if _modal_script == null:
		_modal_script = _modal_resources[0] as Script
		if _modal_script == null or not _modal_script.can_instantiate():
			_modal.show_error("暂时无法打开，请关闭后重试。")
			return
		var paths := PackedStringArray() # 窗口只声明首屏实际动态依赖，不遍历整个游戏目录。
		if _modal_script.has_method("get_initial_resource_paths"):
			paths = _modal_script.call("get_initial_resource_paths")
		if not paths.is_empty():
			_modal_batch = ResourceBatch.new()
			if _modal_batch.start(paths, 12_000) != OK:
				_modal.show_error("暂时无法打开，请关闭后重试。")
				_retire_modal_batch()
			return
	_materialize_modal(_modal_request_id)

## [param request_id] 必须仍为当前请求；留一帧先呈现反馈，再构造已准备的窗口。
func _materialize_modal(request_id: int) -> void:
	await get_tree().process_frame
	if request_id != _modal_request_id or not _modal_context_matches():
		return
	_modal.set_progress(0.92)
	_building_started_msec = Time.get_ticks_msec()
	var token: int = Checkpoint.begin(_modal_script.resource_path, "功能窗口实例化")
	_building_modal = _modal_script.new() as Control
	Checkpoint.finish(token, "ok" if _building_modal != null else "failed")
	if _building_modal == null:
		_modal.show_error("暂时无法打开，请关闭后重试。")
		return
	_building_modal.hide()
	_building_modal.set_meta("preparing_modal", true)
	_building_modal.set_meta("prepared_resources", _modal_resources.duplicate())
	if _request_focus != null:
		_building_modal.set_meta("modal_opener_focus", _request_focus)
	_building_modal.tree_exited.connect(_preparing_modal_exited.bind(request_id))
	var tree_token: int = Checkpoint.begin(_modal_script.resource_path, "功能窗口入树")
	add_child(_building_modal)
	Checkpoint.finish(tree_token)
	_building_modal.set_process_input(false)
	_building_modal.set_process_unhandled_input(false)
	_building_modal.set_process_unhandled_key_input(false)
	move_child(_building_modal, _modal.get_index()) # 新窗口在反馈后方准备，工具栏仍在最上方。

## [param request_id] 对应的窗口在公开前自行退出时恢复可关闭反馈，避免留下等待状态。
func _preparing_modal_exited(request_id: int) -> void:
	if request_id == _modal_request_id and _modal_loading and is_instance_valid(_modal):
		_building_modal = null
		_modal.show_error("窗口已关闭，请取消后重新打开。")

## 首批内容准备好后原子替换反馈；教学只能取得已就绪的真实窗口。
func _publish_modal() -> void:
	var feedback: Control = _modal # 旧反馈的退出回调不能释放新的真实窗口。
	var window: Control = _building_modal # 实例已在主线程构造完成。
	_building_modal = null
	_modal = window
	_modal_loading = false
	_modal_script = null
	_modal_resources.clear()
	window.show()
	window.remove_meta("preparing_modal")
	window.remove_meta("prepared_resources") # 首屏装配完成，实际窗口节点接管资源。
	window.set_process_input(true)
	window.set_process_unhandled_input(true)
	window.set_process_unhandled_key_input(true)
	feedback.dismiss() # 已发布窗口立即可交互，旧反馈只作短淡出，不再拥有取消资格。
	_view.visible = not bool(window.get_meta("covers_toolbar", false))
	window.closed.connect(_release_modal.bind(window))
	window.tree_exited.connect(_release_modal.bind(window))

## 上下文身份必须同时一致，单凭场景名称或玩家名不能识别档案重载。
func _modal_context_matches() -> bool:
	return is_instance_valid(_modal) and is_instance_valid(_request_scene) \
		and get_tree().current_scene == _request_scene \
		and Global.user_manager.curr_user_name == _request_profile \
		and Global.global_game_state != null and Global.global_game_state.adventure_state == _request_state

## 撤销结果发布资格；底层句柄交由加载后端有限回收，不在取消按钮中等待。
func _cancel_modal_loading() -> void:
	_modal_request_id += 1
	_modal_loading = false
	_retire_modal_batch()
	if is_instance_valid(_building_modal):
		_building_modal.queue_free()
	_building_modal = null
	_modal_script = null
	_modal_resources.clear()
	_request_scene = null
	_request_state = null
	_request_profile = ""
	_request_focus = null

## 立即撤销当前请求；底层句柄由后端负责有界回收。
func _retire_modal_batch() -> void:
	if _modal_batch != null:
		retire_resource_batch(_modal_batch)
		_modal_batch = null

## [param batch] 业务请求立即结束，原生线程由后台加载器有限回收。
func retire_resource_batch(batch: ResourceBatch) -> void:
	batch.abandon()

## 宿主退出时只撤销业务交付资格，不等待后台线程。
func _exit_tree() -> void:
	_cancel_modal_loading()

## 切换功能时立即移除旧窗口的输入和发布资格，资源继续异步回收。
func _discard_current_modal() -> void:
	var window: Control = _modal # 可能是加载反馈，也可能是已就绪的窗口。
	window.hide()
	window.process_mode = Node.PROCESS_MODE_DISABLED
	_release_modal(window)
	window.queue_free()

## 仅释放 [param window] 自身；旧回调不能清空新实例。
func _release_modal(window: Control) -> void:
	if _modal == window:
		_cancel_modal_loading()
		_modal = null
		_modal_feature = ""
		if is_instance_valid(_view):
			_view.show() # 页面释放后恢复之前的展开状态，不重建工具栏。

## 工具栏按钮也必须经过公开门面。
func _on_feature_pressed(feature_id: String) -> void:
	request_feature(feature_id)

## 由控制器覆盖，只更新表现，不创建第二套业务状态。
func _refresh() -> void:
	pass
