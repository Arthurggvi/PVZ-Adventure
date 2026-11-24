## AdventureStage 运行规则与旧 PVZ 战斗内核的唯一协议转换。
## 新建 ResourceLevelData，不复制任何原版关卡/存档/胜负配置。
extends RefCounted
class_name AdventureBattleEnvironmentAdapter

static func build(stage: StageDefinition, phase: StagePhaseDefinition) -> ResourceLevelData:
	if stage == null or stage.environment == null or phase == null:
		return null
	if phase.wave_profile == null and phase.kind != StagePhaseDefinition.Kind.TERMINAL:
		return null
	var env: AdventureBattleEnvironment = stage.environment
	if not env.validate().is_empty() or not CardSlotRules.is_valid_capacity(stage.max_selected_cards):
		return null
	var level := ResourceLevelData.new()
	level.board_definition = env.board_definition
	level.accelerate_offscreen_zombies = env.accelerate_offscreen_zombies
	level.game_sences = env.scene
	level.game_BG = env.background
	level.battle_background_texture = env.background_texture
	level.water_surface_profile = env.water_surface_profile
	level.terrain_rows = env.terrain_rows.duplicate()
	level.game_BGM = env.music
	level.battle_music_profile = env.battle_music_profile
	level.is_fog = env.fog
	level.is_rain = env.rain
	level.weather_lens_profile = env.weather_lens_profile
	level.is_day = env.daytime
	level.is_day_sun = env.daytime_sun
	level.is_lawn_mover = env.lawn_mowers
	level.is_zombie_can_home = env.zombie_can_reach_home
	level.start_sun = env.initial_sun
	level.zombie_multy = env.zombie_power_multiplier
	level.boss_spawn_position = env.boss_spawn_position
	level.is_shovel = env.shovel_enabled
	level.all_pre_plant_data = env.preplanted.duplicate(true)
	level.max_choosed_card_num = stage.max_selected_cards
	level.card_mode = ConstLevelData.E_CardMode.Norm
	level.look_show_zombie = true
	level.can_choosed_card = true
	level.game_round = 1
	level.win_on_boss_death = false
	level.boss_type = CharacterRegistry.ZombieBossType.Null
	level.boss_spawn_wave = 0
	level.prechosen_cards.clear()
	level.save_game_data_main_game = null
	project_phase(level, phase)
	if phase.kind == StagePhaseDefinition.Kind.TERMINAL:
		return level
	return level if level.max_wave >= 2 and not level.zombie_refresh_types.is_empty() else null

## 原版 ResourceLevelData 只作为适配投影；阶段内容的唯一权威仍是 Session.active_phase。
## 噩梦切换时同步所有遗留读取者所需的阶段投影，不为其再建第二份阶段状态。
static func project_phase(level: ResourceLevelData, phase: StagePhaseDefinition) -> void:
	assert(level != null and phase != null)
	if phase.board_definition != null:
		level.board_definition = phase.board_definition
	if phase.background_texture != null:
		level.battle_background_texture = phase.background_texture
	level.max_wave = phase.wave_profile.wave_count if phase.wave_profile != null else 0
	level.monster_mode = ConstLevelData.E_MonsterMode.Norm if phase.wave_profile != null else ConstLevelData.E_MonsterMode.Null
	level.zombie_refresh_types = preview_zombies(phase)

## 汇总 [param phase] 的随机池、预排出怪、Boss 援军和事件突袭，供预览与地形校验使用。
## 遍历顺序与去重语义由 AdventureStageRoster 维护，地图悬停预览复用同一份名单。
static func preview_zombies(phase: StagePhaseDefinition) -> Array[CharacterRegistry.ZombieType]:
	return AdventureStageRoster.zombie_types(phase)

