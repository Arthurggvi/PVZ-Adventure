## 冒险关卡事件及 Boss 触发；原版模式不实例化此节点。
## 监听自然波次信号，不按帧遍历僵尸或植物实例。
extends Node
class_name AdventureStageRuntime

var waves: ZombieWaveManager
var zombies: ZombieManager
var phase: StagePhaseDefinition
var boss_runtime: AdventureBossEncounter
var elapsed_seconds := 0.0
var _fired: Dictionary[StringName, bool] = {}
var _threshold_states: Dictionary[StringName, bool] = {}
var _last_clear_wave := 0
var _ordered_events: Array[StageEventDefinition] = []
var _cooldown_effects: Dictionary[StringName, Dictionary] = {}

func setup(wave_manager: ZombieWaveManager, zombie_manager: ZombieManager,
		stage_phase: StagePhaseDefinition) -> void:
	waves = wave_manager
	zombies = zombie_manager
	phase = stage_phase.duplicate(true) as StagePhaseDefinition
	_ordered_events = phase.events.duplicate()
	_ordered_events.sort_custom(func(a: StageEventDefinition, b: StageEventDefinition) -> bool:
		return a.order < b.order)

func _ready() -> void:
	waves.adventure_battle_started.connect(_on_battle_start)
	waves.adventure_wave_before.connect(_on_wave_before)
	waves.adventure_wave_started.connect(_on_wave_started)
	zombies.signal_natural_refresh_zombie_num_change.connect(_on_natural_count)
	# 已初始化的格子才连接种植信号，关卡卸载自动断开。
	for row: Array in zombies.main_game.plant_cell_manager.all_plant_cells:
		for cell: PlantCell in row:
			cell.signal_plant_create.connect(_on_plant_placed)

func _on_battle_start() -> void:
	_fire(StageEventDefinition.Trigger.BATTLE_START)
	_begin_matching_boss(BossEncounterDefinition.Timing.PHASE_START, 0)

func _on_wave_before(wave_number: int) -> void:
	_fire(StageEventDefinition.Trigger.WAVE_BEFORE, wave_number)
	_begin_matching_boss(BossEncounterDefinition.Timing.WAVE_BEFORE, wave_number)

func _on_wave_started(wave_number: int) -> void:
	_fire(StageEventDefinition.Trigger.WAVE_STARTED, wave_number)
	_begin_matching_boss(BossEncounterDefinition.Timing.WAVE_STARTED, wave_number)

func _on_natural_count(count: int) -> void:
	var wave_number: int = waves.curr_wave + 1
	if count != 0 or wave_number <= 0 or _last_clear_wave == wave_number:
		return
	_last_clear_wave = wave_number
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
	if not _cooldown_effects.is_empty():
		var changed := false
		for event_id: StringName in _cooldown_effects.keys():
			if elapsed_seconds >= float(_cooldown_effects[event_id]["end"]):
				_cooldown_effects.erase(event_id)
				changed = true
		if changed:
			_refresh_card_cooldowns()
	_fire(StageEventDefinition.Trigger.ELAPSED_TIME)
	_fire(StageEventDefinition.Trigger.ZOMBIE_COUNT, 0, {"count": zombies.curr_zombie_num})

func _fire(trigger: int, wave_number: int = 0, payload: Dictionary = {}) -> void:
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
		StageEventDefinition.Action.BEGIN_BOSS_ENCOUNTER:
			for candidate: BossEncounterDefinition in phase.boss_encounters:
				if candidate.encounter_id == event.action_target_id:
					_begin_boss(candidate)
					break
		StageEventDefinition.Action.PAUSE_NATURAL_WAVES:
			waves.suspend_advancement()
		StageEventDefinition.Action.RESUME_NATURAL_WAVES:
			if boss_runtime == null or not boss_runtime.active:
				waves.resume_advancement()
		StageEventDefinition.Action.MODIFY_CARD_COOLDOWN:
			_apply_cooldown(event)

func _begin_matching_boss(timing: int, wave_number: int) -> void:
	for encounter: BossEncounterDefinition in phase.boss_encounters:
		if encounter.timing == timing and (wave_number == 0 or encounter.wave == wave_number):
			_begin_boss(encounter)

func _begin_boss(encounter: BossEncounterDefinition) -> void:
	if boss_runtime != null and boss_runtime.active:
		return
	var controller := AdventureBossEncounter.new()
	add_child(controller)
	if not controller.begin(encounter, waves, zombies, AdventureStageCatalog.tier_ids()):
		controller.queue_free()
		push_error("无法启动 Boss 遭遇：" + str(encounter.encounter_id))
		return
	boss_runtime = controller
	controller.encounter_exited.connect(_on_boss_exit)
	controller.boss.hp_component.signal_hp_loss.connect(_on_boss_hp_changed.bind(encounter.encounter_id))

func _on_boss_hp_changed(_current_hp: int, _dropped: bool, encounter_id: StringName) -> void:
	if boss_runtime == null or not boss_runtime.active:
		return
	var hp: HpComponent = boss_runtime.boss.hp_component
	var ratio := float(hp.curr_hp) / maxf(1.0, float(hp.max_hp))
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
	var completed: AdventureBossEncounter = boss_runtime
	AdventureSession.boss_exit_results[encounter_id] = reason
	for event: StageEventDefinition in _ordered_events:
		if event.trigger != StageEventDefinition.Trigger.BOSS_EXITED or event.encounter_id != encounter_id:
			continue
		if event.boss_exit_reason != StageEventDefinition.BossExitReason.ANY and event.boss_exit_reason != reason:
			continue
		if event.repeat_rule == StageEventDefinition.RepeatRule.ONCE_PER_PHASE and _fired.has(event.event_id):
			continue
		_fired[event.event_id] = true
		_apply_action(event)
	if is_instance_valid(completed):
		completed.queue_free()
	if boss_runtime == completed:
		boss_runtime = null

func _apply_cooldown(event: StageEventDefinition) -> void:
	if event.cooldown_operation == StageEventDefinition.CooldownOperation.ADJUST_REMAINING_SECONDS:
		for card: Card in zombies.main_game.card_manager.card_slot_battle.curr_cards:
			if _matches_card(card, event):
				card.adventure_adjust_remaining_cooldown(event.cooldown_value)
		return
	_cooldown_effects[event.event_id] = {"end": elapsed_seconds + event.cooldown_duration_seconds,
		"factor": event.cooldown_value, "scope": event.cooldown_scope, "plant_type": event.cooldown_plant_type}
	_refresh_card_cooldowns()

func _matches_card(card: Card, event: StageEventDefinition) -> bool:
	return event.cooldown_scope == StageEventDefinition.CooldownScope.ALL_SELECTED or \
		(event.cooldown_scope == StageEventDefinition.CooldownScope.PLANT_TYPE and card.card_reference.content_id == event.cooldown_plant_type)

func _refresh_card_cooldowns() -> void:
	for card: Card in zombies.main_game.card_manager.card_slot_battle.curr_cards:
		var product := 1.0
		for effect: Dictionary in _cooldown_effects.values():
			if effect.scope == StageEventDefinition.CooldownScope.ALL_SELECTED or \
				(effect.scope == StageEventDefinition.CooldownScope.PLANT_TYPE and effect.plant_type == card.card_reference.content_id):
				product *= float(effect.factor)
		card.adventure_cooldown_multiplier = clampf(product, 0.05, 20.0)

func _exit_tree() -> void:
	_cooldown_effects.clear()
	if is_instance_valid(zombies) and is_instance_valid(zombies.main_game):
		_refresh_card_cooldowns()
