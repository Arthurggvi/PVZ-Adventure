## 仅声明单关特有差异；未设置的字段继承地区默认关卡。
## 这是内容覆盖资源，不创建新战斗流程，也不保存玩家数据。
extends Resource
class_name AdventureStageOverride

@export var battle_template: ResourceLevelData
@export var normal_wave_profile: WaveProfile
@export var nightmare_wave_profile: WaveProfile
@export var normal_drop_table: DropTable
@export var nightmare_drop_table: DropTable
@export var replace_normal_events := false
@export var normal_events: Array[StageEventDefinition] = []
@export var replace_nightmare_events := false
@export var nightmare_events: Array[StageEventDefinition] = []
@export var replace_nightmare_bosses := false
@export var nightmare_bosses: Array[BossEncounterDefinition] = []
@export var normal_first_clear_coin: int = -1
@export var nightmare_first_clear_coin: int = -1

func apply(stage: StageDefinition) -> bool:
	if stage == null or normal_first_clear_coin < -1 or nightmare_first_clear_coin < -1:
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
	if battle_template != null:
		stage.battle_template = battle_template.duplicate(true) as ResourceLevelData
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
	if replace_nightmare_bosses:
		nightmare.boss_encounters = nightmare_bosses.duplicate(true)
	if normal_first_clear_coin >= 0:
		normal.first_clear_coin = normal_first_clear_coin
	if nightmare_first_clear_coin >= 0:
		nightmare.first_clear_coin = nightmare_first_clear_coin
	return true
