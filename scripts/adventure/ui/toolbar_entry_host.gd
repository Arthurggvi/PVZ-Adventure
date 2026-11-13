extends CanvasLayer
## 工具栏和建筑共用的功能门面/模态所有权；不保存独立解锁或玩家状态。
## 功能元数据，具体条件由原控制器注册。
const Features = preload("res://scripts/adventure/ui/toolbar_features.gd")
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

## 查询 [param feature_id] 的实时可用性；不触发解锁、领奖或保存。
func feature_status(feature_id: String) -> Dictionary:
	var hook: Dictionary = _hooks.get(feature_id,{}) # 权威注册项。
	if hook.is_empty():
		return {"known":false,"unlocked":false,"allowed":false,"reason":"尚未开放"}
	var unlocked: bool = hook.unlock.is_valid() and hook.unlock.call() == true # 查询既有条件。
	var reason := "" # 给场景入口的简短原因，不形成新状态。
	if not unlocked:
		var loaded: bool = Global.save_service != null and Global.save_service.is_current_profile_loaded() # 当前真实档案状态。
		var requirements := {"research": "领取「初次远征」奖励后开放", "library": "完成「千锤百炼」后开放"} # 按功能说明进度条件。
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
	return _modal if is_instance_valid(_modal) and _modal_feature == feature_id else null

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
func _toggle_modal(feature_id: String, screen: Script) -> void:
	if not feature_status(feature_id).allowed:
		return
	if is_instance_valid(_modal):
		if _modal_feature == feature_id:
			_modal.request_close()
		return
	var window: Control = screen.new() # 唯一窗口实例，不复制另一套生命周期。
	_modal = window
	_modal_feature = feature_id
	add_child(window)
	move_child(_view,get_child_count()-1)
	window.closed.connect(_release_modal.bind(window))
	window.tree_exited.connect(_release_modal.bind(window))

## 仅释放 [param window] 自身；旧回调不能清空新实例。
func _release_modal(window: Control) -> void:
	if _modal == window:
		_modal = null
		_modal_feature = ""

## 工具栏按钮也必须经过公开门面。
func _on_feature_pressed(feature_id: String) -> void:
	request_feature(feature_id)

## 由控制器覆盖，只更新表现，不创建第二套业务状态。
func _refresh() -> void:
	pass
