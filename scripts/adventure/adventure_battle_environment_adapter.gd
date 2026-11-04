## AdventureStage 运行规则与旧 PVZ 战斗内核的唯一协议转换。
## 新建 ResourceLevelData，不复制任何原版关卡/存档/胜负配置。
extends RefCounted
class_name AdventureBattleEnvironmentAdapter

static func build(env: AdventureBattleEnvironment,
		phase: StagePhaseDefinition) -> ResourceLevelData:
	if env == null or phase == null or phase.wave_profile == null:
		return null
	if not env.validate().is_empty() or phase.max_selected_cards < 1 or phase.max_selected_cards > 15:
		return null
	var level := ResourceLevelData.new()
	level.game_sences = env.scene
	level.game_BG = env.background
	level.game_BGM = env.music
	level.is_fog = env.fog
	level.is_rain = env.rain
	level.is_day = env.daytime
	level.is_day_sun = env.daytime_sun
	level.is_lawn_mover = env.lawn_mowers
	level.is_zombie_can_home = env.zombie_can_reach_home
	level.start_sun = env.initial_sun
	level.zombie_multy = env.zombie_power_multiplier
	level.boss_spawn_position = env.boss_spawn_position
	level.is_shovel = env.shovel_enabled
	level.all_pre_plant_data = env.preplanted.duplicate(true)
	level.max_wave = phase.wave_profile.wave_count
	level.max_choosed_card_num = phase.max_selected_cards
	level.monster_mode = ConstLevelData.E_MonsterMode.Norm
	level.card_mode = ConstLevelData.E_CardMode.Norm
	level.look_show_zombie = true
	level.can_choosed_card = true
	level.game_round = 1
	level.win_on_boss_death = false
	level.boss_type = CharacterRegistry.ZombieBossType.Null
	level.boss_spawn_wave = 0
	level.prechosen_cards.clear()
	level.save_game_data_main_game = null
	level.zombie_refresh_types = preview_zombies(phase)
	return level if level.max_wave >= 2 and not level.zombie_refresh_types.is_empty() else null

## 完整冒险敌人预览：自然波、Boss 援军与事件突袭均由该阶段定义，不使用原版随机白名单。
static func preview_zombies(phase: StagePhaseDefinition) -> Array[CharacterRegistry.ZombieType]:
	var types: Array[CharacterRegistry.ZombieType] = []
	if phase == null or phase.wave_profile == null:
		return types
	for band: WaveBandDefinition in phase.wave_profile.bands:
		for zombie_type: CharacterRegistry.ZombieType in band.zombie_weights:
			if band.zombie_weights[zombie_type] > 0 and not types.has(zombie_type):
				types.append(zombie_type)
	for encounter: BossEncounterDefinition in phase.boss_encounters:
		for zombie_type: CharacterRegistry.ZombieType in encounter.summon_zombie_weights:
			if encounter.summon_zombie_weights[zombie_type] > 0 and not types.has(zombie_type):
				types.append(zombie_type)
	for event: StageEventDefinition in phase.events:
		if event.action == StageEventDefinition.Action.SPAWN_ZOMBIES and not types.has(event.action_zombie_type):
			types.append(event.action_zombie_type)
	return types

## 只拦截与场景行地形不相容的配置；显式冒险物种不受原版随机刷怪黑名单限制。
static func validate_terrain(stage: StageDefinition) -> PackedStringArray:
	var errors := PackedStringArray()
	if stage == null or stage.environment == null:
		errors.append("缺少冒险场景环境配置。")
		return errors
	var scene: MainSceneRegistry.MainScenes = stage.environment.scene
	if not Global.main_scene_registry.ZombieRowTypewithMainScenesMap.has(scene):
		errors.append("当前冒险场景不具备僵尸行类型。")
		return errors
	var terrain: CharacterRegistry.ZombieRowType = Global.main_scene_registry.ZombieRowTypewithMainScenesMap[scene]
	for phase: StagePhaseDefinition in stage.phases:
		for zombie_type: CharacterRegistry.ZombieType in preview_zombies(phase):
			if not Global.character_registry.ZombieInfo.has(zombie_type):
				errors.append("阶段 %s 未注册的僵尸类型 %s。" % [phase.phase_id, zombie_type])
				continue
			var zombie_terrain: CharacterRegistry.ZombieRowType = Global.character_registry.ZombieInfo[zombie_type][CharacterRegistry.ZombieInfoAttribute.ZombieRowType]
			if terrain != CharacterRegistry.ZombieRowType.Both and zombie_terrain != CharacterRegistry.ZombieRowType.Both and terrain != zombie_terrain:
				errors.append("阶段 %s 僵尸 %s 与地图地形不兼容。" % [phase.phase_id, zombie_type])
	return errors
