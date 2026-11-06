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
	map._select_stage(1)
	await _wait_battle()
	var battle: MainGameManager = Global.main_game
	assert(AdventureSession.active_phase_kind == StagePhaseDefinition.Kind.NORMAL)
	# 真实自然波次与清怪接口推进普通清场；首通钥匙在检查点结算后当场可用。
	Engine.time_scale = 6.0
	var normal_deadline: int = Time.get_ticks_msec() + 60000
	while AdventureSession.challenge_state == AdventureSession.ChallengeState.NORMAL_ACTIVE \
			and Time.get_ticks_msec() < normal_deadline:
		if battle.zombie_manager.curr_zombie_num > 0:
			battle.zombie_manager.death_all_zombie()
		await get_tree().create_timer(0.2, true, false, true).timeout
	assert(AdventureSession.challenge_state == AdventureSession.ChallengeState.NORMAL_COMPLETE)
	assert(Global.adventure_inventory.get_item_count("lawn_nightmare_key") >= 1)
	assert(battle.adventure_continuation.dialog != null)
	Engine.time_scale = 1.0
	battle.adventure_continuation.dialog.confirmed.emit()
	await _frames()
	assert(AdventureSession.active_phase_kind == StagePhaseDefinition.Kind.NIGHTMARE)
	assert(AdventureSession.challenge_state == AdventureSession.ChallengeState.NIGHTMARE_ACTIVE)
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
	# 任何未到最后自然波的外部结算请求均应被拒绝。
	assert(not AdventureSession.settle_victory())
	assert(AdventureStageCatalog.is_cleared(Global.global_game_state.adventure_state,
		AdventureStageCatalog.LAWN_ID, StagePhaseDefinition.Kind.NORMAL))
	assert(not AdventureStageCatalog.is_cleared(Global.global_game_state.adventure_state,
		AdventureStageCatalog.LAWN_ID, StagePhaseDefinition.Kind.NIGHTMARE))
	AdventureSession.abandon_battle()
	await _frames()
	assert(AdventureSession.active_level == null)
	print("PASS: first-clear key continuation, independent nightmare waves, boss events and strict settlement")
	get_tree().quit(0)
