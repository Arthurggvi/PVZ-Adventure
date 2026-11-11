## 工具栏宿主与统一模态窗口管理；业务状态始终来自当前玩家档案。
extends CanvasLayer

## 工具栏纯表现及按钮交互。
const View = preload("res://scripts/adventure/ui/toolbar_view.gd")
## 功能元数据与地图入口条件。
const Features = preload("res://scripts/adventure/ui/toolbar_features.gd")
## 普通背包窗口。
const Inventory = preload("res://scripts/adventure/ui/inventory_window.gd")
## 研究室场景外壳。
const Research = preload("res://scripts/adventure/ui/research_lab_stage.gd")
## 角色窗口接入同一模态生命周期。
const Player = preload("res://scripts/adventure/ui/player_window.gd")
## 主菜单与工具栏共用设置窗口，并参与工具栏模态互斥。
const Settings = preload("res://scripts/ui/game_settings_window.gd")
## 任务面板复用工具栏模态窗口入口。
const Quests = preload("res://scripts/adventure/ui/quest_window.gd")
## 冒险图鉴复用同一模态生命周期，独立于原版图鉴场景。
const Almanac = preload("res://scripts/adventure/ui/almanac_window.gd")
## 首关后教学编排使用独立表现层，不占用任务或研究服务职责。
const Onboarding = preload("res://scripts/adventure/ui/quest_onboarding.gd")
## 教学层随当前宿主销毁表现，业务节点随档案保存。
var _onboarding: CanvasLayer
## 识别档案对象替换，及时释放旧档案的模态窗口和教学引用。
var _bound_state: AdventureState
## 地图导航窗口及切场编排。
const MapNavigation = preload("res://scripts/adventure/ui/map_navigation.gd")
## 只有显式加入该组的场景显示工具栏。
const HOST_GROUP := &"adventure_toolbar_surface"
## 常驻工具栏视图。
var _view: AdventureToolbarView
## 功能 ID 到解锁判断和打开动作。
var _hooks: Dictionary = {}
## 当前宿主是否允许展示工具栏。
var _host_allowed := false
## 暂停、导航或宿主阻塞后的实际交互状态。
var _interactive := false
## 当前场景身份，用于切场时释放表现引用。
var _host_scene: Node
## 当前唯一模态窗口，所有功能共享互斥与切场清理。
var _modal: Control
## 当前模态所属功能，决定再次点击是否关闭。
var _modal_feature: String = ""
## 导航控制节点，不持有玩家资产。
var _navigation: Node

func _ready() -> void:
	layer = 50 # Below existing SceneTransition (100), above ordinary map art.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_view = View.new()
	_view.name = "ToolbarView"
	add_child(_view)
	_view.feature_pressed.connect(_on_feature_pressed)
	_navigation = MapNavigation.new()
	_navigation.name = "MapNavigation"
	add_child(_navigation)
	_navigation.navigation_state_changed.connect(_sync_input)
	get_tree().scene_changed.connect(_on_scene_changed)
	Global.user_manager.signal_users_update.connect(_refresh)
	Global.quests_changed.connect(_refresh)
	register_feature("inventory", Callable(self, "_can_open_inventory"), Callable(self, "_open_inventory"))
	register_feature("research", Callable(self, "can_open_research"), Callable(self, "_open_research"))
	register_feature("quests", Callable(self, "_can_open_quests"), Callable(self, "_open_quests"))
	register_feature("almanac", Callable(self, "_can_open_inventory"), Callable(self, "_open_almanac"))
	register_feature("player", Callable(self, "_can_open_player"), Callable(self, "_open_player"))
	register_feature("settings", Callable(self, "_can_open_settings"), toggle_settings)
	_onboarding = Onboarding.new()
	_onboarding.toolbar = self
	add_child(_onboarding)
	_on_scene_changed()

