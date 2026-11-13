## 噩梦续战：用测试遭遇验证突袭、冷却修饰和 Boss 的独立援军实战。
extends "res://tests/adventure/test_island_flow.gd"

func _run() -> void:
	assert(OS.get_user_data_dir().contains("p3-nightmare-test"))
	get_tree().change_scene_to_file("res://scenes/main/01StartMenuCoastal.tscn")
	await _frames()
	Global.save_service.stop_autosave()
	var username := "p3-nightmare-%d" % Time.get_ticks_usec()
	var user: User = _profile_selector()
	user.panel_create_new_user.line_edit.text = username
	user.panel_create_new_user.button_ok.pressed.emit()
	_select_user(username)
	await _enter_island_from_menu()
	await _frames()
	var map: Control = get_tree().current_scene
	map.canvas.get_node("Intro")._finish()
	await _frames()
	assert(AdventureSession.progress.intro_completed)
	# 续战测试的钥匙由测试档预置，正式关卡奖励不发放。
	assert(Global.adventure_inventory.add_item("lawn_nightmare_key", 1))
	map._select_stage(1)
	_add_test_encounters()
	await _wait_battle()
	var battle: MainGameManager = Global.main_game
	assert(AdventureSession.active_phase_kind == StagePhaseDefinition.Kind.NORMAL)
	# 通过真实自然波次和清怪接口推进普通清场，再使用预置钥匙续战。
	Engine.time_scale = 6.0
	var normal_deadline: int = Time.get_ticks_msec() + 60000
	while AdventureSession.challenge_state == AdventureSession.ChallengeState.NORMAL_ACTIVE \
			and Time.get_ticks_msec() < normal_deadline:
		if battle.zombie_manager.curr_zombie_num > 0:
			battle.zombie_manager.death_all_zombie()
		await get_tree().create_timer(0.2, true, false, true).timeout
	assert(AdventureSession.challenge_state == AdventureSession.ChallengeState.NORMAL_COMPLETE)
	assert(Global.adventure_inventory.get_item_count("lawn_nightmare_key") == 1)
	assert(battle.adventure_continuation.dialog != null)
	Engine.time_scale = 1.0
	battle.adventure_continuation.dialog.confirmed.emit(1)
	await _frames()
	assert(AdventureSession.active_phase_kind == StagePhaseDefinition.Kind.NIGHTMARE)
	assert(AdventureSession.challenge_state == AdventureSession.ChallengeState.NIGHTMARE_ACTIVE)
	assert(Global.adventure_inventory.get_item_count("lawn_nightmare_key") == 0)
	var current_waves: ZombieWaveManager = battle.zombie_manager.zombie_wave_manager
	assert(battle.game_para.max_wave == current_waves.max_wave)
	var previous_wave: int = current_waves.curr_wave
	current_waves._on_refresh_requested(
		current_waves.zombie_wave_refresh_manager._refresh_generation - 1)
	assert(current_waves.curr_wave == previous_wave)
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
	waves.adventure_wave_started.emit(2)
	assert(zombies.curr_zombie_num >= count_before + 5)
	var cards: Array[Card] = battle.card_manager.card_slot_battle.curr_cards
	assert(cards.size() == 2)
	waves.adventure_wave_started.emit(3)
	assert(is_equal_approx(cards[0].adventure_cooldown_multiplier, 1.5))
	cards[0].card_cool()
	assert(is_equal_approx(cards[0]._cool_timer, cards[0].cool_time * 1.5))
	cards[0].set_card_cool_end()
	runtime._cooldown._elapsed += 21.0
	runtime._cooldown._process(0.0)
	assert(is_equal_approx(cards[0].adventure_cooldown_multiplier, 1.0))
	# 由真实波次推进到末波，Boss 必须在最后一波生成后才启动。
	assert(not AdventureSession.settle_victory())
	Engine.time_scale = 12.0
	var final_wave_deadline: int = Time.get_ticks_msec() + 70000
	while waves.curr_wave < waves.max_wave - 1 and Time.get_ticks_msec() < final_wave_deadline:
		if zombies.curr_zombie_num > 0:
			zombies.death_all_zombie()
		await get_tree().create_timer(0.15, true, false, true).timeout
	Engine.time_scale = 1.0
	assert(waves.curr_wave == waves.max_wave - 1)
	assert(zombies.is_end_wave)
	var encounter: AdventureBossEncounter = runtime.boss_runtime
	assert(encounter != null and encounter.active)
	assert(waves.is_advancement_suspended)
	var idle_deliveries: Array[int] = [0]
	runtime._boss_director.idle.connect(func() -> void:
		idle_deliveries[0] += 1)
	await get_tree().create_timer(5.8).timeout
	assert(waves.is_advancement_suspended)
	assert(encounter._summons.size() >= 2)
	# 仅针对本测试关闭援军计时，排除新一批援军和最后一只 Boss 离场的竞争。
	encounter.summon_timer.stop()
	zombies.death_all_zombie()
	await _frames()
	assert(zombies.curr_zombie_num == 1) # 剩余的唯一敌方登记是 Boss 本体。
	assert(not AdventureSession.can_accept_victory())
	var encounter_id: StringName = encounter.config.encounter_id
	encounter.notify_escaped()
	assert(idle_deliveries[0] == 1)
	var reward_deadline: int = Time.get_ticks_msec() + 30000
	while AdventureSession.challenge_state == AdventureSession.ChallengeState.NIGHTMARE_ACTIVE \
			and Time.get_ticks_msec() < reward_deadline:
		await get_tree().create_timer(0.1, true, false, true).timeout
	assert(AdventureSession.boss_exit_results[encounter_id] == StageEventDefinition.BossExitReason.ESCAPED)
	assert(AdventureSession.challenge_state == AdventureSession.ChallengeState.COMPLETE)
	assert(AdventureStageCatalog.is_cleared(Global.global_game_state.adventure_state,
		AdventureStageCatalog.LAWN_ID, StagePhaseDefinition.Kind.NORMAL))
	assert(AdventureStageCatalog.is_cleared(Global.global_game_state.adventure_state,
		AdventureStageCatalog.LAWN_ID, StagePhaseDefinition.Kind.NIGHTMARE))
	assert(battle._round_end_claimed and battle.main_game_progress == MainGameManager.E_MainGameProgress.GAME_OVER)
	battle.win_main_game()
	await _frames()
	assert(AdventureSession.active_level == null)
	print("PASS: real final wave, last Boss exits after natural clear, single idle signal and trophy")
	get_tree().quit(0)

