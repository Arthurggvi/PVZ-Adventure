## 冒险会话边界：地区状态存放 AdventureState，资产使用同一库存服务、同一玩家存档。
extends Node
const MAP_SCENE := "res://scenes/adventure/zombie_island.tscn"
const Progress = preload("res://scripts/adventure/island_progress.gd")
const RewardService = preload("res://scripts/adventure/adventure_reward_service.gd")
signal battle_finished(stage_id: int, result: String)
## 关卡全程唯一状态机；每个阶段都有独立的胜利事务。
enum ChallengeState {
	NONE, NORMAL_ACTIVE, NORMAL_SETTLING, NORMAL_COMPLETE,
	NIGHTMARE_ACTIVE, NIGHTMARE_SETTLING, COMPLETE, FAILED,
	NIGHTMARE_COMPLETE, TERMINAL_ACTIVE, TERMINAL_SETTLING
}
var challenge_state: ChallengeState = ChallengeState.NONE
var progress: RefCounted
var active_level: ResourceLevelData
var active_stage: StageDefinition
## 当前阶段的唯一可变身份；类型与波次只能从该资源派生。
var active_phase: StagePhaseDefinition
var active_stage_number: int = 0
var active_phase_kind: int:
	get:
		return active_phase.kind if active_phase != null else StagePhaseDefinition.Kind.UNSET
var active_wave_profile: WaveProfile:
	get:
		return active_phase.wave_profile if active_phase != null else null
## 本局已冻结的玩家卡数据；不写玩家存档、不反向修改背包。
var battle_loadout: Array[Dictionary] = []
## 确认出战时冻结的角色效果，普通接噩梦沿用；对外只返回副本。
var _player_effects: PlayerEffects
## 快照所属档案，阻止换档后消费上个玩家的效果。
var _player_state: AdventureState
## 本局 Boss 结果，仅供战后掉落判定；明确区分击败与主动撤退。
var boss_exit_results: Dictionary[StringName, int] = {}
## 存档失败后沿用同一次掉落结果，重试不得重新抽奖。
var pending_reward: Dictionary = {}
## 结算结果显示在返回地图后的提示中。
var notice := ""
var battle_failed := false
var adventure_active := false
var entry_error := ""
var error_message := ""
func _ready() -> void:
	Global.user_manager.signal_users_update.connect(_on_profile_changed)
func _on_profile_changed() -> void:
	progress = null
	if owns_battle(Global.game_para):
		Global.game_para = null
	_clear_active_battle()
	adventure_active = false

## 释放场景身份和本局临时状态，供退出战斗与切换档案共用。
func _clear_active_battle() -> void:
	active_level = null
	active_stage = null
	active_phase = null
	active_stage_number = 0
	challenge_state = ChallengeState.NONE
	_reset_battle_attempt()

## 只清理本局快照和结算中间态。历史卡组、库存和关卡进度仍归玩家档案所有。
func _reset_battle_attempt() -> void:
	battle_loadout.clear()
	_player_effects = null
	_player_state = null
	boss_exit_results.clear()
	pending_reward.clear()
	battle_failed = false
