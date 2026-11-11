## Real lawn battle; all spawns use production manager and gameplay paths.
extends "res://tests/adventure/test_island_flow.gd"

func _run() -> void:
	get_tree().change_scene_to_file("res://scenes/main/01StartMenuV8.tscn")
	await _frames()
	Global.save_service.stop_autosave()
	var username := "white-duke-smoke-%d" % Time.get_ticks_usec()
	var user: User = get_tree().current_scene.user
	user.panel_create_new_user.line_edit.text = username
	user.panel_create_new_user.button_ok.pressed.emit()
	_select_user(username)
	assert(AdventureSession.open_adventure(), AdventureSession.entry_error)
	await _frames()
	var map: Control = get_tree().current_scene
	if map.canvas.has_node("Intro"):
		map.canvas.get_node("Intro")._finish()
	await _frames()
	map._select_stage(1)
	await _wait_battle()
	print("WHITE_DUKE_TEST_BATTLE_READY")
	var battle: MainGameManager = Global.main_game
	var manager: ZombieManager = battle.zombie_manager
	assert(manager.is_game_running())
	var ledger := manager.get_node("AdventureZombieDeathArchive") as AdventureZombieDeathArchive
	assert(ledger != null)
	var cell: PlantCell = battle.plant_cell_manager.all_plant_cells[2][4]
	var plant: Plant000Base = cell.create_plant(CharacterRegistry.PlantType.P002SunFlower,
		false,false,false,false,null,PlantCell.PlacementOrigin.LevelSetup)
	assert(plant != null)
	var ts: TombStoneManager = battle.plant_cell_manager.tomb_stone_manager
	var col: Array[int] = [4]
	var placed := ts.spawn_boss_graves(battle.plant_cell_manager.row_col.x,col)
	print("WHITE_DUKE_TEST_FORCED_GRAVES ",placed.size())
	assert(placed.size() == battle.plant_cell_manager.row_col.x)
	assert(plant.is_death)
	assert(is_instance_valid(cell.tombstone))
	var dead: Zombie000Base = manager.zombie_wave_manager.zombie_wave_create_manager.wave_create_zombie(
		CharacterRegistry.ZombieType.Z006Paper,2,-1,Callable(),false,
		AdventureZombieTierBinding.new(&"veteran"))
	assert(dead != null)
	dead.character_death()
	await _frames()
	var last: Array[Dictionary] = ledger.recent(20)
	assert(not last.is_empty() and last[0]["type"] == CharacterRegistry.ZombieType.Z006Paper)
	assert(last[0]["tier"] == &"veteran")
	print("WHITE_DUKE_TEST_ARCHIVE_OK")
	# Both flag-wave spawning and boss reviving use this single grave-cell
	# endpoint and the original zombie_up_from_tombstone animation.
	var marker: TombStone = placed[0]
	var emerged := marker.spawn_from_grave(CharacterRegistry.ZombieType.Z006Paper,
		AdventureZombieTierBinding.new(&"veteran"), 0.5, Callable(), false)
	assert(emerged != null and marker.new_zombie == emerged)
	assert(emerged.lane == marker.row_col.x)
	assert(is_equal_approx(emerged.global_position.x, marker.global_position.x))
	assert(emerged.is_body_up_from_ground)
	assert(emerged.hp_component.curr_hp == ceili(emerged.hp_component.max_hp * 0.5))
	print("WHITE_DUKE_TEST_GRAVE_CELL_EMERGENCE_AND_HALF_HP")
	var boss: ZB003WhiteDuke = manager.try_create_boss_from_card(
		CharacterRegistry.ZombieBossType.ZB003WhiteDuke) as ZB003WhiteDuke
	assert(boss != null and boss.hp_component.max_hp==90000)
	print("WHITE_DUKE_TEST_BOSS_CREATED")
	await _frames()
	assert(is_instance_valid(boss._graves))
	# White Duke can never place graves or revive zombies in columns 0 and 1.
	assert(boss.config.minimum_grave_column == 2)
	var front_cols: Array[int] = [0, 1]
	assert(boss._graves._target_columns(front_cols).is_empty())
	assert(boss._graves.create_graves(2, front_cols).is_empty())
	assert(boss._graves.graves_in_columns(front_cols).is_empty())
	var extra_graves := boss._graves.create_graves(1)
	assert(extra_graves.size() == 1 and extra_graves[0].row_col.y >= 2)
	for owned_stone: TombStone in boss._graves.graves_in_columns():
		assert(owned_stone.row_col.y >= 2)
	print("WHITE_DUKE_TEST_EXCLUDED_FRONT_COLUMNS")
	await get_tree().create_timer(4.0).timeout
	print("WHITE_DUKE_TEST_ENTRY_STATE ",boss.state)
	assert(boss.state == ZB003WhiteDuke.State.IDLE, "entry->summon->idle")
	assert(ts.tombstone_num >= 5)
	assert(not boss.hp_component.damage_immune)
	boss._begin_action(WhiteDukeBehaviorTree.Action.RESURRECT)
	await get_tree().create_timer(1.7).timeout
	assert(boss.state == ZB003WhiteDuke.State.IDLE)
	assert(ts.tombstone_num >= 7)
	# Fixed-row support uses native spawn + tier binding; no parallel zombie factory.
	boss.skills.perform(WhiteDukeBehaviorTree.Action.COMMAND)
	boss.skills.perform(WhiteDukeBehaviorTree.Action.BREACH)
	var jackson_rows: Dictionary[int,bool] = {}
	var paper_rows: Dictionary[int,bool] = {}
	var one_for_buff: Zombie000Base
	for spawned: Zombie000Base in manager.all_zombies_1d:
		if spawned.is_death:
			continue
		if spawned.zombie_type == CharacterRegistry.ZombieType.Z009Jackson:
			assert(spawned.adventure_tier_id==&"veteran")
			jackson_rows[spawned.lane]=true
		if spawned.zombie_type == CharacterRegistry.ZombieType.Z006Paper and spawned.adventure_tier_id==&"veteran":
			paper_rows[spawned.lane]=true
			one_for_buff=spawned
	assert(jackson_rows.has(1) and jackson_rows.has(3))
	assert(paper_rows.size() == manager.all_zombie_rows.size())
	assert(one_for_buff != null)
	boss.skills.perform(WhiteDukeBehaviorTree.Action.FRENZY)
	assert(one_for_buff.get_node_or_null("AdventureTimedSpeedBoost") != null)
	assert(one_for_buff.hp_component.is_damage_immune())
	print("WHITE_DUKE_TEST_SKILLS_COMMAND_FRENZY_BREACH_OK")
	boss.hp_component.apply_unblocked_loss(46000,BulletRegistry.AttackMode.Norm,false,false)
	assert(boss.boss_phase == 2)
	print("WHITE_DUKE_TEST_PHASE_TRIGGERED")
	await get_tree().create_timer(5.0).timeout
	print("WHITE_DUKE_TEST_PHASE_STATE ",boss.state)
	assert(boss.state == ZB003WhiteDuke.State.IDLE,"phase loop did not finish")
	var cols := battle.plant_cell_manager.row_col.y
	for row in range(battle.plant_cell_manager.row_col.x):
		for c in range(cols-3,cols):
			assert(ts.all_is_tombstone[row][c],"phase three columns not filled")
	assert(not boss.hp_component.damage_immune)
	boss.hp_component.Hp_loss_death(false)
	assert(boss.is_death)
	await get_tree().create_timer(1.2).timeout
	assert(not is_instance_valid(boss),"death teleport failed")
	print("WHITE_DUKE_REAL_BATTLE_PASS forced_plants, death_archive, opening, skill, phase, death")
	Global.save_service.stop_autosave()
	get_tree().quit(0)