## 草坪的正式配置没有 Boss 和特殊事件，本用例只给隔离会话添加原有回归场景。
func _add_test_encounters() -> void:
	var phase: StagePhaseDefinition = AdventureStageCatalog.find_phase(
		AdventureSession.active_stage, StagePhaseDefinition.Kind.NIGHTMARE) # 本局独立的噩梦资源。
	var boss_phase: StagePhaseDefinition = AdventureStageCatalog.find_phase(
		AdventureStageCatalog.load_stage(2), StagePhaseDefinition.Kind.NIGHTMARE) # 地区模板提供 Boss 召唤参数。
	var boss: BossEncounterDefinition = boss_phase.boss_encounters[0] # 将测试 Boss 配置在本局末波。
	boss.timing = BossEncounterDefinition.Timing.WAVE_STARTED
	boss.wave = phase.wave_profile.wave_count
	phase.boss_encounters.append(boss)
	var horde := StageEventDefinition.new() # 在第二波模拟原突袭事件。
	horde.event_id = &"fixture_horde"
	horde.trigger = StageEventDefinition.Trigger.WAVE_STARTED
	horde.order = 10
	horde.repeat_rule = StageEventDefinition.RepeatRule.ONCE_PER_PHASE
	horde.wave = 2
	horde.action = StageEventDefinition.Action.SPAWN_ZOMBIES
	horde.action_zombie_type = CharacterRegistry.ZombieType.Z001Norm
	horde.action_tier_id = &"base"
	horde.action_count = 5
	phase.events.append(horde)
	var fatigue := StageEventDefinition.new() # 在第三波模拟原冷却事件。
	fatigue.event_id = &"fixture_fatigue"
	fatigue.trigger = StageEventDefinition.Trigger.WAVE_STARTED
	fatigue.order = 20
	fatigue.repeat_rule = StageEventDefinition.RepeatRule.ONCE_PER_PHASE
	fatigue.wave = 3
	fatigue.action = StageEventDefinition.Action.MODIFY_CARD_COOLDOWN
	fatigue.cooldown_scope = StageEventDefinition.CooldownScope.ALL_SELECTED
	fatigue.cooldown_operation = StageEventDefinition.CooldownOperation.NEXT_USE_MULTIPLIER
	fatigue.cooldown_value = 1.5
	fatigue.cooldown_duration_seconds = 20.0
	phase.events.append(fatigue)