func open_adventure() -> bool:
	# 当前确实仍在地图时才可复用；从菜单或战斗返回后须重新完成场景切换。
	var scene: Node = get_tree().current_scene
	if adventure_active and is_instance_valid(scene) and scene.scene_file_path == MAP_SCENE:
		return true
	adventure_active = false
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
		var before: Dictionary = Global.global_game_state.adventure_state.regions.duplicate(true)
		progress.start()
		if not Global.save_service.save_now():
			Global.global_game_state.adventure_state.regions = before
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
## 新手赠卡统一事务：两卡、UID游标、卡组和领取标记一起成功或一起回滚。
func grant_starter_cards() -> bool:
	if progress == null or not progress.started:
		error_message = "冒险尚未开始。"
		return false
	var state: AdventureState = Global.global_game_state.adventure_state
	if state.claimed_rewards.get("intro_starter_cards", false):
		return true
	var inventory: AdventureInventoryService = Global.adventure_inventory
	var old_next_id: int = state.next_card_id
	var old_deck: Array[String] = state.selected_card_uids.duplicate()
	var old_discoveries: Dictionary = state.almanac_discoveries.duplicate() # 初始赠卡失败时连同首次收录一起恢复。
	var had_claim: bool = state.claimed_rewards.has("intro_starter_cards")
	var previous_claim: bool = state.claimed_rewards.get("intro_starter_cards", false)
	var sunflower: String = inventory.add_card(CharacterRegistry.PlantType.P002SunFlower)
	var peashooter: String = inventory.add_card(CharacterRegistry.PlantType.P001PeaShooterSingle)
	if not sunflower.is_empty() and not peashooter.is_empty():
		if state.selected_card_uids.is_empty():
			state.selected_card_uids = [sunflower, peashooter]
		state.claimed_rewards["intro_starter_cards"] = true
		if Global.save_service.save_now():
			error_message = ""
			return true
	if not sunflower.is_empty():
		inventory.remove_card(sunflower)
	if not peashooter.is_empty():
		inventory.remove_card(peashooter)
	state.next_card_id = old_next_id
	state.selected_card_uids = old_deck
	state.almanac_discoveries.assign(old_discoveries)
	if had_claim:
		state.claimed_rewards["intro_starter_cards"] = previous_claim
	else:
		state.claimed_rewards.erase("intro_starter_cards")
	error_message = "初始卡牌领取失败，状态已回滚，可重试。"
	return false

func complete_intro() -> bool:
	if not grant_starter_cards():
		return false
	var state: AdventureState = Global.global_game_state.adventure_state
	var before: Dictionary = state.regions.duplicate(true)
	if not progress.complete_intro():
		return false
	if not Global.save_service.save_now():
		state.regions = before
		error_message = "无法保存引导进度。"
		return false
	error_message = ""
	return true
## 冒险战斗强制僵尸预览与可交互 UID 选卡；玩家确认时才冻结战斗快照。
func enter_lawn() -> void:
	enter_stage(1, StagePhaseDefinition.Kind.NORMAL)
## 统一配置入口；场景、卡槽、波次种类均由已验证的 StageDefinition 生成。
func enter_stage(stage_number: int, phase_kind: int = StagePhaseDefinition.Kind.NORMAL) -> bool:
	if progress == null or not progress.intro_completed:
		return false
	if phase_kind != StagePhaseDefinition.Kind.NORMAL:
		error_message = "只能从普通阶段进入；噩梦在本次普通阶段完成后续战。"
		return false
	error_message = AdventureStageCatalog.entry_error(
		stage_number, phase_kind, Global.global_game_state.adventure_state, Global.adventure_inventory)
	if not error_message.is_empty():
		return false
	var stage: StageDefinition = AdventureStageCatalog.load_stage(stage_number) # 读取已验证的关卡定义。
	var phase: StagePhaseDefinition = AdventureStageCatalog.find_phase(stage, phase_kind) # 首次进入从普通阶段开始。
	return _start_battle_attempt(stage_number, stage, phase)

## 重开 [param level] 所属的当前阶段；噩梦继续使用已经取得的本阶段进入资格。
func restart_battle(level: ResourceLevelData) -> bool:
	if not owns_battle(level):
		error_message = "当前关卡不属于冒险会话。"
		return false
	return _start_battle_attempt(active_stage_number, active_stage, active_phase)

## 以 [param stage_number]、[param stage] 和 [param phase] 创建一局全新的战斗。
## 切场失败时保留原会话；成功后在新场景入树前发布本局参数。
func _start_battle_attempt(stage_number: int, stage: StageDefinition, phase: StagePhaseDefinition) -> bool:
	var level: ResourceLevelData = AdventureBattleEnvironmentAdapter.build(stage, phase) # 每局重新从阶段定义生成旧引擎的参数投影。
	if level == null:
		error_message = "无法从本局环境及阶段配置构建战斗。"
		return false
	var scene_path: String = Global.main_scene_registry.MainScenesMap.get(level.game_sences, "") # 关卡环境指定战斗场景。
	if scene_path.is_empty() or get_tree().change_scene_to_file(scene_path) != OK:
		error_message = "关卡场景加载失败。"
		return false
	_reset_battle_attempt()
	active_stage_number = stage_number
	active_stage = stage
	active_level = level
	_activate_phase(phase)
	Global.game_para = active_level
	error_message = ""
	_reset_battle_controls()
	return true
