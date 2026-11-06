## 特殊事件的强类型静态契约；只验证触发条件与动作参数，不派发或执行。
extends Resource
class_name StageEventDefinition

## 明确区分波次准备前、开始后、清空后和阶段战斗起止；elapsed 为本阶段有效战斗累计秒数。
enum Trigger { UNSET, BATTLE_START, WAVE_BEFORE, WAVE_STARTED, WAVE_CLEARED, ELAPSED_TIME, ZOMBIE_COUNT, PLANT_PLACED, BOSS_HP_THRESHOLD, BOSS_EXITED, BATTLE_END }
## 阈值从不满足跨到满足时触发；重复策略不等于每帧执行。
enum Comparison { UNSET, LESS_OR_EQUAL, GREATER_OR_EQUAL }
## 每阶段一次或每次匹配触发，禁止隐式重复策略。
enum RepeatRule { UNSET, ONCE_PER_PHASE, EVERY_MATCH }
## 种植触发明确区分任意物种与指定物种。
enum PlantFilter { UNSET, ANY, SPECIFIC }
## Boss 离场原因过滤，不隐式把所有离场当死亡。
enum BossExitReason { UNSET, ANY, DEFEATED, ESCAPED }
## 动作仅是枚举与参数，P1-A 不提供任何执行器。
enum Action { UNSET = 0, SPAWN_ZOMBIES = 3, BEGIN_BOSS_ENCOUNTER = 4, REQUEST_DROP = 5, SET_REGION_FLAG = 6, FINISH_BATTLE = 7, MODIFY_CARD_COOLDOWN = 8 }
enum CooldownScope { UNSET, ALL_SELECTED, PLANT_TYPE }
enum CooldownOperation { UNSET, NEXT_USE_MULTIPLIER, ADJUST_REMAINING_SECONDS }
## 标记动作的布尔目标值必须显式选择。
enum FlagValue { UNSET, OFF, ON }
## 结束战斗动作的结果参数。
enum BattleResult { UNSET = 0, DEFEAT = 2 }
## 当前阶段内唯一的事件静态 ID。
@export var event_id: StringName = &""
## 强类型触发时机。
@export var trigger: Trigger = Trigger.UNSET
## 当前阶段内的执行排序元数据，非负整数，-1 为未配置。
@export var order: int = -1
## 显式重复规则。
@export var repeat_rule: RepeatRule = RepeatRule.UNSET
## 波次型触发使用的 1 起点波次。
@export var wave: int = 0
## elapsed 触发的阶段有效战斗秒数，-1 为未使用。
@export var elapsed_seconds: float = -1.0
## 僵尸数量阈值，-1 为未使用，0 可表示清空。
@export var zombie_count: int = -1
## 数量或 HP 阈值的跨越方向。
@export var comparison: Comparison = Comparison.UNSET
## 种植触发的物种过滤方式。
@export var plant_filter: PlantFilter = PlantFilter.UNSET
## SPECIFIC 种植触发专用物种。
@export var plant_type: CharacterRegistry.PlantType = CharacterRegistry.PlantType.Null
## HP/离场触发引用的阶段内 Boss 遭遇 ID。
@export var encounter_id: StringName = &""
## Boss HP 比例阈值 0–1，-1 为未使用。
@export var boss_hp_ratio: float = -1.0
## Boss 离场触发的原因过滤。
@export var boss_exit_reason: BossExitReason = BossExitReason.UNSET
## 不执行的动作枚举。
@export var action: Action = Action.UNSET
## 遭遇或地区标记动作的静态目标 ID。
@export var action_target_id: StringName = &""
## 普通僵尸生成动作的物种参数，不使用 Boss 类型。
@export var action_zombie_type: CharacterRegistry.ZombieType = CharacterRegistry.ZombieType.Null
## 生成动作引用的已定义等阶。
@export var action_tier_id: StringName = &""
## 生成动作的正数量参数。
@export var action_count: int = 0
## 请求掉落动作使用的独立静态表，不在校验期间结算。
@export var action_drop_table: DropTable
## 设置地区标记动作的显式值。
@export var action_flag_value: FlagValue = FlagValue.UNSET
## 结束战斗动作的显式结果。
@export var action_battle_result: BattleResult = BattleResult.UNSET
## 作用目标为全部出战卡或指定植物物种。
@export var cooldown_scope: CooldownScope = CooldownScope.UNSET
@export var cooldown_plant_type: CharacterRegistry.PlantType = CharacterRegistry.PlantType.Null
## 后续冷却倍率和当下剩余冷却秒数必须区别处理。
@export var cooldown_operation: CooldownOperation = CooldownOperation.UNSET
@export var cooldown_value: float = 0.0
@export var cooldown_duration_seconds: float = 0.0