func _process(_delta: float) -> void:
	var current: AdventureState = Global.global_game_state.adventure_state # 重命名不替换状态对象，因此不会误关窗口。
	if current != _bound_state:
		_bound_state = current
		_apply_host_scene(get_tree().current_scene)
	# Scene ownership controls visibility; temporary modal input locks never hide the HUD.
	_sync_input()
	if _host_allowed and _view._available.get("inventory", false) != _can_open_inventory():
		_refresh()

func _sync_input() -> void:
	var allowed: bool = _host_allowed and is_instance_valid(_host_scene) and not get_tree().paused \
		and not _navigation.is_open()
	if allowed and _host_scene.has_method("is_adventure_toolbar_blocked"):
		allowed = not bool(_host_scene.call("is_adventure_toolbar_blocked"))
	if allowed == _interactive:
		return
	_interactive = allowed
	_view.set_interaction_enabled(allowed)

## SceneTree.scene_changed can be delivered with zero or one argument across launch paths.
## Resolve the authoritative current scene after the notification, not from its payload.
func _on_scene_changed(_signal_scene: Node = null) -> void:
	_sync_scene_from_tree.call_deferred()

func _sync_scene_from_tree() -> void:
	_apply_host_scene(get_tree().current_scene)

func _apply_host_scene(scene: Node) -> void:
	if is_instance_valid(_onboarding):
		_onboarding.reset()
	_navigation.close()
	if is_instance_valid(_modal):
		_modal.queue_free()
	_modal = null
	_modal_feature = ""
	_host_scene = scene
	_view.reset_for_scene()
	_host_allowed = is_instance_valid(scene) and scene.is_in_group(HOST_GROUP)
	visible = _host_allowed
	_sync_input()
	_refresh()

## Same navigation entry for the menu ship and any map toolbar.
func open_map_navigation() -> bool:
	if not _host_allowed or not is_instance_valid(_host_scene) or is_instance_valid(_modal):
		return false
	return _navigation.open_from(_host_scene)

func _can_open_inventory() -> bool:
	return Global.save_service != null and Global.save_service.is_current_profile_loaded() \
		and Global.adventure_inventory != null and Global.global_game_state.adventure_state != null

## 首关普通阶段通关前不能打开任务；与灰显图标共用同一个入口条件。
func _can_open_quests() -> bool:
	return _can_open_inventory() and AdventureQuestService.quests_unlocked(Global.global_game_state.adventure_state)

## 背包入口复用统一窗口管理，不自行维护其他窗口的互斥列表。
func _open_inventory() -> void:
	_toggle_modal("inventory", Inventory)

## 研究室解锁与当前加载档案共用权威任务条件。
func can_open_research() -> bool:
	return _can_open_inventory() and AdventureQuestService.feature_unlocked(Global.global_game_state.adventure_state, "research")

## 教学和普通按钮使用同一研究室入口，不绕过宿主与模态校验。
func open_research() -> void:
	if _host_allowed and _interactive and can_open_research():
		_open_research()

## 研究室窗口的构造由此唯一指定。
func _open_research() -> void:
	_toggle_modal("research", Research)

## 任务窗口的构造由此唯一指定。
func _open_quests() -> void:
	_toggle_modal("quests", Quests)

## 图鉴按当前已加载档案的发现记录展示，不增加任务或阶级门槛。
func _open_almanac() -> void:
	_toggle_modal("almanac", Almanac)

## 角色无需独立解锁进度；有效档案且不在冒险战斗时可以访问。
func _can_open_player() -> bool:
	return _can_open_inventory() and not AdventureSession.owns_battle(Global.game_para)

## 角色窗口的构造由此唯一指定。
func _open_player() -> void:
	_toggle_modal("player", Player)

## 支持工具栏的宿主均可打开设置，无需加载档案。
func _can_open_settings() -> bool:
	return _host_allowed

## 主菜单按钮和工具栏齿轮共用入口、互斥与关闭行为。
func toggle_settings() -> void:
	_toggle_modal("settings", Settings)