## 接收备战画面按 UID 选择的卡，仅确认时冻结快照和更新当前玩家的历史卡组。
func confirm_selected_cards(cards: Array[Card]) -> bool:
	if not owns_battle(Global.game_para) or active_stage == null or active_phase == null or not battle_loadout.is_empty():
		return false
	var inventory: AdventureInventoryService = Global.adventure_inventory # 权威库存决定真实卡片身份。
	var uids: Array[String] = [] # 保存用户实际选中的完整顺序，免槽卡不会被剔除。
	var profiles: Array[PlantSpawnProfile] = [] # 在写入卡组前校验并冻结每张卡的合法配方。
	var occupied_slots: int = 0 # 不信任界面缓存的预算或可修改展示数据。
	for card: Card in cards: # 同种不同 UID 分别校验，重复身份拒绝开战。
		if not is_instance_valid(card) or card.card_reference == null \
				or card.card_reference.card_type != ResourceCardReference.CardType.Plant or card.card_reference.is_imitater:
			return false
		var uid: String = str(card.battle_card_data.get("uid", "")) # 界面只提供待查身份。
		var current: Dictionary = inventory.get_card(uid) # 重新读取该玩家当前实际卡牌。
		if current.is_empty() or str(current.get("uid", "")) != uid or uids.has(uid) \
				or int(current.get("plant_type", -1)) != card.card_reference.content_id:
			return false
		var profile: PlantSpawnProfile = AdventureBattleAdapter.profile_for(current) # 无效分支不能享受免槽。
		if profile == null:
			return false
		profiles.append(profile)
		occupied_slots += profile.selection_slot_cost()
		uids.append(uid)
	if not CardSlotRules.can_start(active_stage.max_selected_cards, cards.size(), occupied_slots):
		return false
	var state: AdventureState = Global.global_game_state.adventure_state
	var previous_uids: Array[String] = state.selected_card_uids.duplicate()
	if not inventory.set_deck(uids):
		return false
	var snapshot: Array[Dictionary] = AdventureBattleAdapter.create_loadout(state)
	if snapshot.size() != cards.size():
		state.selected_card_uids = previous_uids
		return false
	# set_deck 只替换已校验的 UID 顺序；这里的快照与入事务前构造的配方来自同一库存。
	if not Global.save_service.save_now():
		state.selected_card_uids = previous_uids
		return false
	battle_loadout = snapshot
	_player_effects = PlayerEffects.resolve(state.equipment)
	_player_state = state
	for index: int in range(cards.size()):
		cards[index].plant_spawn_profile = profiles[index]
	return true
## 重新核验本局冻结卡组的占槽预算；损坏或重复身份返回 -1，不能消费续战钥匙。
func _frozen_loadout_slot_count() -> int:
	var occupied_slots: int = 0 # 真实卡片数可以大于关卡普通槽预算。
	var seen: Dictionary[String, bool] = {} # 免槽也不能复制同一 UID。
	for build: Dictionary in battle_loadout: # 所有配方仍来自开战时的只读快照。
		var profile: PlantSpawnProfile = AdventureBattleAdapter.profile_for(build) # 使用同一合法分支入口。
		var uid: String = str(build.get("uid", "")) # 完整身份不能在续战时丢失。
		if profile == null or seen.has(uid):
			return -1
		seen[uid] = true
		occupied_slots += profile.selection_slot_cost()
	return occupied_slots

