## 一关包含普通、噩梦与可选终末阶段，只保存资源配置与静态引用。
extends Resource
class_name StageDefinition

## 冒险初始卡槽容量，关卡资源可显式覆盖。
const DEFAULT_CARD_SLOTS: int = 6

## 关卡稳定 ID，不使用场景文件名、列表下标或展示文本替代。
@export var stage_id: StringName = &""
## 复用原版地形/环境/战斗参数模板，阶段只注入自己的动态规则。
@export var environment: AdventureBattleEnvironment
## 单次关卡入场统一选卡/预览；噩梦继承同一组卡和战场。
@export_range(CardSlotRules.MIN_CAPACITY, CardSlotRules.MAX_CAPACITY) var max_selected_cards: int = DEFAULT_CARD_SLOTS
## 唯一的噩梦续战钥匙规则：KEEP 不消耗，CONSUME 进入时扣除。
enum KeyUse { KEEP, CONSUME }
@export var nightmare_key_id: StringName = &""
@export_range(1, 99) var nightmare_key_count: int = 1
@export var nightmare_key_use: KeyUse = KeyUse.KEEP
## 可选终末阶段的消耗钥匙；每次从噩梦续战时扣除一把。
@export var terminal_key_id: StringName = &""
@export var phases: Array[StagePhaseDefinition] = []

## [param known_tier_ids]、[param known_key_ids] 为已存在定义的 ID 集合；不读取进度或执行解锁。
func validate(known_tier_ids: Array[StringName] = [], known_key_ids: Array[StringName] = []) -> PackedStringArray:
	var errors := PackedStringArray() # 汇总所有静态错误，不自动修复或变更配置。
	if str(stage_id).strip_edges().is_empty():
		errors.append("关卡缺少稳定 ID。")
	if environment == null:
		errors.append("关卡缺少冒险环境配置。")
	else:
		errors.append_array(environment.validate())
	if not CardSlotRules.is_valid_capacity(max_selected_cards):
		errors.append("整关初始选卡槽数必须为 %d 到 %d。" % [CardSlotRules.MIN_CAPACITY, CardSlotRules.MAX_CAPACITY])
	if not known_key_ids.has(nightmare_key_id) or nightmare_key_count < 1 \
			or nightmare_key_use not in [KeyUse.KEEP, KeyUse.CONSUME]:
		errors.append("整关噩梦续战钥匙配置无效。")
	var phase_ids: Dictionary = {} # 当前关卡内的唯一阶段 ID。
	var kinds: Dictionary = {} # 阶段类型不能重复，不能用两个 normal 代替两阶段。
	for phase: StagePhaseDefinition in phases: # 不依据数组顺序推断阶段类型。
		if phase == null:
			errors.append("关卡包含空阶段。")
			continue
		if phase_ids.has(phase.phase_id):
			errors.append("阶段 ID 重复：%s。" % phase.phase_id)
		phase_ids[phase.phase_id] = true
		if kinds.has(phase.kind):
			errors.append("阶段类型重复：%s。" % phase.kind)
		kinds[phase.kind] = true
		errors.append_array(phase.validate(known_tier_ids))
	if not kinds.has(StagePhaseDefinition.Kind.NORMAL) or not kinds.has(StagePhaseDefinition.Kind.NIGHTMARE):
		errors.append("关卡必须分别声明 normal 与 nightmare。")
	if kinds.has(StagePhaseDefinition.Kind.TERMINAL):
		if terminal_key_id == nightmare_key_id or not known_key_ids.has(terminal_key_id):
			errors.append("终末阶段必须配置独立的续战钥匙。")
	elif not terminal_key_id.is_empty():
		errors.append("终末续战钥匙必须对应终末阶段。")
	return errors
