## 噩梦草坪：钥匙入口、强制选卡、突袭、冷却修饰和 Boss 的独立援军实战。
extends "res://tests/adventure/test_island_flow.gd"

func _run() -> void:
	assert(OS.get_user_data_dir().contains("p3-nightmare-test"))
	get_tree().change_scene_to_file("res://scenes/main/01StartMenuV8.tscn")
	await _frames()
	Global.save_service.stop_autosave()
	var username := "p3-nightmare-%d" % Time.get_ticks_usec()
	var user: User = get_tree().current_scene.user
	user.panel_create_new_user.line_edit.text = username
	user.panel_create_new_user.button_ok.pressed.emit()
	_select_user(username)
	await _enter_island_from_menu()
	await _frames()
	var map: Control = get_tree().current_scene
	map.canvas.get_node("Intro")._finish()
	await _frames()
	assert(AdventureSession.progress.intro_completed)
	AdventureStageCatalog.mark_cleared(Global.global_game_state.adventure_state,
		AdventureStageCatalog.LAWN_ID, StagePhaseDefinition.Kind.NORMAL)
	assert(Global.adventure_inventory.add_item("lawn_nightmare_key", 1))
	map._select_stage(1)
	assert(map.phase_dialog.dialog_text.contains("可进入"))
	map.phase_dialog.custom_action.emit(&"nightmare")
	await _wait_battle()
	var battle: MainGameManager = Global.main_game
	assert(AdventureSession.active_phase_kind == StagePhaseDefinition.Kind.NIGHTMARE)
	assert(battle.game_para.look_show_zombie and battle.game_para.can_choosed_card)
	var waves: ZombieWaveManager = battle.zombie_manager.zombie_wave_manager
	var runtime: AdventureBattleRuntime = battle.adventure_runtime
	assert(runtime != null and runtime.phase.events.size() == 2)
	assert(runtime.phase.boss_encounters.size() == 1)
	var deadline: int = Time.get_ticks_msec() + 30000
	while waves.curr_wave < 0 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	assert(waves.curr_wave >= 0)
	var zombies: ZombieManager = battle.zombie_manager
	var count_before: int = zombies.curr_zombie_num
	waves.adventure_wave_started.emit(3)
	assert(zombies.curr_zombie_num >= count_before + 5)
	var cards: Array[Card] = battle.card_manager.card_slot_battle.curr_cards
	assert(cards.size() == 2)
	waves.adventure_wave_started.emit(5)
	assert(is_equal_approx(cards[0].adventure_cooldown_multiplier, 1.5))
	cards[0].card_cool()
	assert(is_equal_approx(cards[0]._cool_timer, cards[0].cool_time * 1.5))
	cards[0].set_card_cool_end()
	runtime._cooldown._elapsed += 21.0
	runtime._cooldown._process(0.0)
	assert(is_equal_approx(cards[0].adventure_cooldown_multiplier, 1.0))
	waves.adventure_wave_started.emit(7)
	assert(runtime.boss_runtime != null and runtime.boss_runtime.active)
	assert(waves.is_advancement_suspended)
	var old_wave: int = waves.curr_wave
	waves.start_next_wave()
	assert(waves.curr_wave == old_wave)
	await get_tree().create_timer(5.8).timeout
	assert(waves.is_advancement_suspended and waves.curr_wave == old_wave)
	assert(runtime.boss_runtime._summons.size() >= 2)
	var encounter_id: StringName = runtime.boss_runtime.config.encounter_id
	runtime.boss_runtime.notify_escaped()
	await get_tree().create_timer(0.35).timeout
	assert(not waves.is_advancement_suspended and waves.curr_wave > old_wave)
	assert(AdventureSession.boss_exit_results[encounter_id] == StageEventDefinition.BossExitReason.ESCAPED)
	# 人工调用胜利结算只验证存档路由，不作为完成十波的证据。
	assert(AdventureSession.settle_victory())
	AdventureSession.finish_victory()
	await _frames()
	assert(AdventureStageCatalog.is_cleared(Global.global_game_state.adventure_state,
		AdventureStageCatalog.LAWN_ID, StagePhaseDefinition.Kind.NIGHTMARE))
	assert(AdventureSession.active_level == null)
	print("PASS: nightmare entry, events, boss independent minions, escape and victory save routing")
	get_tree().quit(0)
