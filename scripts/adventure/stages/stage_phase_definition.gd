## 单个 normal/nightmare 阶段的静态契约；选卡和僵尸预览始终必需。
extends Resource
class_name StagePhaseDefinition

## 阶段身份必须显式指定，不由名字或数组位置推断。
enum Kind { UNSET, NORMAL, NIGHTMARE }
## 阶段只有战斗内容；钥匙/卡槽/预览属于整关入口契约。
@export var phase_id: StringName = &""
@export var kind: Kind = Kind.UNSET
## 本阶段无存活 Boss 时的战斗曲目；未配置时沿用关卡环境音乐。
@export var battle_music: AudioStream
## 本阶段存在存活 Boss 时的战斗曲目；未配置时沿用默认 Boss 音乐。
@export var boss_music: AudioStream
## 自然波次与分波段物种/等阶权重。
@export var wave_profile: WaveProfile
## 独立掉落表；此处只引用，不执行奖励。
@export var drop_table: DropTable
## 阶段首次达成指定条件时一次性奖励，与重复通关掉落独立。
@export var first_clear_coin: int = 0
@export var first_clear_items: Dictionary[StringName, int] = {}
## 噩梦 Boss 被击败才发放首通 Boss 奖励；逃跑仍可完成普通波次。
@export var first_clear_requires_boss_kill: bool = false
## 当前阶段的 Boss 遭遇元数据，可为空。
@export var boss_encounters: Array[BossEncounterDefinition] = []
## 当前阶段的事件元数据，可为空。
@export var events: Array[StageEventDefinition] = []

## 静态阶段校验只关心自身战斗资源，不查询玩家入口条件。
func validate(known_tier_ids: Array[StringName] = []) -> PackedStringArray:
	var errors := PackedStringArray()
	if str(phase_id).strip_edges().is_empty():
		errors.append("阶段缺少稳定 ID。")
	if kind not in [Kind.NORMAL, Kind.NIGHTMARE]:
		errors.append("阶段类型必须为 normal 或 nightmare。")
	var wave_count := 0 # 用于子资源的波次边界校验，缺配置仍继续收集其他错误。
	if wave_profile == null:
		errors.append("阶段缺少 WaveProfile。")
	else:
		wave_count = wave_profile.wave_count
		errors.append_array(wave_profile.validate(known_tier_ids))
	if drop_table == null:
		errors.append("阶段缺少独立 DropTable。")
	else:
		errors.append_array(drop_table.validate())
	if first_clear_coin < 0 or first_clear_coin > PlantCardInstance.MAX_JSON_INTEGER:
		errors.append("首通金币数量无效。")
	for item_id: StringName in first_clear_items:
		if not ItemRegistry.has_item(str(item_id)) or first_clear_items[item_id] < 1:
			errors.append("首通道具配置非法：" + str(item_id))
	if first_clear_requires_boss_kill and (kind != Kind.NIGHTMARE or boss_encounters.is_empty()):
		errors.append("首通击杀奖励需要噩梦 Boss。")
	var encounter_ids: Array[StringName] = [] # 先建立完整目录，允许事件引用列表中稍后的遭遇。
	for encounter: BossEncounterDefinition in boss_encounters: # 不实例化遭遇资源所描述的角色。
		if encounter == null:
			errors.append("阶段包含空 Boss 遭遇。")
			continue
		if encounter_ids.has(encounter.encounter_id):
			errors.append("Boss 遭遇 ID 重复：%s。" % encounter.encounter_id)
		encounter_ids.append(encounter.encounter_id)
		errors.append_array(encounter.validate(wave_count, known_tier_ids))
	var event_ids: Dictionary = {} # 事件 ID 以阶段为作用域。
	for event: StageEventDefinition in events: # 校验参数及引用，不调用事件动作。
		if event == null:
			errors.append("阶段包含空事件。")
			continue
		if event_ids.has(event.event_id):
			errors.append("阶段事件 ID 重复：%s。" % event.event_id)
		event_ids[event.event_id] = true
		errors.append_array(event.validate(wave_count, known_tier_ids, encounter_ids))
	# 每个强制遭遇都必须保证能启动；EVENT_ONLY 无固定的自然时间触发。
	# 可达事件限本阶段必经的开始/自然开波事件，拒绝依赖玩家动作或僵尸数量。
	for encounter: BossEncounterDefinition in boss_encounters:
		if encounter == null or encounter.timing != BossEncounterDefinition.Timing.EVENT_ONLY:
			continue
		var guaranteed := false
		for event: StageEventDefinition in events:
			if event != null and event.action == StageEventDefinition.Action.BEGIN_BOSS_ENCOUNTER \
					and event.action_target_id == encounter.encounter_id \
					and event.trigger in [StageEventDefinition.Trigger.BATTLE_START,
						StageEventDefinition.Trigger.WAVE_BEFORE, StageEventDefinition.Trigger.WAVE_STARTED]:
				guaranteed = true
		if not guaranteed:
			errors.append("EVENT_ONLY Boss 缺少必经时机的启动事件：" + str(encounter.encounter_id))
	return errors
