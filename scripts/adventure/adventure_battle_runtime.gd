## 冒险关卡事件及 Boss 触发；原版模式不实例化此节点。
## 监听自然波次信号，不按帧遍历僵尸或植物实例。
extends Node
class_name AdventureBattleRuntime

var waves: ZombieWaveManager
var zombies: ZombieManager
var phase: StagePhaseDefinition
var _boss_director: AdventureBossDirector
var boss_runtime: AdventureBossEncounter:
	get:
		return _boss_director.current if is_instance_valid(_boss_director) else null
var elapsed_seconds := 0.0
var _fired: Dictionary[StringName, bool] = {}
var _threshold_states: Dictionary[StringName, bool] = {}
var _cleared_waves: Dictionary[int, bool] = {}
var _ordered_events: Array[StageEventDefinition] = []
var _gravestones: AdventureGravestoneDirector
var _cooldown: AdventureCardCooldownRuntime
var _sunflower_skills: AdventureSunflowerPromotionRuntime
## 豌豆射手事件技能与场上协同分别由独立运行时结算。
var _pea_skills: AdventurePeaPromotionRuntime
var _pea_synergy: AdventurePeaSynergyRuntime
var requested_items: Dictionary[String, int] = {}
var pending_region_flags: Dictionary[StringName, bool] = {}
var _reward_rng := RandomNumberGenerator.new()
var _battle_ended := false
var _battle_won := false
var _ending_requested := false
var _last_zombie_count := -1

## 只在实际胜/负判定时发一次 BATTLE_END；战斗事件不允许自行落盘。
func finish_battle(victory: bool = false) -> void:
	if _battle_ended:
		return
	_battle_ended = true
	_battle_won = victory
	_fire(StageEventDefinition.Trigger.BATTLE_END)
	if is_instance_valid(_cooldown):
		_cooldown.clear()
	if is_instance_valid(_gravestones):
		_gravestones.clear()

func setup(wave_manager: ZombieWaveManager, zombie_manager: ZombieManager,
		stage_phase: StagePhaseDefinition) -> void:
	waves = wave_manager
	zombies = zombie_manager
	phase = stage_phase # 共享 AdventureSession 已冻结的本局阶段快照，不重复读取资源文件。
	_reward_rng.randomize()
	_ordered_events = phase.events.duplicate()
	_ordered_events.sort_custom(func(a: StageEventDefinition, b: StageEventDefinition) -> bool:
		return a.order < b.order)
	var requires_tick := false
	for event: StageEventDefinition in _ordered_events:
		if event.trigger in [StageEventDefinition.Trigger.ELAPSED_TIME,
				StageEventDefinition.Trigger.ZOMBIE_COUNT]:
			requires_tick = true
			break
	set_process(requires_tick)

func _ready() -> void:
	waves.adventure_battle_started.connect(start_phase)
	waves.adventure_wave_before.connect(_on_wave_before)
	waves.adventure_wave_started.connect(_on_wave_started)
	_gravestones = AdventureGravestoneDirector.new()
	_gravestones.configure(phase.gravestone_rules,
		zombies.main_game.plant_cell_manager.tomb_stone_manager, waves)
	add_child(_gravestones)
	_cooldown = AdventureCardCooldownRuntime.new()
	_cooldown.setup(zombies)
	add_child(_cooldown)
	_sunflower_skills = AdventureSunflowerPromotionRuntime.new()
	_sunflower_skills.setup(zombies.main_game)
	add_child(_sunflower_skills)
	_pea_skills = AdventurePeaPromotionRuntime.new()
	_pea_skills.setup(zombies.main_game)
	add_child(_pea_skills)
	_pea_synergy = AdventurePeaSynergyRuntime.new()
	_pea_synergy.setup(zombies.main_game)
	add_child(_pea_synergy)
	_boss_director = AdventureBossDirector.new()
	_boss_director.setup(waves, zombies)
	add_child(_boss_director)
	_boss_director.exited.connect(_on_boss_exit)
	_boss_director.hp_changed.connect(_on_boss_hp_changed)
	_boss_director.idle.connect(_on_boss_idle)
	_boss_director.failed.connect(_on_boss_failed)
	zombies.signal_natural_wave_count_change.connect(_on_natural_count)
	# 已初始化的格子才连接种植信号，关卡卸载自动断开。
	for row: Array in zombies.main_game.plant_cell_manager.all_plant_cells:
		for cell: PlantCell in row:
			cell.signal_plant_create.connect(_on_plant_placed)

## 开始本阶段的开场事件和遭遇；终末阶段直接调用，无需生成第一波。
func start_phase() -> void:
	_fire(StageEventDefinition.Trigger.BATTLE_START)
	_begin_matching_boss(BossEncounterDefinition.Timing.PHASE_START, 0)

