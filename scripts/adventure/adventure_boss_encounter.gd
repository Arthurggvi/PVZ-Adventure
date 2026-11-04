## 独立 Boss 遭遇：挂起自然波次，但使用自己的 Timer 持续生成小怪。
## 不调用原版 win_on_boss_death，Boss 死亡/明确撤退时停止援军并恢复自然波次。
extends Node
class_name AdventureBossEncounter

signal encounter_exited(encounter_id: StringName, exit_reason: int)

var config: BossEncounterDefinition
var wave_manager: ZombieWaveManager
var zombie_manager: ZombieManager
var boss: ZB000Base
var active := false
var summon_timer: Timer
var _summons: Dictionary[int, WeakRef] = {}
var _rng := RandomNumberGenerator.new()

func begin(encounter: BossEncounterDefinition, waves: ZombieWaveManager,
		manager: ZombieManager, known_tiers: Array[StringName]) -> bool:
	if active or encounter == null or waves == null or manager == null:
		return false
	if not encounter.validate(waves.max_wave_one_round, known_tiers).is_empty():
		return false
	config = encounter
	wave_manager = waves
	zombie_manager = manager
	_rng.randomize()
	wave_manager.suspend_advancement()
	# 使用已有 Boss 注册、死亡统计和音乐接口，原版提前胜利保持关闭。
	boss = zombie_manager.try_create_boss_from_card(config.boss_type)
	if boss == null:
		wave_manager.resume_advancement()
		return false
	active = true
	boss.signal_character_death.connect(_on_boss_defeated)
	boss.tree_exiting.connect(_on_boss_tree_exiting)
	summon_timer = Timer.new()
	summon_timer.wait_time = config.summon_interval_seconds
	summon_timer.one_shot = false
	add_child(summon_timer)
	summon_timer.timeout.connect(_on_summon_tick)
	summon_timer.start()
	return true

## Boss AI 可显式报告撤退；正式战斗中未死亡即离树也视为撤退。
func notify_escaped() -> void:
	if active and zombie_manager.is_game_running():
		_finish(StageEventDefinition.BossExitReason.ESCAPED)

func _on_boss_defeated() -> void:
	_finish(StageEventDefinition.BossExitReason.DEFEATED)

func _on_boss_tree_exiting() -> void:
	# 仍在正式战斗且 Boss 未死亡时离树，统一按撤退处理；场景卸载不能触发。
	if active and is_instance_valid(zombie_manager) and zombie_manager.is_game_running() \
		and zombie_manager.main_game == get_tree().current_scene \
		and not zombie_manager.main_game.is_queued_for_deletion():
		_finish(StageEventDefinition.BossExitReason.ESCAPED)

func _on_summon_tick() -> void:
	if not active or not zombie_manager.is_game_running():
		return
	var capacity: int = config.max_alive_summons - _summons.size()
	for i: int in range(mini(config.summon_count, capacity)):
		var type_key: Variant = _weighted_pick(config.summon_zombie_weights)
		var tier_key: Variant = _weighted_pick(config.summon_tier_weights)
		if type_key == null or tier_key == null:
			return
		var zombie: Zombie000Base = wave_manager.zombie_wave_create_manager.spawn_stage_support(
			type_key as CharacterRegistry.ZombieType, tier_key as StringName)
		if zombie == null:
			continue
		var instance_id: int = zombie.get_instance_id()
		_summons[instance_id] = weakref(zombie)
		zombie.signal_character_death.connect(_remove_summon.bind(instance_id))
		zombie.signal_character_be_hypno.connect(_remove_summon.bind(instance_id))
		zombie.tree_exiting.connect(_remove_summon.bind(instance_id))

func _weighted_pick(weights: Dictionary) -> Variant:
	var total := 0
	for key: Variant in weights:
		total += maxi(0, int(weights[key]))
	if total <= 0:
		return null
	var draw: int = _rng.randi_range(1, total)
	for key: Variant in weights:
		draw -= maxi(0, int(weights[key]))
		if draw <= 0:
			return key
	return null

func _remove_summon(instance_id: int) -> void:
	_summons.erase(instance_id)

func _finish(reason: int) -> void:
	if not active:
		return
	active = false
	if summon_timer != null:
		summon_timer.stop()
		summon_timer.queue_free()
		summon_timer = null
	if is_instance_valid(wave_manager) and is_instance_valid(zombie_manager) and zombie_manager.is_game_running():
		wave_manager.resume_advancement()
	encounter_exited.emit(config.encounter_id, reason)
	_summons.clear()

func _exit_tree() -> void:
	active = false
	if summon_timer != null:
		summon_timer.stop()
	_summons.clear()
