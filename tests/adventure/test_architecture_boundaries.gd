## P0-P6 边界对抗：只使用隔离 user://，不进入战斗、原版关卡或真实玩家档案。
extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	assert(OS.get_user_data_dir().contains("architecture-boundary-test"))
	var invalid_names: Array[String] = [
		"", "..", ".hidden", "a/../b", "folder/other", "folder\\other",
		"CON", "LPT1", "foo.", "foo..bar", "a:b"
	]
	for invalid_name: String in invalid_names:
		assert(not UserManager.is_valid_user_name(invalid_name), "invalid username accepted: " + invalid_name)
	assert(UserManager.is_valid_user_name("唐吉诃德-01"))
	assert(not Global.save_service.is_current_profile_loaded() or not Global.user_manager.curr_user_name.is_empty())

	# 原版 ResourceLevelData 即使与冒险环境参数相同，也不得拥有冒险会话身份。
	var original: ResourceLevelData = load("res://resources/adventure/island_lawn.tres")
	assert(original != null)
	assert(not AdventureSession.owns_battle(original))
	assert(AdventureSession.get_active_wave_profile(original) == null)
	assert(AdventureSession.get_active_phase(original) == null)
	var stages: Array[StageDefinition] = []
	for index: int in range(1, 7):
		var stage: StageDefinition = AdventureStageCatalog.load_stage(index)
		assert(stage != null and stage.stage_id == AdventureStageRegistry.stage_id(index))
		assert(stage.validate(AdventureStageCatalog.tier_ids(), AdventureStageCatalog.key_ids()).is_empty())
		var normal: StagePhaseDefinition = AdventureStageCatalog.find_phase(stage, StagePhaseDefinition.Kind.NORMAL)
		var nightmare: StagePhaseDefinition = AdventureStageCatalog.find_phase(stage, StagePhaseDefinition.Kind.NIGHTMARE)
		assert(normal != null and nightmare != null)
		assert(stage.nightmare_key_id == AdventureStageRegistry.key_id(index))
		var level: ResourceLevelData = AdventureBattleEnvironmentAdapter.build(stage, normal)
		assert(level != null and level != original)
		assert(level.look_show_zombie and level.can_choosed_card)
		assert(level.card_mode == ConstLevelData.E_CardMode.Norm)
		assert(level.monster_mode == ConstLevelData.E_MonsterMode.Norm)
		assert(level.game_round == 1 and level.save_game_data_main_game == null)
		assert(level.boss_type == CharacterRegistry.ZombieBossType.Null)
		assert(not level.win_on_boss_death)
		assert(level.max_wave == normal.wave_profile.wave_count)
		assert(level.max_choosed_card_num == stage.max_selected_cards)
		assert(not AdventureSession.owns_battle(level))
		stages.append(stage)
	assert(stages[1].phases[0].phase_id != stages[2].phases[0].phase_id)
	assert(stages[1].phases[0].drop_table != stages[2].phases[0].drop_table)
	# P6 地图实际交互边界：第二关解锁后按钮必须能点击，不能遗留第一关专用门禁。
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://assets/adventure/zombie_island/layout.json"))
	var stage_button: TextureButton = (load("res://scripts/adventure/island_stage_button.gd") as GDScript).new()
	add_child(stage_button)
	stage_button.call("configure", layout["stages"][1], true, false, func(): pass)
	assert(not stage_button.disabled, "Unlocked stage 2 was blocked by legacy stage-1 gate")
	stage_button.queue_free()
	var default_path := "res://resources/adventure/stages/zombie_island_default.tres"
	var default_text: String = FileAccess.get_file_as_string(default_path)
	assert(not default_text.contains("battle_template ="))
	assert(not default_text.contains("ResourceLevelData"))

	# 七波冒险也必须生成可见的 3 面旗帜；原版十波仍使用旧布局。
	var progress_scene: PackedScene = load("res://scenes/ui/flag_progress_bar.tscn")
	var flag_bar: FlagProgressBar = progress_scene.instantiate() as FlagProgressBar
	add_child(flag_bar)
	var custom_waves := WaveProfile.new()
	custom_waves.wave_count = 7
	custom_waves.flag_waves = [3, 5]
	flag_bar.init_flag_from_adventure_profile(custom_waves)
	assert(flag_bar.flag_arr.size() == 3)
	var distance: float = flag_bar.start_flag - flag_bar.end_flag
	assert(is_equal_approx(flag_bar.flag_arr[0].position.x,
		flag_bar.start_flag - distance * 2.0 / 6.0))
	assert(is_equal_approx(flag_bar.flag_arr[2].position.x, flag_bar.end_flag))
	flag_bar.queue_free()
	var legacy_bar: FlagProgressBar = progress_scene.instantiate() as FlagProgressBar
	add_child(legacy_bar)
	legacy_bar.init_flag_from_wave(10)
	assert(legacy_bar.flag_arr.size() == 1)
	assert(is_equal_approx(legacy_bar.flag_arr[0].position.x, legacy_bar.end_flag))
	legacy_bar.queue_free()

	# 冒险物种不能被原版随机名单悄悄过滤；地形不相容必须在开战前拒绝。
	var adversarial_stage := StageDefinition.new() # 单阶段测试，避免其他阶段的布局和预排出怪影响地形断言。
	adversarial_stage.environment = AdventureBattleEnvironment.new()
	var adversarial_phase := StagePhaseDefinition.new() # 仅声明测例使用的随机池。
	adversarial_phase.kind = StagePhaseDefinition.Kind.NORMAL
	adversarial_phase.wave_profile = WaveProfile.new()
	adversarial_phase.wave_profile.wave_count = 2
	var adversarial_band := WaveBandDefinition.new() # 同一只水生僵尸分别在草坪和泳池验证。
	adversarial_phase.wave_profile.bands = [adversarial_band]
	adversarial_stage.phases = [adversarial_phase]
	adversarial_band.zombie_weights[CharacterRegistry.ZombieType.Z012Snorkle] = 1
	assert(not AdventureBattleEnvironmentAdapter.validate_terrain(adversarial_stage).is_empty())
	adversarial_stage.environment.scene = MainSceneRegistry.MainScenes.MainGameBack
	assert(AdventureBattleEnvironmentAdapter.validate_terrain(adversarial_stage).is_empty())
	adversarial_band.zombie_weights.clear()
	adversarial_band.zombie_weights[CharacterRegistry.ZombieType.Z011Duckytube] = 1
	var explicit_level: ResourceLevelData = AdventureBattleEnvironmentAdapter.build(
		adversarial_stage, adversarial_phase)
	assert(explicit_level.zombie_refresh_types.has(CharacterRegistry.ZombieType.Z011Duckytube))
	assert(explicit_level.init_para())
	assert(not explicit_level.zombie_refresh_types.has(CharacterRegistry.ZombieType.Z011Duckytube))
	explicit_level.zombie_refresh_types = AdventureBattleEnvironmentAdapter.preview_zombies(adversarial_phase)
	assert(explicit_level.zombie_refresh_types.has(CharacterRegistry.ZombieType.Z011Duckytube))

	# 构造非法静态掉落：未知 ID、类别错配、超大数量都应在入口前拒绝。
	var entry := DropEntryDefinition.new()
	entry.entry_id = &"adversarial_item"
	entry.rule = DropEntryDefinition.Rule.GUARANTEED
	entry.asset_kind = DropEntryDefinition.AssetKind.ITEM
	entry.asset_id = &"does_not_exist"
	entry.quantity_min = 1
	entry.quantity_max = 1
	assert(not entry.validate().is_empty())
	entry.asset_id = &"lawn_nightmare_key"
	assert(not entry.validate().is_empty())
	entry.asset_kind = DropEntryDefinition.AssetKind.KEY
	assert(entry.validate().is_empty())
	entry.quantity_max = PlantCardInstance.MAX_JSON_INTEGER + 1
	assert(not entry.validate().is_empty())

	# 仅使用隔离 user://，校验坏 JSON 不能当空档，待提交文件不影响正式档。
	var path := "user://architecture_boundary_20261104.json"
	for suffix: String in ["", ".bak", ".pending"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)
	var initial := {"value": 1, "items": ["A", "B"]}
	assert(SaveFileStore.write(path, initial))
	assert(int(SaveFileStore.read(path)["data"]["value"]) == 1)
	var pending := FileAccess.open(path + ".pending", FileAccess.WRITE)
	assert(pending != null)
	pending.store_string("{broken")
	pending.close()
	assert(int(SaveFileStore.read(path)["data"]["value"]) == 1)
	var second := {"value": 2, "items": ["C"]}
	assert(SaveFileStore.write(path, second))
	assert(int(SaveFileStore.read(path)["data"]["value"]) == 2)
	assert(int(SaveFileStore.read(path + ".bak")["data"]["value"]) == 1)
	for suffix: String in ["", ".bak", ".pending"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)
	print("PASS: P0-P6 isolation, six-stage schemas, legacy identity, invalid drops, user paths, safe saves")
	get_tree().quit(0)
