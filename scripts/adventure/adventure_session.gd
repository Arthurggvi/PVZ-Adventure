## 冒险会话边界：地区状态存放 AdventureState，资产使用同一库存服务、同一玩家存档。
extends Node
const MAP_SCENE := "res://scenes/adventure/zombie_island.tscn"
const Progress = preload("res://scripts/adventure/island_progress.gd")
signal battle_finished(stage_id: int, result: String)
var progress: RefCounted
var active_level: ResourceLevelData
var active_stage_number: int = 0
var active_phase_kind: int = 0
## 当前战斗独有的波次资源快照，场景内不重复读磁盘配置。
var active_wave_profile: WaveProfile
## 本局已冻结的玩家卡数据；不写玩家存档、不反向修改背包。
var battle_loadout: Array[Dictionary] = []
var notice := ""
var battle_failed := false
var adventure_active := false
var entry_error := ""
var error_message := ""
func _ready() -> void:
	Global.user_manager.signal_users_update.connect(_on_profile_changed)
func _on_profile_changed() -> void:
	progress = null
	active_level = null
	active_stage_number = 0
	active_phase_kind = 0
	active_wave_profile = null
	battle_loadout.clear()
	adventure_active = false
func open_adventure() -> bool:
	if adventure_active:
		return true
	progress = null
	entry_error = ""
	error_message = ""
	var profile: String = Global.user_manager.curr_user_name
	if profile.is_empty() or not Global.user_manager.all_user_name.has(profile) \
		or not DirAccess.dir_exists_absolute("user://" + profile):
		entry_error = "请先从主菜单左上角创建或选择玩家档案。"
		return false
	progress = Progress.new(Global.global_game_state.adventure_state)
	if not progress.started:
		progress.start()
		if not Global.save_service.save_now():
			progress = null
			entry_error = "无法保存冒险初始化状态。"
			return false
	notice = ""
	return_to_map()
	return true
func is_unlocked(stage_id: int) -> bool:
	return stage_id == 1 or (stage_id == 2 and progress != null and progress.stage_1_cleared)
## 新手赠卡只检查持久领取标记；重复播放对话、跳过均不重复发放。
func grant_starter_cards() -> bool:
	if progress == null or not progress.started:
		error_message = "冒险尚未开始。"
		return false
	var state: AdventureState = Global.global_game_state.adventure_state
	if state.claimed_rewards.get("intro_starter_cards", false):
		return true
	var inventory: AdventureInventoryService = Global.adventure_inventory
	var sunflower_uid: String = inventory.add_card(CharacterRegistry.PlantType.P002SunFlower)
	var peashooter_uid: String = inventory.add_card(CharacterRegistry.PlantType.P001PeaShooterSingle)
	if sunflower_uid.is_empty() or peashooter_uid.is_empty():
		if not sunflower_uid.is_empty():
			inventory.remove_card(sunflower_uid)
		if not peashooter_uid.is_empty():
			inventory.remove_card(peashooter_uid)
		error_message = "初始植物卡创建失败。"
		return false
	if state.selected_card_uids.is_empty():
		state.selected_card_uids = [sunflower_uid, peashooter_uid]
	state.claimed_rewards["intro_starter_cards"] = true
	if not Global.save_service.save_now():
		error_message = "无法保存初始植物卡。"
		return false
	error_message = ""
	return true
func complete_intro() -> bool:
	if not grant_starter_cards() or not progress.complete_intro():
		return false
	if not Global.save_service.save_now():
		error_message = "无法保存引导进度。"
		return false
	error_message = ""
	return true
## 冒险战斗强制僵尸预览与可交互 UID 选卡；玩家确认时才冻结战斗快照。
func enter_lawn() -> void:
	enter_stage(1, StagePhaseDefinition.Kind.NORMAL)