func _on_wave_before(wave_number: int) -> void:
	_fire(StageEventDefinition.Trigger.WAVE_BEFORE, wave_number)
	_begin_matching_boss(BossEncounterDefinition.Timing.WAVE_BEFORE, wave_number)

func _on_wave_started(wave_number: int) -> void:
	_fire(StageEventDefinition.Trigger.WAVE_STARTED, wave_number)
	if is_instance_valid(_gravestones):
		_gravestones.on_wave_started(wave_number, phase.wave_profile.flag_wave_numbers().has(wave_number))
	_begin_matching_boss(BossEncounterDefinition.Timing.WAVE_STARTED, wave_number)
	if zombies.get_natural_wave_count(wave_number - 1) == 0:
		_on_natural_count(wave_number, 0)
		# 无任何有效出怪行也必须触发末波胜负检查，避免等待不存在的死亡信号。
		if waves.curr_wave == waves.max_wave - 1 and zombies.curr_zombie_num == 0:
			zombies._try_finish_wave.call_deferred(zombies.main_game.camera_2d.get_screen_center_position())

## 每只僵尸按出生波分别登记，前波残敌晚死也要触发属于前波的清波事件。
func _on_natural_count(wave_number: int, count: int) -> void:
	if not zombies.is_game_running() or count != 0 or wave_number < 1 or _cleared_waves.has(wave_number):
		return
	_cleared_waves[wave_number] = true
	_fire(StageEventDefinition.Trigger.WAVE_CLEARED, wave_number)
	_begin_matching_boss(BossEncounterDefinition.Timing.WAVE_CLEARED, wave_number)

func _on_plant_placed(_cell: PlantCell, plant_type: CharacterRegistry.PlantType) -> void:
	if not zombies.is_game_running():
		return
	_fire(StageEventDefinition.Trigger.PLANT_PLACED, 0, {"plant_type": plant_type})

func _process(delta: float) -> void:
	if not zombies.is_game_running():
		return
	elapsed_seconds += delta
	_fire(StageEventDefinition.Trigger.ELAPSED_TIME)
	var count: int = zombies.curr_zombie_num
	if count != _last_zombie_count:
		_last_zombie_count = count
		_fire(StageEventDefinition.Trigger.ZOMBIE_COUNT, 0, {"count": count})

func _fire(trigger: int, wave_number: int = 0, payload: Dictionary = {}) -> void:
	if _battle_ended and trigger != StageEventDefinition.Trigger.BATTLE_END:
		return
	for event: StageEventDefinition in _ordered_events:
		if event.trigger != trigger or (_fired.has(event.event_id) and
			(event.repeat_rule == StageEventDefinition.RepeatRule.ONCE_PER_PHASE or
			trigger == StageEventDefinition.Trigger.ELAPSED_TIME)):
			continue
		if trigger in [StageEventDefinition.Trigger.WAVE_BEFORE, StageEventDefinition.Trigger.WAVE_STARTED,
			StageEventDefinition.Trigger.WAVE_CLEARED] and event.wave != wave_number:
			continue
		if trigger == StageEventDefinition.Trigger.ELAPSED_TIME and elapsed_seconds < event.elapsed_seconds:
			continue
		if trigger == StageEventDefinition.Trigger.PLANT_PLACED and event.plant_filter == StageEventDefinition.PlantFilter.SPECIFIC \
			and event.plant_type != payload.get("plant_type", CharacterRegistry.PlantType.Null):
			continue
		if trigger == StageEventDefinition.Trigger.ZOMBIE_COUNT:
			var matched: bool = _compares(int(payload.get("count", 0)), event.zombie_count, event.comparison)
			var previously: bool = _threshold_states.get(event.event_id, false)
			_threshold_states[event.event_id] = matched
			if not matched or previously:
				continue
		_fired[event.event_id] = true
		_apply_action(event)

func _compares(actual: int, limit: int, comparison: int) -> bool:
	return actual <= limit if comparison == StageEventDefinition.Comparison.LESS_OR_EQUAL else actual >= limit