## 查询 [param feature_id] 的当前窗口；返回 null 表示未打开，不暴露额外生命周期状态。
func modal_for(feature_id: String) -> Control:
	return _modal if is_instance_valid(_modal) and _modal_feature == feature_id else null

## [param feature_id] 同功能再次点击关闭；其他模态存在时不抢占。
## [param screen] 必须提供 closed 信号和 request_close 方法；当前内置窗口遵守同一契约。
func _toggle_modal(feature_id: String, screen: Script) -> void:
	if not _host_allowed or not _interactive:
		return
	if is_instance_valid(_modal):
		if _modal_feature == feature_id:
			_modal.request_close()
		return
	var hook: Dictionary = _hooks.get(feature_id, {}) # 打开前重验解锁条件，不能相信上帧图标。
	if hook.is_empty() or hook.unlock.call() != true:
		return
	var window: Control = screen.new() # 当前局部身份被关闭回调捕获，避免旧窗口清空新窗口。
	_modal = window
	_modal_feature = feature_id
	add_child(window)
	move_child(_view, get_child_count() - 1)
	window.closed.connect(_release_modal.bind(window))
	window.tree_exited.connect(_release_modal.bind(window))

## 仅释放 [param window] 自身的引用；切场旧回调不能污染新宿主的窗口。
func _release_modal(window: Control) -> void:
	if _modal == window:
		_modal = null
		_modal_feature = ""

## Additional modules register a real screen and its actual unlock predicate here.
## Registration alone never changes a player's stored progress.
func register_feature(feature_id: String, unlock_check: Callable, open_action: Callable) -> bool:
	if feature_id == "map" \
		or not Features.is_known(feature_id) or not unlock_check.is_valid() or not open_action.is_valid():
		return false
	_hooks[feature_id] = {"unlock": unlock_check, "open": open_action}
	_refresh()
	return true

func unregister_feature(feature_id: String) -> void:
	_hooks.erase(feature_id)
	_refresh()

func _refresh() -> void:
	if not is_instance_valid(_view):
		return
	var enabled: Dictionary = {"map": Features.can_open_map()}
	for id: String in _hooks:
		var entry: Dictionary = _hooks[id]
		if entry.unlock.is_valid() and entry.open.is_valid():
			enabled[id] = entry.unlock.call() == true
	_view.refresh(enabled)
	_view.set_quest_attention(_can_open_quests() and AdventureQuestService.has_claimable(Global.global_game_state.adventure_state))

## 为教学提供已校验的当前上下文；背包等其他模态存在时不抢占输入。
func guide_context() -> Dictionary:
	return {"ready": _host_allowed and _interactive and _can_open_inventory() and (not is_instance_valid(_modal) or _modal_feature in ["quests", "research"]),
		"state": Global.global_game_state.adventure_state if _can_open_inventory() else null,
		"quests": modal_for("quests"), "research": modal_for("research")}

## 展开并定位 [param feature_id] 的真实按钮；不绕过正常功能入口。
func guide_feature(feature_id: String) -> Control:
	return _view.guide_feature(feature_id)

## 戴夫和研究室教学开始前关闭任务窗口；领奖表现期间调用方等待其结束。
func close_quests_for_guide() -> void:
	var quests: Control = modal_for("quests") # 教学只能关闭自身需要交接的任务窗口。
	if quests != null:
		quests.request_close()

func _on_feature_pressed(feature_id: String) -> void:
	if not _host_allowed or not _interactive:
		return
	# 所有功能共享同一互斥判断，新增角色不增加交叉分支。
	if is_instance_valid(_modal) and feature_id != _modal_feature:
		return
	if feature_id == "map":
		if Features.can_open_map():
			open_map_navigation()
		return
	if not _hooks.has(feature_id):
		return
	var entry: Dictionary = _hooks[feature_id]
	if entry.unlock.is_valid() and entry.unlock.call() == true and entry.open.is_valid():
		entry.open.call()