## 仅供原版预选卡槽获取对应序号的冻结身份；普通模式不走此入口。
func get_prechosen_battle_data(slot_index: int, reference: ResourceCardReference) -> Dictionary:
	if active_level == null:
		return {}
	return AdventureBattleAdapter.binding_at(battle_loadout, slot_index, reference)
func owns_battle(level: ResourceLevelData) -> bool:
	return active_level != null and active_level == level

## 返回 [param level] 所属冒险战斗的角色效果副本；非本局或跨档返回中性效果。
func player_effects_for(level: ResourceLevelData) -> PlayerEffects:
	if not owns_battle(level) or _player_effects == null or _player_state != Global.global_game_state.adventure_state:
		return PlayerEffects.new()
	return _player_effects.copy()

func get_active_wave_profile(level: ResourceLevelData) -> WaveProfile:
	return active_wave_profile if owns_battle(level) else null

func get_active_phase(level: ResourceLevelData) -> StagePhaseDefinition:
	return active_phase if owns_battle(level) else null

## 波次阶段必须清完末波与遭遇；无波次的终末阶段只要求击败博士。
## 历史通关记录与当前能否完成战斗无关。
func can_accept_victory() -> bool:
	if challenge_state not in [ChallengeState.NORMAL_ACTIVE, ChallengeState.NIGHTMARE_ACTIVE, ChallengeState.TERMINAL_ACTIVE]:
		return false
	var runtime: AdventureBattleRuntime = _active_runtime()
	if runtime == null or runtime.has_pending_bosses():
		return false
	for encounter: BossEncounterDefinition in active_phase.boss_encounters: # 撤退只满足不要求击败的遭遇。
		if not boss_exit_results.has(encounter.encounter_id):
			return false
		if encounter.require_defeat and boss_exit_results[encounter.encounter_id] != StageEventDefinition.BossExitReason.DEFEATED:
			return false
	if active_phase_kind == StagePhaseDefinition.Kind.TERMINAL:
		# 终末的唯一必杀遭遇是开场博士；它死亡后无需再清理援军。
		return true
	var waves: ZombieWaveManager = runtime.waves
	var zombies: ZombieManager = runtime.zombies
	return waves.curr_wave == waves.max_wave - 1 and zombies.is_end_wave and zombies.curr_zombie_num == 0

## 判断普通完成后是否可询问续战；只依赖当前持有钥匙，无首通要求。
func can_offer_nightmare() -> bool:
	return challenge_state == ChallengeState.NORMAL_COMPLETE and \
		AdventureStageCatalog.continuation_error(active_stage, Global.adventure_inventory).is_empty()

## 噩梦结算落盘后，持有下半钥匙才可选择续战；没有终末阶段的关卡直接完成。
func can_offer_terminal() -> bool:
	return challenge_state == ChallengeState.NIGHTMARE_COMPLETE and active_stage != null \
		and not active_stage.terminal_key_id.is_empty() \
		and Global.adventure_inventory.get_item_count(str(active_stage.terminal_key_id)) >= 1

## 用户拒绝续战，或没有对应钥匙：已经保存的阶段结算成为整局结算。
func complete_checkpoint_challenge() -> bool:
	if challenge_state not in [ChallengeState.NORMAL_COMPLETE, ChallengeState.NIGHTMARE_COMPLETE]:
		return false
	challenge_state = ChallengeState.COMPLETE
	battle_finished.emit(active_stage_number, "victory")
	return true

## 继续噩梦时重新检查即时库存；钥匙消费和玩家存档必须原子提交。
## 新阶段沿用本局战场与卡组，阶段奖励、Boss 和事件状态重新开始。
func begin_nightmare() -> bool:
	if not can_offer_nightmare():
		error_message = "当前没有可用的噩梦钥匙。"
		return false
	var nightmare: StagePhaseDefinition = AdventureStageCatalog.find_phase(
		active_stage, StagePhaseDefinition.Kind.NIGHTMARE)
	return _begin_followup(nightmare, active_stage.nightmare_key_id, active_stage.nightmare_key_count,
		active_stage.nightmare_key_use == StageDefinition.KeyUse.CONSUME)

