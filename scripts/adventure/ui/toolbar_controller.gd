## 工具栏宿主与统一模态窗口管理；业务状态始终来自当前玩家档案。
extends "res://scripts/adventure/ui/toolbar_entry_host.gd"

## 工具栏纯表现及按钮交互。
const View = preload("res://scripts/adventure/ui/toolbar_view.gd")
## 普通背包窗口。
const Inventory = preload("res://scripts/adventure/ui/inventory_window.gd")
## 研究室场景外壳。
const Research = preload("res://scripts/adventure/ui/research_lab_stage.gd")
## 角色窗口接入同一模态生命周期。
const Player = preload("res://scripts/adventure/ui/player_window.gd")
## 设置窗口参与工具栏模态互斥。
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
## 当前场景身份，用于切场时释放表现引用。
var _host_scene: Node
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
	register_feature("map", Features.can_open_map, Callable(self,"_open_map"))
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

## [param _delta] 为帧间隔，档案切换期间没有状态时也继续更新工具栏。
func _process(_delta: float) -> void:
	# current 是当前档案的冒险状态；无档案时清理旧窗口。
	var current: AdventureState = Global.global_game_state.adventure_state if Global.global_game_state != null else null
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

## [param scene] 为当前真实宿主；清理旧表现后读取其显式停靠偏好，不改变功能注册或解锁条件。
func _apply_host_scene(scene: Node) -> void:
	if is_instance_valid(_onboarding):
		_onboarding.reset()
	_navigation.close()
	if is_instance_valid(_modal):
		_modal.queue_free()
	_modal = null
	_modal_feature = ""
	_host_scene = scene
	var coastal: bool = is_instance_valid(scene) and scene.has_method("uses_coastal_dock") \
		and bool(scene.call("uses_coastal_dock")) # 只有宿主显式启用海滨停靠，其余地图和战斗保持原样。
	_view.set_coastal_presentation(coastal)
	_view.reset_for_scene()
	_host_allowed = is_instance_valid(scene) and scene.is_in_group(HOST_GROUP)
	visible = _host_allowed
	_sync_input()
	_refresh()

## Same navigation entry for the menu ship and any map toolbar.
func open_map_navigation() -> bool:
	return request_feature("map")

## 门面校验后的既有地图导航动作。
func _open_map() -> bool:
	if not _host_allowed or not is_instance_valid(_host_scene) or is_instance_valid(_modal):
		return false
	return _navigation.open_from(_host_scene)

func _can_open_inventory() -> bool:
	return Global.save_service != null and Global.save_service.is_current_profile_loaded() \
		and Global.adventure_inventory != null and Global.global_game_state != null \
		and Global.global_game_state.adventure_state != null

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
	request_feature("research")

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

## 从工具栏齿轮打开设置，沿用模态互斥和关闭行为。
func toggle_settings() -> void:
	_toggle_modal("settings", Settings)

func _refresh() -> void:
	if not is_instance_valid(_view):
		return
	var enabled: Dictionary = {}
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

## 教学遮罩不属于普通模态窗口，但不能透传到背景建筑。
func scene_entries_blocked() -> bool:
	return super.scene_entries_blocked() or (is_instance_valid(_onboarding) and _onboarding.blocks_scene_entries())