func _apply_action(event: StageEventDefinition) -> void:
	match event.action:
		StageEventDefinition.Action.SPAWN_ZOMBIES:
			for i: int in range(event.action_count):
				waves.zombie_wave_create_manager.spawn_stage_support(event.action_zombie_type, event.action_tier_id)
		StageEventDefinition.Action.SPAWN_TOMBSTONES:
			zombies.main_game.plant_cell_manager.tomb_stone_manager.create_pvz2_tombstone(event.action_count)
		StageEventDefinition.Action.BEGIN_BOSS_ENCOUNTER:
			for candidate: BossEncounterDefinition in phase.boss_encounters:
				if candidate.encounter_id == event.action_target_id:
					_begin_boss(candidate)
					break
		StageEventDefinition.Action.MODIFY_CARD_COOLDOWN:
			_cooldown.apply(event)
		StageEventDefinition.Action.REQUEST_DROP, StageEventDefinition.Action.SET_REGION_FLAG:
			if event.trigger == StageEventDefinition.Trigger.BATTLE_END and not _battle_won:
				return
			if not AdventureBattleEventLedger.apply(event, requested_items, pending_region_flags, _reward_rng):
				push_error("关卡事件结算失败：" + str(event.event_id))
		StageEventDefinition.Action.FINISH_BATTLE:
			if not _battle_ended and not _ending_requested \
					and event.action_battle_result == StageEventDefinition.BattleResult.DEFEAT:
				_ending_requested = true
				zombies.main_game.request_adventure_event_result.call_deferred(event.action_battle_result)

## 返回 [param wave_number] 是否必须先清空该波，才能触发配置在清场边界的 Boss。
func has_wave_clear_encounter(wave_number: int) -> bool:
	for encounter: BossEncounterDefinition in phase.boss_encounters: # 每条配置属于当前阶段。
		if encounter.timing == BossEncounterDefinition.Timing.WAVE_CLEARED and encounter.wave == wave_number:
			return true
	return false

## 批量开始符合 [param timing] 和 [param wave_number] 的遭遇，让同组 Boss 同时入场。
func _begin_matching_boss(timing: int, wave_number: int) -> void:
	var matching: Array[BossEncounterDefinition] = [] # 一次提交同一个触发点的全部配置。
	for encounter: BossEncounterDefinition in phase.boss_encounters: # 保留资源声明的入场顺序。
		if encounter.timing == timing and (wave_number == 0 or encounter.wave == wave_number):
			matching.append(encounter)
	if not matching.is_empty():
		_boss_director.enqueue_batch(matching)

func _begin_boss(encounter: BossEncounterDefinition) -> void:
	_boss_director.enqueue(encounter)

func _on_boss_hp_changed(encounter_id: StringName, ratio: float) -> void:
	for event: StageEventDefinition in _ordered_events:
		if event.trigger != StageEventDefinition.Trigger.BOSS_HP_THRESHOLD or event.encounter_id != encounter_id:
			continue
		if _fired.has(event.event_id) and event.repeat_rule == StageEventDefinition.RepeatRule.ONCE_PER_PHASE:
			continue
		var matched: bool = ratio <= event.boss_hp_ratio if event.comparison == StageEventDefinition.Comparison.LESS_OR_EQUAL else ratio >= event.boss_hp_ratio
		var previous: bool = _threshold_states.get(event.event_id, false)
		_threshold_states[event.event_id] = matched
		if matched and not previous:
			_fired[event.event_id] = true
			_apply_action(event)

func _on_boss_exit(encounter_id: StringName, reason: int) -> void:
	AdventureSession.boss_exit_results[encounter_id] = reason
	for encounter: BossEncounterDefinition in phase.boss_encounters: # 必杀遭遇不可用撤退完成。
		if encounter.encounter_id == encounter_id and encounter.require_defeat and reason != StageEventDefinition.BossExitReason.DEFEATED:
			push_error("必须击败的 Boss 提前离场：" + str(encounter_id))
			zombies.main_game.request_adventure_event_result.call_deferred(StageEventDefinition.BattleResult.DEFEAT)
			return
	for event: StageEventDefinition in _ordered_events:
		if event.trigger != StageEventDefinition.Trigger.BOSS_EXITED or event.encounter_id != encounter_id:
			continue
		if event.boss_exit_reason != StageEventDefinition.BossExitReason.ANY and event.boss_exit_reason != reason:
			continue
		if event.repeat_rule == StageEventDefinition.RepeatRule.ONCE_PER_PHASE and _fired.has(event.event_id):
			continue
		_fired[event.event_id] = true
		_apply_action(event)

func has_pending_bosses() -> bool:
	return is_instance_valid(_boss_director) and _boss_director.has_pending()

func _on_boss_idle() -> void:
	if AdventureSession.can_accept_victory() and zombies.is_game_running():
		var game: MainGameManager = zombies.main_game # 普通及噩梦仍须清场，终末在博士击败后立即进入结算。
		game.create_trophy.call_deferred(game.camera_2d.get_screen_center_position())

func _on_boss_failed(id: StringName) -> void:
	push_error("Boss 遭遇无法启动：" + str(id))
	zombies.main_game.request_adventure_event_result.call_deferred(StageEventDefinition.BattleResult.DEFEAT)