## 消耗下半钥匙进入终末阶段，复用相同的存档事务。
func begin_terminal() -> bool:
	if not can_offer_terminal():
		error_message = "当前没有可用的终末钥匙。"
		return false
	var terminal: StagePhaseDefinition = AdventureStageCatalog.find_phase(
		active_stage, StagePhaseDefinition.Kind.TERMINAL) # 已预检的第三阶段快照。
	return _begin_followup(terminal, active_stage.terminal_key_id, 1, true)

## 校验冻结卡组；按 [param key_id]、[param key_count] 和 [param consume] 完成钥匙事务，再进入 [param phase]。
func _begin_followup(phase: StagePhaseDefinition, key_id: StringName, key_count: int, consume: bool) -> bool:
	var occupied_slots: int = _frozen_loadout_slot_count() # 续战沿用本局冻结配方，不重读已变化的库存。
	if phase == null or occupied_slots < 0 \
			or not CardSlotRules.can_start(active_stage.max_selected_cards, battle_loadout.size(), occupied_slots):
		error_message = "下一阶段与当前卡组不兼容。"
		return false
	if consume:
		var key: String = str(key_id) # 库存的钥匙 ID 使用 String。
		if not Global.adventure_inventory.consume_item(key, key_count):
			error_message = "续战钥匙不足。"
			return false
		if not Global.save_service.save_now():
			Global.adventure_inventory.add_item(key, key_count)
			error_message = "无法保存钥匙消耗，阶段未切换。"
			return false
	_activate_phase(phase)
	error_message = ""
	return true

## 切换到 [param phase]，清除前一阶段的 Boss 与奖励中间态。
func _activate_phase(phase: StagePhaseDefinition) -> void:
	active_phase = phase
	boss_exit_results.clear()
	pending_reward.clear()
	match phase.kind:
		StagePhaseDefinition.Kind.NORMAL:
			challenge_state = ChallengeState.NORMAL_ACTIVE
		StagePhaseDefinition.Kind.NIGHTMARE:
			challenge_state = ChallengeState.NIGHTMARE_ACTIVE
		StagePhaseDefinition.Kind.TERMINAL:
			challenge_state = ChallengeState.TERMINAL_ACTIVE

