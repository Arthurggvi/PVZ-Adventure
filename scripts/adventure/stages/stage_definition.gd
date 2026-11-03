## 一关恰好包含 normal/nightmare 两阶段，只保存 Resource 配置与静态引用。
extends Resource
class_name StageDefinition

## 关卡稳定 ID，不使用场景文件名、列表下标或展示文本替代。
@export var stage_id: StringName = &""
## 复用原版地形/环境/战斗参数模板，阶段只注入自己的动态规则。
@export var battle_template: ResourceLevelData
## 两个独立阶段资源，身份与锁在阶段内显式配置.
@export var phases: Array[StagePhaseDefinition] = []

## [param known_tier_ids]、[param known_key_ids] 为已存在定义的 ID 集合；不读取进度或执行解锁。
func validate(known_tier_ids: Array[StringName] = [], known_key_ids: Array[StringName] = []) -> PackedStringArray:
	var errors := PackedStringArray() # 汇总所有静态错误，不自动修复或变更配置。
	if str(stage_id).strip_edges().is_empty():
		errors.append("关卡缺少稳定 ID。")
	if battle_template == null:
		errors.append("关卡缺少原版战斗模板。")
	else:
		errors.append_array(AdventureLevelTemplateAdapter.validate(battle_template))
	if phases.size() != 2:
		errors.append("一关必须恰好包含 normal 和 nightmare 两个阶段。")
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
		errors.append_array(phase.validate(known_tier_ids, known_key_ids))
	if not kinds.has(StagePhaseDefinition.Kind.NORMAL) or not kinds.has(StagePhaseDefinition.Kind.NIGHTMARE):
		errors.append("关卡必须分别声明 normal 与 nightmare。")
	return errors
