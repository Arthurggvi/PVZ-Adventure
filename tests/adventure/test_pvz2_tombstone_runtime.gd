extends Node

class ProbeCell extends PlantCell:
	var removals := 0
	func tombstone_death_update_plant_cell_data() -> void:
		removals += 1

const GRAVE_SCENE: PackedScene = preload("res://scenes/item/game_scenes_item/pvz2_attackable_tombstone.tscn")

func _ready() -> void:
	call_deferred("_test")

func _test() -> void:
	var grave := GRAVE_SCENE.instantiate() as PvZ2AttackableTombstone
	_require(grave != null, "grave instance")
	if grave == null:
		return
	var cell := PlantCell.new()
	cell.row_col = Vector2i(2, 3)
	grave.init_tombstone(cell)
	add_child(grave)
	await get_tree().process_frame
	_require(grave.damage_receiver.lane == 2, "lane initialization")
	_require(grave.damage_receiver.is_in_group(&"lobber_secondary_targets"), "lobber target priority")
	_require(grave.get_current_hp() == 700, "initial 700 HP")
	var visual_0 := grave.tombstone.texture
	grave.damage_receiver.be_attacked_bullet(20)
	await get_tree().process_frame
	_require(grave.get_current_hp() == 680, "bullet 20 damage")
	_require(grave.tombstone.texture != visual_0, "damage art changed")
	for step in [{"hp": 700, "index": 0}, {"hp": 699, "index": 1},
			{"hp": 550, "index": 2}, {"hp": 400, "index": 3}, {"hp": 250, "index": 4}]:
		grave.restore_hp(int(step["hp"]))
		_require(grave.tombstone.texture == PvZ2AttackableTombstone.DAMAGE_ART[int(step["index"])], "damage art threshold " + str(step["index"]))
	grave.restore_hp(400)
	_require(grave.get_current_hp() == 400, "restore HP")
	_require(grave.get_tombstone_kind() == &"pvz2", "save kind")
	# Stage resources remain authoritative for both phases; no leftover fixed opening spawns.
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for spec in [{"stage": 3, "sun": true, "banner": true},
			{"stage": 4, "sun": false, "banner": false}]:
		var stage: StageDefinition = AdventureStageRegistry.resolve(int(spec["stage"]))
		_require(stage != null, "grave stage loads")
		if stage == null:
			continue
		_require(not stage.environment.daytime and stage.environment.daytime_sun == bool(spec["sun"]),
			"stage dusk/night and sky-sun separation")
		for phase: StagePhaseDefinition in stage.phases:
			var rules: GravestoneWaveRules = phase.gravestone_rules
			_require(rules != null, "grave phase has rules")
			if rules == null:
				continue
			_require(rules.validate().is_empty(), "grave rule validation")
			_require(rules.regular_interval == 3 and rules.regular_count == Vector2i(1, 2),
				"natural graves every three waves")
			_require(rules.flag_summons_one_per_grave == bool(spec["banner"]),
				"banner zombies only upstream")
			var expected_flag: Vector2i = Vector2i(2, 3) if bool(spec["banner"]) else Vector2i.ZERO
			_require(rules.flag_count == expected_flag, "banner grave quantities")
			for number: int in range(1, 11):
				var flag: bool = phase.wave_profile.flag_wave_numbers().has(number)
				var plan: Dictionary = rules.plan(number, flag, rng)
				var base_min: int = 1 if number % 3 == 0 else 0
				var base_max: int = 2 if number % 3 == 0 else 0
				if flag:
					base_min += expected_flag.x
					base_max += expected_flag.y
				_require(int(plan["count"]) >= base_min and int(plan["count"]) <= base_max,
					"grave wave count " + str(number))
				_require(bool(plan["summon"]) == (flag and bool(spec["banner"])),
					"banner spawning eligibility")
			var level: ResourceLevelData = AdventureBattleEnvironmentAdapter.build(stage, phase)
			_require(level != null and not level.is_day and level.is_day_sun == bool(spec["sun"]),
				"battle environment projection")
			for event: StageEventDefinition in phase.events:
				_require(event.action != StageEventDefinition.Action.SPAWN_TOMBSTONES,
					"no duplicate fixed-start tombstones")
	# Placement candidates must skip plants, special blockers and existing tombstones.
	var grid := PlantCellManager.new()
	grid.row_col = Vector2i(1, 6)
	var cells: Array = []
	for c in range(6):
		var check_cell := PlantCell.new()
		check_cell.row_col = Vector2i(0, c)
		cells.append(check_cell)
	grid.all_plant_cells = [cells]
	var blocked_plant := Plant000Base.new()
	cells[2].plant_in_cell[CharacterRegistry.PlacePlantInCell.Norm] = blocked_plant
	cells[3].can_common_plant = false
	var manager_probe := TombStoneManager.new()
	manager_probe.plant_cell_manager = grid
	manager_probe.all_is_tombstone = [[false, false, false, false, true, false]]
	var candidates := manager_probe.available_pvz2_positions()
	_require(candidates == [Vector2i(0, 5)], "grave placement ignores occupied cells")
	manager_probe.free()
	blocked_plant.free()
	for check_cell: PlantCell in cells:
		check_cell.free()
	grid.free()
	cell.tombstone = grave
	var cell_manager := PlantCellManager.new()
	cell_manager.all_plant_cells = [[cell]]
	var stone_manager := TombStoneManager.new()
	stone_manager.plant_cell_manager = cell_manager
	var save_data := stone_manager.get_save_game_data_tomb_stone_manager()
	var records: Array = save_data.get("tombstones", [])
	_require(records.size() == 1 and records[0].get("kind") == "pvz2" \
		and records[0].get("hp") == 400, "serialize PVZ2 type and HP")
	stone_manager.free()
	cell_manager.free()
	var death_cell := ProbeCell.new()
	death_cell.row_col = Vector2i(1, 4)
	var death_grave := GRAVE_SCENE.instantiate() as PvZ2AttackableTombstone
	death_grave.init_tombstone(death_cell)
	death_cell.tombstone = death_grave
	add_child(death_grave)
	await get_tree().process_frame
	death_grave.damage_receiver.be_attacked_bullet(700)
	await get_tree().process_frame
	_require(death_cell.removals == 1, "death notifies cell once")
	_require(not is_instance_valid(death_grave), "dead grave frees itself")
	death_cell.free()
	if not _failed:
		print("PVZ2_TOMBSTONE_RUNTIME_PASS")
	grave.queue_free()
	cell.free()
	get_tree().quit(1 if _failed else 0)

var _failed := false
func _require(ok: bool, description: String) -> void:
	if not ok:
		_failed = true
		push_error("PVZ2_TOMBSTONE_FAIL: " + description)