## 权威胜利事务：战斗胜利被接受时执行，独立于奖杯 UI 和玩家是否点击。
## [param skip_combat_checks] 仅供已接受的一键通关及其重试跳过清场；奖励依然读取真实 Boss 击杀记录。
func settle_victory(skip_combat_checks: bool = false) -> bool:
	if challenge_state in [ChallengeState.NORMAL_COMPLETE, ChallengeState.NIGHTMARE_COMPLETE, ChallengeState.COMPLETE]:
		return true
	if active_level == null or battle_failed or progress == null or active_stage == null or active_phase == null:
		return false
	if challenge_state in [ChallengeState.NORMAL_ACTIVE, ChallengeState.NIGHTMARE_ACTIVE, ChallengeState.TERMINAL_ACTIVE]:
		if not skip_combat_checks and not can_accept_victory():
			error_message = "当前阶段尚未真正清场，禁止提前结算。"
			return false
		match active_phase_kind:
			StagePhaseDefinition.Kind.NORMAL:
				challenge_state = ChallengeState.NORMAL_SETTLING
			StagePhaseDefinition.Kind.NIGHTMARE:
				challenge_state = ChallengeState.NIGHTMARE_SETTLING
			StagePhaseDefinition.Kind.TERMINAL:
				challenge_state = ChallengeState.TERMINAL_SETTLING
	elif challenge_state not in [ChallengeState.NORMAL_SETTLING, ChallengeState.NIGHTMARE_SETTLING, ChallengeState.TERMINAL_SETTLING]:
		return false
	var stage: StageDefinition = active_stage
	var phase: StagePhaseDefinition = active_phase
	var runtime: AdventureBattleRuntime = _active_runtime()
	var defeated_boss := false
	var loot_table: DropTable = phase.drop_table
	for encounter: BossEncounterDefinition in phase.boss_encounters: # 修改器也只根据真实结果发放击杀奖励。
		if boss_exit_results.get(encounter.encounter_id) == StageEventDefinition.BossExitReason.DEFEATED:
			defeated_boss = true
	# 噩梦遭遇全数撤退才回退到普通掉落表。
	if active_phase_kind == StagePhaseDefinition.Kind.NIGHTMARE and not phase.boss_encounters.is_empty() and not defeated_boss:
		var normal: StagePhaseDefinition = AdventureStageCatalog.find_phase(stage, StagePhaseDefinition.Kind.NORMAL) # 普通掉落快照。
		if normal == null:
			return false
		loot_table = normal.drop_table
	if runtime != null:
		runtime.finish_battle(true)
	var state: AdventureState = Global.global_game_state.adventure_state
	if pending_reward.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		pending_reward = RewardService.prepare(
			phase, loot_table, state.claimed_rewards, defeated_boss, rng, player_effects_for(active_level))
		if pending_reward.get("ok", false) and runtime != null:
			var items: Dictionary = pending_reward["items"]
			for item_id: String in runtime.requested_items:
				items[item_id] = int(items.get(item_id, 0)) + int(runtime.requested_items[item_id])
	if not pending_reward.get("ok", false):
		error_message = "关卡奖励配置无效，未结算。"
		return false
	var before_items: Dictionary = state.items.duplicate(true)
	var before_claims: Dictionary = state.claimed_rewards.duplicate(true)
	var before_regions: Dictionary = state.regions.duplicate(true)
	var before_coin: int = Global.global_game_state.coin_value
	var reward_items: Dictionary = pending_reward["items"]
	var phase_claim_id: String = RewardService.first_clear_claim_id(phase) # 当前阶段在存档中的稳定领取 ID。
	var claim_id: String = str(pending_reward["claim_id"]) # 非空表示这次结算首次取得奖励资格。
	var first_clear_coins: Dictionary = pending_reward["first_clear_coins"] # 新取得的钱堆，尚未生成实体。
	if claim_id.is_empty():
		first_clear_coins = RewardService.pending_first_clear_coins(state, phase_claim_id)
	# 一键通关直接返回地图，只有这条路径在结算事务内兑现当前阶段的钱堆。
	var reward_coin: int = RewardService.first_clear_coin_total(first_clear_coins) if skip_combat_checks else 0
	if not RewardService.apply(reward_items, reward_coin,
			state, Global.adventure_inventory, Global.global_game_state):
		_restore_reward_snapshot(before_items, before_claims, before_regions, before_coin)
		error_message = "奖励入账失败，请检查库存容量。"
		return false
	# 在写入通关事实前记录事件，避免同一次事件计入刚解锁的后继任务。
	var before_quests: Dictionary = state.quests.to_dict()
	AdventureQuestService.record_event(state, "stage_cleared", "%s/%s" % [stage.stage_id,
		AdventureStageCatalog.phase_slug(active_phase_kind)], AdventureQuestService.today())
	if not claim_id.is_empty():
		state.claimed_rewards[claim_id] = true
		if not skip_combat_checks:
			RewardService.set_pending_first_clear_coins(state, claim_id, first_clear_coins)
	if skip_combat_checks and not first_clear_coins.is_empty():
		RewardService.set_pending_first_clear_coins(state, phase_claim_id, {})
	if active_stage_number == 1 and active_phase_kind == StagePhaseDefinition.Kind.NORMAL and not progress.record_victory():
		_restore_reward_snapshot(before_items, before_claims, before_regions, before_coin)
		error_message = "草坪胜利进度无法更新。"
		state.quests = AdventureQuestState.from_dict(before_quests)
		return false
	AdventureStageCatalog.mark_cleared(state, stage.stage_id, active_phase_kind)
	if runtime != null and not runtime.pending_region_flags.is_empty():
		var region: Dictionary = state.regions.get(AdventureStageCatalog.REGION_ID, {}).duplicate(true)
		var flags: Dictionary = region.get("event_flags", {}).duplicate(true)
		for flag_id: StringName in runtime.pending_region_flags:
			flags[str(flag_id)] = runtime.pending_region_flags[flag_id]
		region["event_flags"] = flags
		state.regions[AdventureStageCatalog.REGION_ID] = region
	if not Global.save_service.save_now():
		_restore_reward_snapshot(before_items, before_claims, before_regions, before_coin)
		error_message = "奖励或通关记录保存失败，可重试相同掉落。"
		state.quests = AdventureQuestState.from_dict(before_quests)
		return false
	Global.quests_changed.emit()
	error_message = ""
	var phase_name: String # 结算提示中的阶段名称。
	match active_phase_kind:
		StagePhaseDefinition.Kind.NORMAL:
			challenge_state = ChallengeState.NORMAL_COMPLETE
			phase_name = "普通"
		StagePhaseDefinition.Kind.NIGHTMARE:
			challenge_state = ChallengeState.NIGHTMARE_COMPLETE if not stage.terminal_key_id.is_empty() else ChallengeState.COMPLETE
			phase_name = "噩梦"
		StagePhaseDefinition.Kind.TERMINAL:
			challenge_state = ChallengeState.COMPLETE
			phase_name = "终末"
	notice = "%s%s阶段通关！结算获得 %d 种物品。" % [
		AdventureStageRegistry.display_name(active_stage_number), phase_name, reward_items.size()]
	if challenge_state == ChallengeState.COMPLETE:
		battle_finished.emit(active_stage_number, "victory")
	return true

