## 隔离用户：真实草坪 Boss 暂停自然波次、小怪持续召唤、明确撤退后恢复。
extends "res://tests/adventure/test_island_flow.gd"

func _run() -> void:
	assert(OS.get_user_data_dir().contains("p3-boss-test"))
	get_tree().change_scene_to_file("res://scenes/main/01StartMenuV8.tscn")
	await _frames()
	Global.save_service.stop_autosave()
	var username := "p3-boss-%d" % Time.get_ticks_usec()
	var user: User = get_tree().current_scene.user
	user.panel_create_new_user.line_edit.text = username
	user.panel_create_new_user.button_ok.pressed.emit()
	_select_user(username)
	await _enter_island_from_menu()
	await _frames()
	var map: Control = get_tree().current_scene
	map.canvas.get_node("Intro")._finish()
	await _frames()
	map._select_stage(1)
	await _wait_battle()
	var battle: MainGameManager = Global.main_game
	var waves: ZombieWaveManager = battle.zombie_manager.zombie_wave_manager
	var end_ms := Time.get_ticks_msec() + 30000
	while waves.curr_wave < 0 and Time.get_ticks_msec() < end_ms:
		await get_tree().process_frame
	assert(waves.curr_wave == 0)
	var cfg := BossEncounterDefinition.new()
	cfg.encounter_id = &"test_p3_encounter"
	cfg.boss_type = CharacterRegistry.ZombieBossType.ZB001Doctor
	cfg.timing = BossEncounterDefinition.Timing.EVENT_ONLY
	cfg.natural_waves = BossEncounterDefinition.NaturalWaves.PAUSE_UNTIL_BOSS_EXIT
	cfg.summon_rule = BossEncounterDefinition.SummonRule.PERIODIC
	cfg.summon_while_paused = BossEncounterDefinition.SummonWhilePaused.CONTINUE
	cfg.summon_end = BossEncounterDefinition.SummonEnd.BOSS_EXIT
	cfg.summon_interval_seconds = 1.2
	cfg.summon_count = 2
	cfg.max_alive_summons = 5
	cfg.summon_zombie_weights[CharacterRegistry.ZombieType.Z001Norm] = 1
	cfg.summon_tier_weights[&"base"] = 1
	assert(cfg.validate(10, AdventureStageCatalog.tier_ids()).is_empty())
	var encounter := AdventureBossEncounter.new()
	battle.add_child(encounter)
	assert(encounter.begin(cfg, waves, battle.zombie_manager, AdventureStageCatalog.tier_ids()))
	assert(waves.is_advancement_suspended)
	assert(waves.every_wave_progress_timer.paused)
	assert(waves.zombie_wave_refresh_manager.wave_norm_refresh_timer.paused)
	assert(waves.zombie_wave_refresh_manager.wave_min_time_timer.paused)
	var before_wave := waves.curr_wave
	var natural_before := battle.zombie_manager.natural_refresh_zombie_count
	waves.start_next_wave()
	assert(waves.curr_wave == before_wave)
	await get_tree().create_timer(3.3).timeout
	assert(waves.is_advancement_suspended and waves.curr_wave == before_wave)
	assert(encounter._summons.size() >= 4) # 两次以上独立召唤，不是仅入场刷新一批。
	assert(encounter._summons.size() <= cfg.max_alive_summons)
	for ref: WeakRef in encounter._summons.values():
		var minion: Zombie000Base = ref.get_ref() as Zombie000Base
		assert(minion != null and minion.adventure_tier_id == &"base")
		assert(not minion.participates_natural_refresh)
		assert(minion.curr_wave == -1)
	var count_before_exit := encounter._summons.size()
	encounter.notify_escaped()
	assert(not waves.is_advancement_suspended and not encounter.active)
	await get_tree().create_timer(0.25).timeout
	assert(waves.curr_wave > before_wave)
	await get_tree().create_timer(1.6).timeout
	assert(encounter._summons.is_empty())
	assert(count_before_exit > 0)
	assert(not waves.every_wave_progress_timer.paused)
	assert(not waves.zombie_wave_refresh_manager.wave_norm_refresh_timer.paused)
	# 第二次遭遇使用真实 Boss 生命值归零来触发死亡分支。
	encounter.boss.queue_free()
	var defeated := AdventureBossEncounter.new()
	battle.add_child(defeated)
	assert(defeated.begin(cfg, waves, battle.zombie_manager, AdventureStageCatalog.tier_ids()))
	assert(waves.is_advancement_suspended)
	defeated.boss.hp_component.curr_hp = 0
	await _frames()
	assert(not defeated.active and not waves.is_advancement_suspended)
	print("PASS: boss pauses natural waves; multiple timed minion batches; escape and death both resume")
	get_tree().quit(0)