## [param wave_count] 是阶段总波数；[param known_tier_ids]、[param encounter_ids] 是显式引用目录。
func validate(wave_count: int = 0, known_tier_ids: Array[StringName] = [], encounter_ids: Array[StringName] = []) -> PackedStringArray:
	var errors := PackedStringArray() # 返回校验结果，不执行任何动作。
	if str(event_id).strip_edges().is_empty() or order < 0:
		errors.append("事件必须指定稳定 ID 与非负排序。")
	if trigger == Trigger.UNSET or not Trigger.values().has(trigger):
		errors.append("事件触发时机未配置或无效。")
	if repeat_rule == RepeatRule.UNSET or not RepeatRule.values().has(repeat_rule):
		errors.append("事件重复规则未配置或无效。")
	if trigger in [Trigger.WAVE_BEFORE, Trigger.WAVE_STARTED, Trigger.WAVE_CLEARED]:
		if wave < 1 or wave > wave_count:
			errors.append("事件波次越界。")
	elif wave != 0:
		errors.append("非波次事件不能填写 wave。")
	if trigger == Trigger.ELAPSED_TIME:
		if not is_finite(elapsed_seconds) or elapsed_seconds < 0.0:
			errors.append("事件累计秒数无效。")
	elif elapsed_seconds != -1.0:
		errors.append("非 elapsed 事件不能填写累计秒数。")
	if trigger == Trigger.ZOMBIE_COUNT:
		if zombie_count < 0:
			errors.append("僵尸数量阈值必须非负。")
	elif zombie_count != -1:
		errors.append("非数量事件不能填写 zombie_count。")
	if trigger in [Trigger.ZOMBIE_COUNT, Trigger.BOSS_HP_THRESHOLD]:
		if comparison not in [Comparison.LESS_OR_EQUAL, Comparison.GREATER_OR_EQUAL]:
			errors.append("阈值事件必须显式指定跨越方向。")
	elif comparison != Comparison.UNSET:
		errors.append("非阈值事件不能填写跨越方向。")
	if trigger == Trigger.PLANT_PLACED:
		if plant_filter not in [PlantFilter.ANY, PlantFilter.SPECIFIC]:
			errors.append("种植事件必须显式指定物种过滤方式。")
		if plant_filter == PlantFilter.SPECIFIC and (plant_type == CharacterRegistry.PlantType.Null or not CharacterRegistry.PlantType.values().has(plant_type)):
			errors.append("种植事件引用了非法物种。")
	elif plant_filter != PlantFilter.UNSET:
		errors.append("非种植事件不能填写物种过滤方式。")
	if (trigger != Trigger.PLANT_PLACED or plant_filter != PlantFilter.SPECIFIC) and plant_type != CharacterRegistry.PlantType.Null:
		errors.append("非指定物种事件不能填写 plant_type。")
	if trigger in [Trigger.BOSS_HP_THRESHOLD, Trigger.BOSS_EXITED]:
		if not encounter_ids.has(encounter_id):
			errors.append("事件引用了不存在的 Boss 遭遇。")
	elif encounter_id != &"":
		errors.append("非 Boss 触发不能填写遭遇 ID。")
	if trigger == Trigger.BOSS_HP_THRESHOLD:
		if not is_finite(boss_hp_ratio) or boss_hp_ratio < 0.0 or boss_hp_ratio > 1.0:
			errors.append("Boss HP 阈值必须在 0–1 之间。")
	elif boss_hp_ratio != -1.0:
		errors.append("非 HP 阈值事件不能填写 HP 比例。")
	if trigger == Trigger.BOSS_EXITED:
		if boss_exit_reason not in [BossExitReason.ANY, BossExitReason.DEFEATED, BossExitReason.ESCAPED]:
			errors.append("Boss 离场事件必须显式指定原因过滤。")
	elif boss_exit_reason != BossExitReason.UNSET:
		errors.append("非 Boss 离场事件不能填写离场原因。")
	# 终局事件发生在胜负已确定、资产结算尚未落盘之间；只能写结算账本。
	if trigger == Trigger.BATTLE_END and action not in [Action.REQUEST_DROP, Action.SET_REGION_FLAG]:
		errors.append("BATTLE_END 只允许写入掉落或地区标记，不能重启/修改战斗。")
	errors.append_array(_validate_action(known_tier_ids, encounter_ids))
	return errors