## 统一配置入口；场景、卡槽、波次种类均由已验证的 StageDefinition 生成。
func enter_stage(stage_number: int, phase_kind: int) -> bool:
	if progress == null or not progress.intro_completed:
		return false
	error_message = AdventureStageCatalog.entry_error(
		stage_number, phase_kind, Global.global_game_state.adventure_state, Global.adventure_inventory)
	if not error_message.is_empty():
		return false
	var level: ResourceLevelData = AdventureStageCatalog.build_level(stage_number, phase_kind)
	if level == null:
		error_message = "无法生成该阶段的原版战斗模板。"
		return false
	var stage: StageDefinition = AdventureStageCatalog.load_stage(stage_number)
	var phase: StagePhaseDefinition = AdventureStageCatalog.find_phase(stage, phase_kind)
	if phase == null or phase.wave_profile == null:
		error_message = "冒险波次数据未就绪。"
		return false
	battle_loadout.clear()
	active_stage_number = stage_number
	active_phase_kind = phase_kind
	active_wave_profile = phase.wave_profile.duplicate(true)
	active_level = level
	battle_failed = false
	Global.game_para = active_level
	var err := get_tree().change_scene_to_file(Global.main_scene_registry.MainScenesMap[level.game_sences])
	if err != OK:
		active_level = null
		active_stage_number = 0
		active_phase_kind = 0
		active_wave_profile = null
		Global.game_para = null
		error_message = "草坪场景加载失败。"
		return false
	return true
## 接收备战画面按 UID 选择的卡，仅确认时冻结快照和更新当前玩家的历史卡组。
func confirm_selected_cards(cards: Array[Card]) -> bool:
	if not owns_battle(Global.game_para) or cards.is_empty() or cards.size() > active_level.max_choosed_card_num:
		return false
	var inventory: AdventureInventoryService = Global.adventure_inventory
	var uids: Array[String] = []
	for card: Card in cards:
		var uid: String = str(card.battle_card_data.get("uid", ""))
		var current: Dictionary = inventory.get_card(uid)
		if current.is_empty() or int(current.get("plant_type", -1)) != card.card_reference.content_id:
			return false
		uids.append(uid)
	var state: AdventureState = Global.global_game_state.adventure_state
	var previous_uids: Array[String] = state.selected_card_uids.duplicate()
	if not inventory.set_deck(uids):
		return false
	var snapshot: Array[Dictionary] = AdventureBattleAdapter.create_loadout(state)
	if snapshot.size() != cards.size() or not Global.save_service.save_now():
		state.selected_card_uids = previous_uids
		return false
	battle_loadout = snapshot
	for index: int in range(cards.size()):
		cards[index].battle_card_data = snapshot[index].duplicate(true)
	return true
## 仅供原版预选卡槽获取对应序号的冻结身份；普通模式不走此入口。
func get_prechosen_battle_data(slot_index: int, reference: ResourceCardReference) -> Dictionary:
	if active_level == null:
		return {}
	return AdventureBattleAdapter.binding_at(battle_loadout, slot_index, reference)
func owns_battle(level: ResourceLevelData) -> bool:
	return active_level != null and active_level == level

func get_active_wave_profile(level: ResourceLevelData) -> WaveProfile:
	return active_wave_profile if owns_battle(level) else null

func finish_victory() -> void:
	if active_level == null or battle_failed or progress == null:
		return
	if active_stage_number != 1 or active_phase_kind != StagePhaseDefinition.Kind.NORMAL:
		return # 其他阶段必须由后续运行时提供可靠的通关判定。
	if not progress.record_victory():
		error_message = "草坪胜利进度无法更新。"
		_show_save_retry()
		return
	AdventureStageCatalog.mark_cleared(
		Global.global_game_state.adventure_state, AdventureStageCatalog.LAWN_ID, active_phase_kind)
	if not Global.save_service.save_now():
		error_message = "无法保存草坪通关状态。"
		_show_save_retry()
		return
	notice = "草坪普通阶段已通关，没落营地已开放！"
	battle_finished.emit(1, "victory")
	return_to_map()
func _show_save_retry() -> void:
	var retry := AcceptDialog.new()
	retry.dialog_text = error_message
	retry.ok_button_text = "重试保存"
	retry.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(retry)
	retry.confirmed.connect(func():
		retry.queue_free()
		finish_victory())
	retry.canceled.connect(func():
		retry.queue_free()
		_show_save_retry.call_deferred())
	retry.popup_centered(Vector2i(520, 150))
func finish_defeat() -> void:
	if active_level == null:
		return
	notice = "草坪挑战失败，再试一次吧。"
	battle_finished.emit(1, "defeat")
	return_to_map()
func abandon_battle() -> void:
	if active_level != null:
		notice = "已离开草坪，本次未结算通关。"
		battle_finished.emit(1, "abandoned")
	return_to_map()
func return_to_map() -> void:
	adventure_active = true
	active_level = null
	active_stage_number = 0
	active_phase_kind = 0
	active_wave_profile = null
	battle_loadout.clear()
	Global.game_para = null
	TreePauseManager.end_tree_pause_clear_all_pause_factors()
	Global.time_scale = 1.0
	Engine.time_scale = 1.0
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file(MAP_SCENE)
