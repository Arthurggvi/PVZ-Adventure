## 原版运行边界验收：实际加载原版战斗场景，不持有冒险阶段与事件控制器。
extends Node

func _ready() -> void:
	get_tree().current_scene = null
	call_deferred("_run")

func _run() -> void:
	assert(OS.get_user_data_dir().contains("legacy-isolation-test"))
	Global.save_service.stop_autosave()
	assert(AdventureSession.active_level == null)
	var template: ResourceLevelData = load("res://resources/adventure/island_lawn.tres")
	assert(template != null)
	var level: ResourceLevelData = template.duplicate(true) as ResourceLevelData
	level.look_show_zombie = false
	level.can_choosed_card = false
	level.max_wave = 10
	level.zombie_refresh_types = [CharacterRegistry.ZombieType.Z001Norm]
	Global.game_para = level
	var scene_path: String = Global.main_scene_registry.MainScenesMap[level.game_sences]
	assert(get_tree().change_scene_to_file(scene_path) == OK)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	var battle: MainGameManager = Global.main_game
	assert(battle != null and battle.game_para == level)
	assert(not battle.is_test)
	assert(battle.adventure_runtime == null)
	assert(not AdventureSession.owns_battle(level))
	var waves: ZombieWaveManager = battle.zombie_manager.zombie_wave_manager
	assert(waves.zombie_wave_create_manager.adventure_wave_profile == null)
	assert(waves.max_wave == 10 and waves.max_wave_one_round == 10)
	var until: int = Time.get_ticks_msec() + 21000
	while waves.curr_wave < 0 and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	assert(waves.curr_wave >= 0, "Legacy natural wave never started")
	assert(waves.curr_wave_type == ZombieWaveManager.E_WaveType.Norm)
	assert(not waves.is_advancement_suspended)
	assert(battle.adventure_runtime == null)
	assert(get_tree().change_scene_to_file("res://scenes/main/01StartMenuCoastal.tscn") == OK)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(Global.main_game == null)
	print("PASS: legacy actual main game, original wave path, no adventure runtime or phase")
	get_tree().quit(0)
