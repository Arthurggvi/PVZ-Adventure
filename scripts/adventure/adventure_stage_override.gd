## 仅声明单关特有差异；未设置的字段继承地区默认关卡。
## 这是内容覆盖资源，不创建新战斗流程，也不保存玩家数据。
extends Resource
class_name AdventureStageOverride

@export var environment: AdventureBattleEnvironment
## 单关美术差异，不覆盖地区默认环境玩法配置。
@export var battle_background_texture: Texture2D
## -1 继承、0 关闭、1 开启降雨；避免影响地区共享默认配置。
@export var rain_override: int = -1
## 当前关卡专用镜头预设；空值沿用地区默认值。
@export var weather_lens_profile: WeatherLensProfile
## -1 inherit, 0 false, 1 true; independent sky sun and mushroom sleep.
@export var daytime_override: int = -1
@export var daytime_sun_override: int = -1
@export var normal_gravestone_rules: GravestoneWaveRules
@export var nightmare_gravestone_rules: GravestoneWaveRules
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
	if battle_background_texture != null and stage.environment != null:
		stage.environment.background_texture = battle_background_texture
	if stage.environment != null:
		if rain_override != -1:
			stage.environment.rain = rain_override == 1
		if weather_lens_profile != null:
			stage.environment.weather_lens_profile = weather_lens_profile
		if daytime_override != -1:
			stage.environment.daytime = daytime_override == 1
		if daytime_sun_override != -1:
			stage.environment.daytime_sun = daytime_sun_override == 1
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
