## 原生菜单冒险入口、首卡持久化与跨玩家隔离：不触碰真实玩家数据。
extends "res://tests/adventure/test_island_flow.gd"

func _run() -> void:
	assert(OS.get_user_data_dir().contains("entry-test-user"))
	get_tree().change_scene_to_file("res://scenes/main/01StartMenuCoastal.tscn")
	await _frames()
	Global.save_service.stop_autosave()
	Global.user_manager.set_current_user("")
	await _enter_island_from_menu()
	assert(AdventureSession.progress == null and not AdventureSession.adventure_active)
	var a := "entry-a-%s" % Time.get_ticks_usec()
	var b := a + "-b"
	_create_user(a)
	_create_user(b)
	_select_user(a)
	await _enter_island_from_menu()
	await _frames()
	assert(AdventureSession.progress.started and not AdventureSession.progress.intro_completed)
	var path_a := "user://%s/GlobalSaveGame.json" % a
	assert(FileAccess.file_exists(path_a))
	assert(not FileAccess.file_exists("user://%s/adventure/zombie_island_v1.json" % a))
	var intro: Control = get_tree().current_scene.canvas.get_node("Intro")
	intro._finish()
	await _frames()
	assert(AdventureSession.progress.intro_completed)
	assert(Global.adventure_inventory.list_cards().size() == 2)
	assert(Global.global_game_state.adventure_state.claimed_rewards.get("intro_starter_cards", false))
	# 直接重复赠卡不会累计数量，已领取标记属于相同 Global JSON。
	assert(AdventureSession.grant_starter_cards())
	assert(Global.adventure_inventory.list_cards().size() == 2)
	# 地区进度的实验性胜利标记只改内存，持久化仍经唯一 SaveService。
	assert(AdventureSession.progress.record_victory())
	assert(Global.save_service.save_now())
	_menu_return()
	await _frames()
	_select_user(b)
	await _enter_island_from_menu()
	await _frames()
	assert(not AdventureSession.progress.intro_completed and not AdventureSession.progress.stage_1_cleared)
	assert(Global.adventure_inventory.list_cards().is_empty())
	_menu_return()
	await _frames()
	_select_user(a)
	await _enter_island_from_menu()
	await _frames()
	assert(AdventureSession.progress.stage_1_cleared and AdventureSession.is_unlocked(2))
	assert(Global.adventure_inventory.list_cards().size() == 2)
	assert(not get_tree().current_scene.canvas.has_node("Intro"))
	print("PASS: native menu, single global save, starter idempotence, profile A/B/A")
	get_tree().quit(0)

func _create_user(username: String) -> void:
	var user: User = get_tree().current_scene.user
	user.panel_create_new_user.line_edit.text = username
	user.panel_create_new_user.button_ok.pressed.emit()

func _menu_return() -> void:
	get_tree().current_scene._return_menu()
	# No await here: scene transition is asynchronous; caller waits on _frames().