## 校验动作参数与 [param known_tier_ids]、[param encounter_ids] 引用，不调用执行接口。
func _validate_action(known_tier_ids: Array[StringName], encounter_ids: Array[StringName]) -> PackedStringArray:
	var errors := PackedStringArray() # 强类型动作之间的参数不能混用。
	if action == Action.UNSET or not Action.values().has(action):
		errors.append("事件动作未配置或无效。")
	if action == Action.SPAWN_ZOMBIES:
		if action_zombie_type == CharacterRegistry.ZombieType.Null or not CharacterRegistry.ZombieType.values().has(action_zombie_type) \
			or str(action_tier_id).strip_edges().is_empty() or not known_tier_ids.has(action_tier_id) or action_count < 1:
			errors.append("生成动作的普通僵尸、等阶或数量参数无效。")
	elif action_zombie_type != CharacterRegistry.ZombieType.Null or action_tier_id != &"" or action_count != 0:
		errors.append("非生成动作不能残留僵尸生成参数。")
	if action == Action.BEGIN_BOSS_ENCOUNTER:
		if not encounter_ids.has(action_target_id):
			errors.append("遭遇动作引用了不存在的 Boss 遭遇。")
	elif action == Action.SET_REGION_FLAG:
		if str(action_target_id).strip_edges().is_empty():
			errors.append("标记动作缺少静态标记 ID。")
	elif action_target_id != &"":
		errors.append("此动作不接受目标 ID。")
	if action == Action.REQUEST_DROP:
		if action_drop_table == null:
			errors.append("掉落动作缺少静态 DropTable。")
		else:
			errors.append_array(action_drop_table.validate())
	elif action_drop_table != null:
		errors.append("非掉落动作不能引用 DropTable。")
	if action == Action.SET_REGION_FLAG:
		if action_flag_value not in [FlagValue.OFF, FlagValue.ON]:
			errors.append("标记动作必须显式指定目标值。")
	elif action_flag_value != FlagValue.UNSET:
		errors.append("非标记动作不能填写标记值。")
	if action == Action.FINISH_BATTLE:
		if action_battle_result != BattleResult.DEFEAT:
			errors.append("事件只能显式触发失败；阶段胜利由真实末波和 Boss 结果判定。")
	elif action_battle_result != BattleResult.UNSET:
		errors.append("非结束动作不能填写战斗结果。")
	if action == Action.MODIFY_CARD_COOLDOWN:
		if cooldown_scope not in [CooldownScope.ALL_SELECTED, CooldownScope.PLANT_TYPE]:
			errors.append("冷却事件必须显式选择全部出战卡或特定物种。")
		if cooldown_scope == CooldownScope.PLANT_TYPE:
			if cooldown_plant_type == CharacterRegistry.PlantType.Null or not CharacterRegistry.PlantType.values().has(cooldown_plant_type):
				errors.append("冷却事件引用了非法物种。")
		elif cooldown_plant_type != CharacterRegistry.PlantType.Null:
			errors.append("全卡冷却事件不得指定单一物种。")
		if not is_finite(cooldown_value):
			errors.append("冷却事件值必须有限。")
		elif cooldown_operation == CooldownOperation.NEXT_USE_MULTIPLIER:
			if cooldown_value <= 0 or not is_finite(cooldown_duration_seconds) or cooldown_duration_seconds <= 0:
				errors.append("后续冷却倍率和持续秒数必须为正数。")
		elif cooldown_operation == CooldownOperation.ADJUST_REMAINING_SECONDS:
			if is_zero_approx(cooldown_value) or cooldown_duration_seconds != 0:
				errors.append("当前剩余冷却调整不能为零或包含持续时间。")
		else:
			errors.append("冷却事件必须指定效果类型。")
	elif cooldown_scope != CooldownScope.UNSET or cooldown_plant_type != CharacterRegistry.PlantType.Null 		or cooldown_operation != CooldownOperation.UNSET or cooldown_value != 0.0 or cooldown_duration_seconds != 0.0:
		errors.append("非冷却事件不能残留冷却参数。")
	return errors
