## AdventureStage 运行规则与旧 PVZ 战斗内核的唯一协议转换。
## 新建 ResourceLevelData，不复制任何原版关卡/存档/胜负配置。
extends RefCounted
class_name AdventureBattleEnvironmentAdapter

static func build(stage: StageDefinition, phase: StagePhaseDefinition) -> ResourceLevelData:
	if stage == null or stage.environment == null or phase == null or phase.wave_profile == null:
		return null
	var env: AdventureBattleEnvironment = stage.environment
	if not env.validate().is_empty() or not CardSlotRules.is_valid_capacity(stage.max_selected_cards):
		return null
	var level := ResourceLevelData.new()
	level.game_sences = env.scene
	level.game_BG = env.background
	level.battle_background_texture = env.background_texture
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
	level.max_choosed_card_num = stage.max_selected_cards
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

## 原版 ResourceLevelData 只作为适配投影；阶段内容的唯一权威仍是 Session.active_phase。
## 噩梦切换时同步所有遗留读取者所需的阶段投影，不为其再建第二份阶段状态。
static func project_phase(level: ResourceLevelData, phase: StagePhaseDefinition) -> void:
	assert(level != null and phase != null and phase.wave_profile != null)
	level.max_wave = phase.wave_profile.wave_count
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
	var terrain: CharacterRegistry.ZombieRowType = Global.main_scene_registry.ZombieRowTypewithMainScenesMap[scene]
	var rows: Array[CharacterRegistry.ZombieRowType] = [] # 仅在关卡确实指定行时读取实际布局。
	for phase: StagePhaseDefinition in stage.phases:
		if phase == null or phase.wave_profile == null:
			continue
		for zombie_type: CharacterRegistry.ZombieType in preview_zombies(phase):
			if not Global.character_registry.ZombieInfo.has(zombie_type):
				errors.append("阶段 %s 未注册的僵尸类型 %s。" % [phase.phase_id, zombie_type])
				continue
			var zombie_terrain: CharacterRegistry.ZombieRowType = Global.character_registry.ZombieInfo[zombie_type][CharacterRegistry.ZombieInfoAttribute.ZombieRowType]
			if not ZombieRow.supports_spawn(zombie_terrain, terrain):
				errors.append("阶段 %s 僵尸 %s 与地图地形不兼容。" % [phase.phase_id, zombie_type])
		for group: WaveSpawnGroup in phase.wave_profile.scheduled_spawns: # 随机选行的组只需上面的场景地形校验。
			if group == null or group.row <= 0:
				continue
			if rows.is_empty():
				rows = _read_spawn_rows(scene)
				if rows.is_empty():
					errors.append("无法读取预排出怪所需的地图行。")
					return errors
			if group.row > rows.size():
				errors.append("阶段 %s 第%d波的预排出怪行号 %d 超出地图范围。" % [phase.phase_id, group.wave, group.row])
				continue
			for zombie_type: CharacterRegistry.ZombieType in group.zombie_weights: # 检查固定行的每个正权重候选。
				if group.zombie_weights[zombie_type] <= 0 or not Global.character_registry.ZombieInfo.has(zombie_type):
					continue
				var spawn_type: CharacterRegistry.ZombieRowType = Global.character_registry.get_zombie_info(
					zombie_type, CharacterRegistry.ZombieInfoAttribute.ZombieRowType) # 注册表中的水陆要求。
				if not ZombieRow.supports_spawn(spawn_type, rows[group.row - 1]):
					errors.append("阶段 %s 第%d波的僵尸 %s 无法生成在第%d行。" % [phase.phase_id, group.wave, zombie_type, group.row])
	return errors

## 按战场的节点顺序读取 [param scene] 的行地形；临时实例不入树，因此不会启动战斗。
static func _read_spawn_rows(scene: MainSceneRegistry.MainScenes) -> Array[CharacterRegistry.ZombieRowType]:
	var rows: Array[CharacterRegistry.ZombieRowType] = [] # 无有效行返回空数组。
	var path: String = Global.main_scene_registry.MainScenesMap.get(scene, "") # 场景注册表中的战场资源。
	if path.is_empty():
		return rows
	var packed: PackedScene = load(path) as PackedScene # 实际战场布局，包含继承的行配置。
	if packed == null or not packed.can_instantiate():
		return rows
	var battle: Node = packed.instantiate() # 离树检查，不触发战场节点的 _ready。
	var root: Node = battle.get_node_or_null(^"ZombiesRoot") # 与运行时使用同一行容器。
	if root != null:
		for child: Node in root.get_children(): # 行序与战场运行时一致。
			var row: ZombieRow = child as ZombieRow # 非行节点表示场景布局无效。
			if row == null or not row.has_node(^"ZombieCreatePosition"):
				rows.clear()
				break
			rows.append(row.zombie_row_type)
	battle.free()
	return rows