func _active_runtime() -> AdventureBattleRuntime:
	var game: MainGameManager = Global.main_game
	if game == null or not owns_battle(game.game_para):
		return null
	return game.adventure_runtime

## 保存奖杯收取后的钱包和背包，再返回地图；写盘失败时保留本局并重试保存。
func finish_victory() -> void:
	if challenge_state != ChallengeState.COMPLETE:
		return
	if not Global.save_service.save_now():
		error_message = "拾取奖励保存失败，可重试保存。"
		prompt_victory_retry(finish_victory)
		return
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

## 仅在事务失败时弹出重试入口；主游戏自身恢复奖杯演出。
func prompt_victory_retry(retry_action: Callable) -> void:
	var retry := AcceptDialog.new()
	retry.dialog_text = error_message
	retry.ok_button_text = "重试结算"
	retry.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(retry)
	retry.confirmed.connect(func():
		retry.queue_free()
		if retry_action.is_valid():
			retry_action.call_deferred())
	retry.canceled.connect(func():
		retry.queue_free()
		prompt_victory_retry.call_deferred(retry_action))
	retry.popup_centered(Vector2i(520, 150))

func finish_defeat() -> void:
	if active_level == null:
		return
	challenge_state = ChallengeState.FAILED
	var runtime: AdventureBattleRuntime = _active_runtime()
	if runtime != null:
		runtime.finish_battle()
	notice = "%s挑战失败。" % AdventureStageRegistry.display_name(active_stage_number)
	battle_finished.emit(active_stage_number, "defeat")
	return_to_map()
func abandon_battle() -> void:
	if active_level != null:
		var runtime: AdventureBattleRuntime = _active_runtime()
		if runtime != null:
			runtime.finish_battle()
		notice = "已离开%s，本次未结算通关。" % AdventureStageRegistry.display_name(active_stage_number)
		battle_finished.emit(active_stage_number, "abandoned")
	return_to_map()
func return_to_map() -> void:
	adventure_active = true
	_clear_active_battle()
	Global.game_para = null
	_reset_battle_controls()
	get_tree().change_scene_to_file(MAP_SCENE)

## 离开旧战场时解除暂停、恢复正常速度与鼠标显示。
func _reset_battle_controls() -> void:
	TreePauseManager.end_tree_pause_clear_all_pause_factors()
	Global.time_scale = 1.0
	Engine.time_scale = 1.0
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
