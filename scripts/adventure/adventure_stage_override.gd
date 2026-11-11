## 仅声明单关特有差异；未设置的字段继承地区默认关卡。
## 这是内容覆盖资源，不创建新战斗流程，也不保存玩家数据。
extends Resource
class_name AdventureStageOverride

@export var environment: AdventureBattleEnvironment
## 单关空间覆盖；定义自有地形，不能同时使用 terrain_rows_override。
@export var board_definition: BoardDefinition
## 单关美术差异，不覆盖地区默认环境玩法配置。
@export var battle_background_texture: Texture2D
## 单关水面表现覆盖，空值继承地区默认水面配置。
@export var water_surface_profile: WaterSurfaceProfile
## 单关逐行地形覆盖；空数组继承地区和战场默认布局。
@export var terrain_rows_override: Array[CharacterRegistry.ZombieRowType] = []
## 仅覆盖进入战斗时的静态默认雨势：-1 继承、0 关闭、1 开启；动态强度由阶段时间轴控制。
@export var rain_override: int = -1
## 当前关卡专用镜头预设；空值沿用地区默认值。
@export var weather_lens_profile: WeatherLensProfile
## -1 inherit, 0 false, 1 true; independent sky sun and mushroom sleep.
@export var daytime_override: int = -1
@export var daytime_sun_override: int = -1
@export var normal_gravestone_rules: GravestoneWaveRules
@export var nightmare_gravestone_rules: GravestoneWaveRules
## 普通阶段可选的天气时间轴，空值沿用当前天气。
@export var normal_weather_sequence: WeatherSequence
## 噩梦阶段可选的天气时间轴，空值沿用当前天气。
@export var nightmare_weather_sequence: WeatherSequence
@export var normal_wave_profile: WaveProfile
@export var nightmare_wave_profile: WaveProfile
@export var normal_drop_table: DropTable
@export var nightmare_drop_table: DropTable
@export var replace_normal_events := false
@export var normal_events: Array[StageEventDefinition] = []
@export var additional_normal_events: Array[StageEventDefinition] = []
@export var replace_nightmare_events := false
@export var nightmare_events: Array[StageEventDefinition] = []
@export var additional_nightmare_events: Array[StageEventDefinition] = []
@export var replace_nightmare_bosses := false
@export var nightmare_bosses: Array[BossEncounterDefinition] = []
## 单关音乐只覆盖对应阶段；留空时沿用地区默认曲目。
@export var normal_battle_music: AudioStream
@export var nightmare_battle_music: AudioStream
@export var nightmare_boss_music: AudioStream
@export var normal_first_clear_coin: int = -1
@export var nightmare_first_clear_coin: int = -1

func apply(stage: StageDefinition) -> bool:
	if stage == null or normal_first_clear_coin < -1 or nightmare_first_clear_coin < -1 \
			or daytime_override not in [-1, 0, 1] or daytime_sun_override not in [-1, 0, 1] \
			or rain_override not in [-1, 0, 1]:
		return false
	var normal: StagePhaseDefinition
	var nightmare: StagePhaseDefinition
	for phase: StagePhaseDefinition in stage.phases:
		if phase.kind == StagePhaseDefinition.Kind.NORMAL:
			normal = phase
		elif phase.kind == StagePhaseDefinition.Kind.NIGHTMARE:
			nightmare = phase
	if normal == null or nightmare == null:
		return false
	if environment != null:
		stage.environment = environment.duplicate(true) as AdventureBattleEnvironment
	if board_definition != null and stage.environment != null:
		if not terrain_rows_override.is_empty():
			return false
		stage.environment.board_definition = board_definition
		stage.environment.terrain_rows.clear()
	if battle_background_texture != null and stage.environment != null:
		stage.environment.background_texture = battle_background_texture
	if water_surface_profile != null and stage.environment != null:
		stage.environment.water_surface_profile = water_surface_profile
	if not terrain_rows_override.is_empty() and stage.environment != null:
		stage.environment.terrain_rows = terrain_rows_override.duplicate()
	if stage.environment != null:
		if rain_override != -1:
			stage.environment.rain = rain_override == 1
		if weather_lens_profile != null:
			stage.environment.weather_lens_profile = weather_lens_profile
		if daytime_override != -1:
			stage.environment.daytime = daytime_override == 1
		if daytime_sun_override != -1:
			stage.environment.daytime_sun = daytime_sun_override == 1
	if normal_weather_sequence != null:
		normal.weather_sequence = normal_weather_sequence.duplicate(true) as WeatherSequence
	if nightmare_weather_sequence != null:
		nightmare.weather_sequence = nightmare_weather_sequence.duplicate(true) as WeatherSequence
	if normal_gravestone_rules != null:
		normal.gravestone_rules = normal_gravestone_rules.duplicate(true) as GravestoneWaveRules
	if nightmare_gravestone_rules != null:
		nightmare.gravestone_rules = nightmare_gravestone_rules.duplicate(true) as GravestoneWaveRules
	if normal_wave_profile != null:
		normal.wave_profile = normal_wave_profile.duplicate(true) as WaveProfile
	if nightmare_wave_profile != null:
		nightmare.wave_profile = nightmare_wave_profile.duplicate(true) as WaveProfile
	if normal_drop_table != null:
		normal.drop_table = normal_drop_table.duplicate(true) as DropTable
	if nightmare_drop_table != null:
		nightmare.drop_table = nightmare_drop_table.duplicate(true) as DropTable
	if replace_normal_events:
		normal.events = normal_events.duplicate(true)
	if replace_nightmare_events:
		nightmare.events = nightmare_events.duplicate(true)
	if not additional_normal_events.is_empty():
		normal.events.append_array(additional_normal_events.duplicate(true))
	if not additional_nightmare_events.is_empty():
		nightmare.events.append_array(additional_nightmare_events.duplicate(true))
	if replace_nightmare_bosses:
		nightmare.boss_encounters = nightmare_bosses.duplicate(true)
		# 显式清空 Boss 时，首通奖励改为随阶段清场结算。
		if nightmare.boss_encounters.is_empty():
			nightmare.first_clear_requires_boss_kill = false
	if normal_battle_music != null:
		normal.battle_music = normal_battle_music
	if nightmare_battle_music != null:
		nightmare.battle_music = nightmare_battle_music
	if nightmare_boss_music != null:
		nightmare.boss_music = nightmare_boss_music
	if normal_first_clear_coin >= 0:
		normal.first_clear_coin = normal_first_clear_coin
	if nightmare_first_clear_coin >= 0:
		nightmare.first_clear_coin = nightmare_first_clear_coin
	return true