## 校验 [param stage] 的物种和预排行能否在实际场景生成。
static func validate_terrain(stage: StageDefinition) -> PackedStringArray:
	var errors := PackedStringArray()
	if stage == null or stage.environment == null:
		errors.append("缺少冒险场景环境配置。")
		return errors
	var scene: MainSceneRegistry.MainScenes = stage.environment.scene
	if not Global.main_scene_registry.ZombieRowTypewithMainScenesMap.has(scene):
		errors.append("当前冒险场景不具备僵尸行类型。")
		return errors
	var rows: Array[CharacterRegistry.ZombieRowType] = stage.environment.terrain_rows.duplicate() # 单关地形优先
	if stage.environment.board_definition != null:
		var layout: BoardDefinition = stage.environment.board_definition # 关卡静态空间权威。
		errors.append_array(layout.validate())
		if not errors.is_empty():
			return errors
		rows.clear()
		for lane: BoardLaneDefinition in layout.lane_definitions(): # 显式攻击行无需匹配旧场景节点数。
			rows.append(lane.spawn_type)
	else:
		var scene_rows: Array[CharacterRegistry.ZombieRowType] = Global.main_scene_registry.get_legacy_spawn_rows(scene) # 原版静态行协议。
		if scene_rows.is_empty():
			errors.append("当前冒险场景缺少静态出怪行配置。")
			return errors
		if not rows.is_empty() and rows.size() != scene_rows.size():
			errors.append("冒险关卡自定义行数与战场场景不一致")
			return errors
		if rows.is_empty():
			rows = scene_rows
	var terrain: CharacterRegistry.ZombieRowType = ResourceLevelData.resolve_terrain_type(scene, rows)
	for phase: StagePhaseDefinition in stage.phases:
		if phase == null:
			continue
		var phase_rows: Array[CharacterRegistry.ZombieRowType] = rows.duplicate() # 每阶段独立校验水陆规则。
		if phase.board_definition != null:
			errors.append_array(phase.board_definition.validate())
			phase_rows.clear()
			for lane: BoardLaneDefinition in phase.board_definition.lane_definitions(): # 使用布局的出怪资格。
				phase_rows.append(lane.spawn_type)
		terrain = ResourceLevelData.resolve_terrain_type(scene, phase_rows)
		for zombie_type: CharacterRegistry.ZombieType in preview_zombies(phase):
			if not Global.character_registry.ZombieInfo.has(zombie_type):
				errors.append("阶段 %s 未注册的僵尸类型 %s。" % [phase.phase_id, zombie_type])
				continue
			var zombie_terrain: CharacterRegistry.ZombieRowType = Global.character_registry.ZombieInfo[zombie_type][CharacterRegistry.ZombieInfoAttribute.ZombieRowType]
			if not ZombieRow.supports_spawn(zombie_terrain, terrain):
				errors.append("阶段 %s 僵尸 %s 与地图地形不兼容。" % [phase.phase_id, zombie_type])
		if phase.wave_profile == null:
			continue
		for group: WaveSpawnGroup in phase.wave_profile.scheduled_spawns: # 随机选行的组只需上面的场景地形校验。
			if group == null or group.row <= 0:
				continue
			if group.row > phase_rows.size():
				errors.append("阶段 %s 第%d波的预排出怪行号 %d 超出地图范围。" % [phase.phase_id, group.wave, group.row])
				continue
			for zombie_type: CharacterRegistry.ZombieType in group.zombie_weights: # 检查固定行的每个正权重候选。
				if group.zombie_weights[zombie_type] <= 0 or not Global.character_registry.ZombieInfo.has(zombie_type):
					continue
				var spawn_type: CharacterRegistry.ZombieRowType = Global.character_registry.get_zombie_info(
					zombie_type, CharacterRegistry.ZombieInfoAttribute.ZombieRowType) # 注册表中的水陆要求。
				if not ZombieRow.supports_spawn(spawn_type, phase_rows[group.row - 1]):
					errors.append("阶段 %s 第%d波的僵尸 %s 无法生成在第%d行。" % [phase.phase_id, group.wave, zombie_type, group.row])
	return errors
