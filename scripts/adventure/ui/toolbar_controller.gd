## 工具栏宿主与统一模态窗口管理；业务状态始终来自当前玩家档案。
extends "res://scripts/adventure/ui/toolbar_entry_host.gd"

## 工具栏纯表现及按钮交互。
const View = "res://scripts/adventure/ui/toolbar_view.gd"
## 普通背包窗口。
const Inventory = "res://scripts/adventure/ui/inventory_window.gd"
## 研究室场景外壳。
const Research = "res://scripts/adventure/ui/research_lab_stage.gd"
## 角色窗口接入同一模态生命周期。
const Player = "res://scripts/adventure/ui/player_window.gd"
## 设置窗口参与工具栏模态互斥。
const Settings = "res://scripts/ui/game_settings_window.gd"
## 任务面板复用工具栏模态窗口入口。
const Quests = "res://scripts/adventure/ui/quest_window.gd"
## 冒险图鉴复用同一模态生命周期，独立于原版图鉴场景。
const Almanac = "res://scripts/adventure/ui/almanac_window.gd"
## 图书馆建筑使用独立书籍面板，复用相同模态生命周期。
const Library = "res://scripts/adventure/ui/library_window.gd"
## 戴夫全屏商店复用建筑入口与统一模态生命周期。
const Shop = "res://scripts/adventure/shop/shop_window.gd"
## 首关后教学编排使用独立表现层，不占用任务或研究服务职责。
const Onboarding = "res://scripts/adventure/ui/quest_onboarding.gd"
## 教学层随当前宿主销毁表现，业务节点随档案保存。
var _onboarding: CanvasLayer
## 识别档案对象替换，及时释放旧档案的模态窗口和教学引用。
var _bound_state: AdventureState
## 地图导航窗口及切场编排。
const MapNavigation = "res://scripts/adventure/ui/map_navigation.gd"
## 只有显式加入该组的场景显示工具栏。
const HOST_GROUP := &"adventure_toolbar_surface"
## 当前场景身份，用于切场时释放表现引用。
var _host_scene: Node
## 导航控制节点，不持有玩家资产。
var _navigation: Node

func _ready() -> void:
	layer = 50 # 高于普通地图、低于 SceneTransition 的 100 层遮幕。
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Bootstrap 不具备工具栏宿主资格，当前只注册业务回调，不创建 HUD 或窗口。
	get_tree().scene_changed.connect(_on_scene_changed)
	Global.user_manager.signal_users_update.connect(_refresh)
	Global.quests_changed.connect(_refresh)
	register_feature("map", Features.can_open_map, Callable(self,"_open_map"))
	register_feature("inventory", Callable(self, "_can_open_inventory"), Callable(self, "_open_inventory"))
	register_feature("research", Callable(self, "can_open_research"), Callable(self, "_open_research"))
	register_feature("quests", Callable(self, "_can_open_quests"), Callable(self, "_open_quests"))
	register_feature("almanac", Callable(self, "_can_open_inventory"), Callable(self, "_open_almanac"))
	register_feature("library", Callable(self, "_can_open_library"), Callable(self, "_open_library"))
	register_feature("player", Callable(self, "_can_open_player"), Callable(self, "_open_player"))
	register_feature("shop", Callable(self, "_can_open_shop"), Callable(self, "_open_shop"))
	register_feature("settings", Callable(self, "_can_open_settings"), toggle_settings)
	_on_scene_changed()

## 唯一表现层创建入口，只在有效游戏宿主上构造工具栏、导航与教学。
func _ensure_presenter() -> void:
	if is_instance_valid(_view):
		return
	_view = (load(View) as Script).new() as AdventureToolbarView
	_view.name = "ToolbarView"
	add_child(_view)
	_view.feature_pressed.connect(_on_feature_pressed)
	_navigation = (load(MapNavigation) as Script).new()
	_navigation.name = "MapNavigation"
	add_child(_navigation)
	_navigation.navigation_state_changed.connect(_sync_input)
	_onboarding = (load(Onboarding) as Script).new()
	_onboarding.toolbar = self
	add_child(_onboarding)

## [param _delta] 为帧间隔，档案切换期间没有状态时也继续更新工具栏。
func _process(_delta: float) -> void:
	# current 是当前档案的冒险状态；无档案时清理旧窗口。
	var current: AdventureState = Global.global_game_state.adventure_state if Global.global_game_state != null else null
	if current != _bound_state:
		_bound_state = current
		_apply_host_scene(get_tree().current_scene)
	# 场景控制工具栏整体可见性，模态和导航只禁止输入，不复制 HUD。
	_sync_input()
	if _host_allowed and is_instance_valid(_view) and _view._available.get("inventory", false) != _can_open_inventory():
		_refresh()

func _sync_input() -> void:
	var allowed: bool = _host_allowed and is_instance_valid(_host_scene) and not get_tree().paused \
		and is_instance_valid(_navigation) and not _navigation.is_open()
	if allowed and _host_scene.has_method("is_adventure_toolbar_blocked"):
		allowed = not bool(_host_scene.call("is_adventure_toolbar_blocked"))
	if allowed == _interactive:
		return
	_interactive = allowed
	if is_instance_valid(_view):
		_view.set_interaction_enabled(allowed)

## SceneTree.scene_changed 参数随入口不同；延迟读取权威 current_scene。
func _on_scene_changed(_signal_scene: Node = null) -> void:
	_sync_scene_from_tree.call_deferred()

func _sync_scene_from_tree() -> void:
	_apply_host_scene(get_tree().current_scene)

func _apply_host_scene(scene: Node) -> void:
	if is_instance_valid(_onboarding):
		_onboarding.reset()
	if is_instance_valid(_navigation):
		_navigation.close()
	if is_instance_valid(_modal):
		_modal.queue_free()
	_modal = null
	_modal_feature = ""
	_host_scene = scene
	_host_allowed = is_instance_valid(scene) and scene.is_in_group(HOST_GROUP)
	if _host_allowed:
		_ensure_presenter()
		_view.reset_for_scene()
		_view.show()
	visible = _host_allowed
	_sync_input()
	_refresh()

## 海滨港口与岛屿工具栏共用地图导航门面。
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

## 当前档案完成千锤百炼后才允许通过建筑和教学入口打开图书馆。
func _can_open_library() -> bool:
	return _can_open_inventory() and AdventureQuestService.feature_unlocked(Global.global_game_state.adventure_state, "library")

## 图书馆窗口复用统一模态生命周期。
func _open_library() -> void:
	_toggle_modal("library", Library)

## 商店需要当前档案完成开店剧情，且当前不在冒险战斗中。
func _can_open_shop() -> bool:
	return _can_open_player() and AdventureQuestService.feature_unlocked(Global.global_game_state.adventure_state, "shop")

## 主菜单商店建筑进入全屏戴夫页面。
func _open_shop() -> void:
	_toggle_modal("shop", Shop)

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
	return {"ready": _host_allowed and _interactive and _can_open_inventory() and (not is_instance_valid(_modal) or _modal_feature in ["quests", "research", "library"]),
		"state": Global.global_game_state.adventure_state if _can_open_inventory() else null,
		"quests": modal_for("quests"), "research": modal_for("research"), "library": modal_for("library")}

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
