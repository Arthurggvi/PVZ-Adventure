## A battle-scoped executor. Owns no tile state; delegates creation to TombStoneManager.
extends Node
class_name AdventureGravestoneDirector

var rules: GravestoneWaveRules
var manager: TombStoneManager
var waves: ZombieWaveManager
var _generation := 0
var _rng := RandomNumberGenerator.new()

func configure(config: GravestoneWaveRules, grave_manager: TombStoneManager,
		wave_manager: ZombieWaveManager) -> void:
	rules = config
	manager = grave_manager
	waves = wave_manager
	_generation += 1
	_rng.randomize()

func clear() -> void:
	_generation += 1
	rules = null

func on_wave_started(wave_number: int, is_flag: bool) -> void:
	if rules == null or not is_instance_valid(manager) or not is_instance_valid(waves) \
			or not waves.zombie_manager.is_game_running():
		return
	var instructions := rules.plan(wave_number, is_flag, _rng)
	manager.create_pvz2_tombstone(int(instructions["count"]))
	if instructions["summon"]:
		_summon_after_emergence(_generation)

func _summon_after_emergence(generation: int) -> void:
	await get_tree().create_timer(rules.flag_zombie_delay_seconds, false).timeout
	if generation != _generation or rules == null or not is_instance_valid(waves) 			or not waves.zombie_manager.is_game_running():
		return
	var graves: Array[TombStone] = manager.plant_cell_manager.tombstone_list.duplicate()
	for stone: TombStone in graves:
		if generation != _generation or not waves.zombie_manager.is_game_running():
			return
		if stone is PvZ2AttackableTombstone and is_instance_valid(stone) 				and not stone.is_queued_for_deletion():
			var types: Array[CharacterRegistry.ZombieType] = waves.zombie_type_candidate_tombstone
			if not types.is_empty():
				stone.create_new_zombie(types.pick_random())
