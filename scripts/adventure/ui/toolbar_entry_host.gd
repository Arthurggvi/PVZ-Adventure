extends CanvasLayer
## 工具栏和建筑共用的功能门面/模态所有权；不保存独立解锁或玩家状态。
## 功能元数据，具体条件由原控制器注册。
const Features = preload("res://scripts/adventure/ui/toolbar_features.gd")
## 场景与窗口共用的后台资源批次，不持有全局缓存。
const ResourceBatch = preload("res://scripts/ui/transitions/resource_load_batch.gd")
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
## 模态所属功能；同功能可关闭，其他功能不抢占。
var _modal_feature := ""
## 每次打开、取消、换档和离场都会改变的请求身份。
var _modal_request_id := 0
## 资源准备期间的批次，取消后移入回收列表继续非阻塞轮询。
var _modal_batch: ResourceBatch
## 已取消但底层仍在运行的批次，不允许重新发布窗口。
var _retired_modal_batches: Array[ResourceBatch] = []
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
	var allowed: bool = _host_allowed and _interactive and unlocked and (not is_instance_valid(_modal) or _modal_feature == feature_id) # 所有来源共用。
	return {"known":true,"unlocked":unlocked,"allowed":allowed,"reason":reason}

## [param feature_id] 通过相同条件打开/关闭；返回是否接受请求，失败不产生窗口。
func request_feature(feature_id: String) -> bool:
	var status: Dictionary = feature_status(feature_id) # 提交时重新检查，不能相信上帧hover。
	if not status.allowed:
		return false
	var hook: Dictionary = _hooks[feature_id] # 同一注册调用，不另建研究室或地图。
	if not hook.open.is_valid():
		return false
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
	_modal.closed.connect(_release_modal.bind(_modal))
	_modal.tree_exited.connect(_release_modal.bind(_modal))
	_modal_batch = ResourceBatch.new()
	if _modal_batch.start(PackedStringArray([screen_path])) != OK:
		_modal.show_error("暂时无法打开，请关闭后重试。")
		_retire_modal_batch()

## 控制器每帧调用；只消费已经完成的后台资源，从不等待未完成请求。
func _poll_modal_loading() -> void:
	for index: int in range(_retired_modal_batches.size() - 1, -1, -1): # 取消结果只回收，不再进入界面。
		if _retired_modal_batches[index].poll() != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_retired_modal_batches.remove_at(index)
	if not _modal_loading:
		return
	if not _modal_context_matches():
		_cancel_modal_loading()
		if is_instance_valid(_modal):
			_modal.queue_free()
		_release_modal(_modal)
		return
	if is_instance_valid(_building_modal):
		if not _building_modal.has_method("is_content_ready") or _building_modal.call("is_content_ready"):
			_publish_modal()
		return
	if _modal_batch == null:
		return
	var status: int = _modal_batch.poll() # 状态查询不触发阻塞资源获取。
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
			if _modal_batch.start(paths) != OK:
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
	_building_modal = _modal_script.new() as Control
	if _building_modal == null:
		_modal.show_error("暂时无法打开，请关闭后重试。")
		return
	_building_modal.hide()
	_building_modal.set_meta("preparing_modal", true)
	_building_modal.set_meta("prepared_resources", _modal_resources.duplicate())
	if _request_focus != null:
		_building_modal.set_meta("modal_opener_focus", _request_focus)
	_building_modal.tree_exited.connect(_preparing_modal_exited.bind(request_id))
	add_child(_building_modal)
	_building_modal.set_process_input(false)
	_building_modal.set_process_unhandled_input(false)
	_building_modal.set_process_unhandled_key_input(false)
	move_child(_modal, get_child_count() - 1)

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
	window.set_process_input(true)
	window.set_process_unhandled_input(true)
	window.set_process_unhandled_key_input(true)
	feedback.dismiss() # 已发布窗口立即可交互，旧反馈只作短淡出，不再拥有取消资格。
	move_child(_view, get_child_count() - 1)
	_view.visible = not bool(window.get_meta("covers_toolbar", false))
	window.closed.connect(_release_modal.bind(window))
	window.tree_exited.connect(_release_modal.bind(window))

## 上下文身份必须同时一致，单凭场景名称或玩家名不能识别档案重载。
func _modal_context_matches() -> bool:
	return is_instance_valid(_modal) and is_instance_valid(_request_scene) \
		and get_tree().current_scene == _request_scene \
		and Global.user_manager.curr_user_name == _request_profile \
		and Global.global_game_state != null and Global.global_game_state.adventure_state == _request_state

## 撤销结果发布资格；底层批次继续由当前拥有者回收，不在取消按钮中阻塞。
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

## 将未完成请求移到非阻塞回收队列。
func _retire_modal_batch() -> void:
	if _modal_batch != null:
		retire_resource_batch(_modal_batch)
		_modal_batch = null

## [param batch] 所属窗口关闭后，由持久宿主非阻塞回收已经发出的请求。
func retire_resource_batch(batch: ResourceBatch) -> void:
	batch.cancel()
	_retired_modal_batches.append(batch)

## 仅应用退出时完成尚未结束的资源请求；正常取消和切场不等待。
func _exit_tree() -> void:
	_cancel_modal_loading()
	for batch: ResourceBatch in _retired_modal_batches: # 生命周期结束后没有后续帧可轮询。
		batch.finish_on_exit()

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
