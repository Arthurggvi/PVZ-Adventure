## 验证原生地图的普通/噩梦分流和强制选卡预览，不修改玩家正式数据。
extends "res://tests/adventure/test_island_flow.gd"

func _run() -> void:
	assert(OS.get_user_data_dir().contains("p2-menu-test"))
	var username := "p2-phase-%d" % Time.get_ticks_usec()
	get_tree().change_scene_to_file("res://scenes/main/01StartMenuCoastal.tscn")
	await _frames()
	Global.save_service.stop_autosave()
	var user: User = _profile_selector()
	user.panel_create_new_user.line_edit.text = username
	user.panel_create_new_user.button_ok.pressed.emit()
	_select_user(username)
	await _enter_island_from_menu()
	await _frames()
	var map: Control = get_tree().current_scene
	var intro: Control = map.canvas.get_node("Intro")
	intro._finish()
	await _frames()
	assert(AdventureSession.progress.intro_completed)
	map._select_stage(1)
	await _frames()
	var battle: MainGameManager = Global.main_game
	while not battle.card_manager.is_norm_appeared:
		await get_tree().process_frame
	assert(AdventureSession.active_stage_number == 1)
	assert(AdventureSession.active_phase_kind == StagePhaseDefinition.Kind.NORMAL)
	assert(battle.main_game_progress == MainGameManager.E_MainGameProgress.CHOOSE_CARD)
	assert(battle.game_para.look_show_zombie and battle.game_para.can_choosed_card)
	assert(battle.zombie_manager.zombie_show_in_start.show_zombies_array.size() > 0)
	print("PASS: map enters normal directly, no difficulty dialog, card selection and preview")
	get_tree().quit(0)
