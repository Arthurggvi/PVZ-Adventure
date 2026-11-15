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
	# 验证每阶段的自然墓碑规则和独立的固定墓碑事件。
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for spec in [{"stage": 3, "sun": true, "banner": true},
			{"stage": 4, "sun": false, "banner": true}]:
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
				"flag-wave zombies from existing graves on both grave stages")
			var expected_flag: Vector2i = Vector2i(2, 3) if int(spec["stage"]) == 3 else Vector2i.ZERO
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
			var grave_events: Dictionary = {} # 波次和墓碑数量，0 代表开战时。
			for event: StageEventDefinition in phase.events:
				if event.action != StageEventDefinition.Action.SPAWN_TOMBSTONES:
					continue
				var expected_trigger := StageEventDefinition.Trigger.BATTLE_START if event.wave == 0 else StageEventDefinition.Trigger.WAVE_STARTED # 固定墓碑的触发时机。
				_require(event.trigger == expected_trigger, "fixed grave trigger timing")
				_require(event.repeat_rule == StageEventDefinition.RepeatRule.ONCE_PER_PHASE,
					"fixed grave event runs once")
				_require(not grave_events.has(event.wave), "no duplicate grave event at the same wave")
				grave_events[event.wave] = event.action_count
			var expected_events: Dictionary = {0: 8, 30: 8, 40: 8} if phase.kind == StagePhaseDefinition.Kind.NIGHTMARE else {0: 6}
			_require(grave_events == expected_events, "fixed grave count and wave schedule")
	# Placement candidates must skip plants, special blockers and existing tombstones.
	var grid := PlantCellManager.new()
	var cells: Array = []
	for c in range(6):
		var check_cell := PlantCell.new()
		check_cell.row_col = Vector2i(0, c)
		cells.append(check_cell)
	var grid_host: MainGameManager = _bind_existing_cells(cells) # 原测试夹具改用空间注册接口。
	grid.main_game = grid_host
	var blocked_plant := Plant000Base.new()
	cells[2].plant_in_cell[CharacterRegistry.PlacePlantInCell.Norm] = blocked_plant
	cells[3].can_common_plant = false
	var manager_probe := TombStoneManager.new()
	manager_probe.plant_cell_manager = grid
	var occupied_grave := TombStone.new() # 原有占用案例使用真实墓碑引用。
	cells[4].tombstone = occupied_grave
	var candidates := manager_probe.available_pvz2_positions()
	_require(candidates == [Vector2i(0, 5)], "grave placement ignores occupied cells")
	manager_probe.free()
	occupied_grave.free()
	blocked_plant.free()
	for check_cell: PlantCell in cells:
		check_cell.free()
	grid.free()
	grid_host.free()
	cell.tombstone = grave
	var cell_manager := PlantCellManager.new()
	var save_host: MainGameManager = _bind_existing_cells([cell]) # 原有序列化案例的空间夹具。
	cell_manager.main_game = save_host
	var stone_manager := TombStoneManager.new()
	stone_manager.plant_cell_manager = cell_manager
	var save_data := stone_manager.get_save_game_data_tomb_stone_manager()
	var records: Array = save_data.get("tombstones", [])
	_require(records.size() == 1 and records[0].get("kind") == "pvz2" \
		and records[0].get("hp") == 400, "serialize PVZ2 type and HP")
	stone_manager.free()
	cell_manager.free()
	save_host.free()
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


## 为既有案例绑定当前空间接口，不增加案例或执行范围。
func _bind_existing_cells(cells: Array) -> MainGameManager:
	var game := MainGameManager.new() # 离树夹具宿主，不启动战斗。
	game.board = BoardRuntime.new()
	var count: int = 1 # 夹具中的最大逻辑行数。
	for cell: PlantCell in cells: # 保留案例原有逻辑地址。
		count = maxi(count, cell.row_col.x + 1)
	var lanes: Array[BoardLaneDefinition] = [] # 夹具的攻击行。
	for index: int in range(count): # 每个原有逻辑行一个声明。
		var lane := BoardLaneDefinition.new() # 原有测试无需装配标记节点。
		lane.lane_id = StringName("lane_%d" % index)
		lanes.append(lane)
	game.board.configure_lanes(lanes)
	game.board.terrains[&"grass"] = BoardTerrainDefinition.legacy(0)
	for cell: PlantCell in cells: # 注册现有节点，不替换测试对象。
		var data := BoardCellDefinition.new() # 稳定身份来自原有地址。
		data.address = cell.row_col
		data.cell_id = StringName("cell_%d_%d" % [cell.row_col.x, cell.row_col.y])
		game.board.register_cell(cell, data)
	game.board.finish_configuration()
	return game
