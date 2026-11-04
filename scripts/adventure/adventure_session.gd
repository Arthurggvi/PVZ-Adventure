## 冒险会话边界：地区状态存放 AdventureState，资产使用同一库存服务、同一玩家存档。
extends Node
const MAP_SCENE := "res://scenes/adventure/zombie_island.tscn"
const Progress = preload("res://scripts/adventure/island_progress.gd")
const RewardService = preload("res://scripts/adventure/adventure_reward_service.gd")
signal battle_finished(stage_id: int, result: String)
var progress: RefCounted
var active_level: ResourceLevelData
var active_stage: StageDefinition
var active_phase: StagePhaseDefinition
var active_stage_number: int = 0
var active_phase_kind: int = 0
## 当前战斗独有的波次资源快照，场景内不重复读磁盘配置。
var active_wave_profile: WaveProfile
## 本局已冻结的玩家卡数据；不写玩家存档、不反向修改背包。
var battle_loadout: Array[Dictionary] = []
## 本局 Boss 结果，仅供战后掉落判定；明确区分击败与主动撤退。
var boss_exit_results: Dictionary[StringName, int] = {}
## 存档失败后沿用同一次掉落结果，重试不得重新抽奖。
var pending_reward: Dictionary = {}
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
	active_stage = null
	active_phase = null
	active_stage_number = 0
	active_phase_kind = 0
	active_wave_profile = null
	battle_loadout.clear()
	boss_exit_results.clear()
	pending_reward.clear()
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
	if progress == null:
		return false
	return AdventureStageCatalog.is_unlocked(stage_id, Global.global_game_state.adventure_state)
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
	var stage: StageDefinition = AdventureStageCatalog.load_stage(stage_number)
	var phase: StagePhaseDefinition = AdventureStageCatalog.find_phase(stage, phase_kind)
	if phase == null or phase.wave_profile == null:
		error_message = "冒险波次数据未就绪。"
		return false
	var level: ResourceLevelData = AdventureBattleEnvironmentAdapter.build(stage.environment, phase)
	if level == null:
		error_message = "无法从本局环境及阶段配置构建战斗。"
		return false
	battle_loadout.clear()
	boss_exit_results.clear()
	pending_reward.clear()
	active_stage_number = stage_number
	active_phase_kind = phase_kind
	active_stage = stage
	active_phase = phase
	active_wave_profile = phase.wave_profile
	active_level = level
	battle_failed = false
	Global.game_para = active_level
	var err := get_tree().change_scene_to_file(Global.main_scene_registry.MainScenesMap[level.game_sences])
	if err != OK:
		active_level = null
		active_stage_number = 0
		active_phase_kind = 0
		active_stage = null
		active_phase = null
		active_wave_profile = null
		Global.game_para = null
		error_message = "关卡场景加载失败。"
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

func get_active_phase(level: ResourceLevelData) -> StagePhaseDefinition:
	return active_phase if owns_battle(level) else null

func finish_victory() -> void:
	if active_level == null or battle_failed or progress == null:
		return
	var stage: StageDefinition = active_stage
	var phase: StagePhaseDefinition = active_phase
	if phase == null:
		return
	var defeated_boss := false
	var loot_table: DropTable = phase.drop_table
	if active_phase_kind == StagePhaseDefinition.Kind.NIGHTMARE:
		for encounter: BossEncounterDefinition in phase.boss_encounters:
			if not boss_exit_results.has(encounter.encounter_id):
				error_message = "Boss 遭遇未结束，不能结算胜利。"
				return
			if boss_exit_results[encounter.encounter_id] == StageEventDefinition.BossExitReason.DEFEATED:
				defeated_boss = true
		if not defeated_boss:
			var normal: StagePhaseDefinition = AdventureStageCatalog.find_phase(stage, StagePhaseDefinition.Kind.NORMAL)
			if normal == null:
				return
			loot_table = normal.drop_table # Boss 逃跑仅获得普通材料，不获得 Boss 专属掉落。
	var state: AdventureState = Global.global_game_state.adventure_state
	if pending_reward.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		pending_reward = RewardService.prepare(
			phase, loot_table, state.claimed_rewards, defeated_boss, rng)
	if not pending_reward.get("ok", false):
		error_message = "关卡奖励配置无效，未结算。"
		return
	var before_items: Dictionary = state.items.duplicate(true)
	var before_claims: Dictionary = state.claimed_rewards.duplicate(true)
	var before_regions: Dictionary = state.regions.duplicate(true)
	var before_coin: int = Global.global_game_state.coin_value
	var reward_items: Dictionary = pending_reward["items"]
	var reward_coin: int = int(pending_reward["coin"])
	if not RewardService.apply(reward_items, reward_coin,
			state, Global.adventure_inventory, Global.global_game_state):
		_restore_reward_snapshot(before_items, before_claims, before_regions, before_coin)
		error_message = "奖励入账失败，请检查库存容量。"
		return
	var claim_id: String = str(pending_reward["claim_id"])
	if not claim_id.is_empty():
		state.claimed_rewards[claim_id] = true
	if active_stage_number == 1 and active_phase_kind == StagePhaseDefinition.Kind.NORMAL and not progress.record_victory():
		_restore_reward_snapshot(before_items, before_claims, before_regions, before_coin)
		error_message = "草坪胜利进度无法更新。"
		return
	AdventureStageCatalog.mark_cleared(state, stage.stage_id, active_phase_kind)
	if not Global.save_service.save_now():
		_restore_reward_snapshot(before_items, before_claims, before_regions, before_coin)
		error_message = "奖励或通关记录保存失败，可重试相同掉落。"
		_show_save_retry()
		return
	var phase_name: String = "普通" if active_phase_kind == StagePhaseDefinition.Kind.NORMAL else "噩梦"
	notice = "%s%s阶段通关！奖励：%s种物品，金币+%d。" % [
		AdventureStageRegistry.display_name(active_stage_number), phase_name,
		reward_items.size(), reward_coin]
	battle_finished.emit(active_stage_number, "victory")
	return_to_map()

func _restore_reward_snapshot(items: Dictionary, claims: Dictionary,
		regions: Dictionary, coin: int) -> void:
	var state: AdventureState = Global.global_game_state.adventure_state
	state.items.clear()
	for id: String in items:
		state.items[id] = items[id]
	state.claimed_rewards.clear()
	for claim_id: String in claims:
		state.claimed_rewards[claim_id] = claims[claim_id]
	state.regions = regions.duplicate(true)
	Global.global_game_state.coin_value = coin

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
	notice = "%s挑战失败。" % AdventureStageRegistry.display_name(active_stage_number)
	battle_finished.emit(active_stage_number, "defeat")
	return_to_map()
func abandon_battle() -> void:
	if active_level != null:
		notice = "已离开%s，本次未结算通关。" % AdventureStageRegistry.display_name(active_stage_number)
		battle_finished.emit(active_stage_number, "abandoned")
	return_to_map()
func return_to_map() -> void:
	adventure_active = true
	active_level = null
	active_stage = null
	active_phase = null
	active_stage_number = 0
	active_phase_kind = 0
	active_wave_profile = null
	battle_loadout.clear()
	boss_exit_results.clear()
	pending_reward.clear()
	Global.game_para = null
	TreePauseManager.end_tree_pause_clear_all_pause_factors()
	Global.time_scale = 1.0
	Engine.time_scale = 1.0
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file(MAP_SCENE)
