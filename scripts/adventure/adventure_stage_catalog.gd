## 冒险关卡配置门面：地区默认值 + 单关覆盖，解锁/战斗/奖励统一使用阶段身份。
extends RefCounted
class_name AdventureStageCatalog

const REGION_ID := AdventureStageRegistry.REGION_ID
const LAWN_ID: StringName = &"zombie_island.lawn"
const BASE_TIER: StringName = &"base"

static func tier_ids() -> Array[StringName]:
	return AdventureZombieTierCatalog.tier_ids()

static func tier_threat_costs() -> Dictionary:
	return AdventureZombieTierCatalog.threat_costs()

static func key_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for stage_number: int in range(1, AdventureStageRegistry.SLUGS.size() + 1):
		var key: StringName = AdventureStageRegistry.key_id(stage_number)
		if ItemRegistry.has_item(str(key)):
			result.append(key)
	return result

static func load_stage(stage_number: int) -> StageDefinition:
	return AdventureStageRegistry.resolve(stage_number)

static func find_phase(stage: StageDefinition, kind: int) -> StagePhaseDefinition:
	if stage == null:
		return null
	for phase: StagePhaseDefinition in stage.phases:
		if phase != null and phase.kind == kind:
			return phase
	return null

static func is_cleared(state: AdventureState, stage_id: StringName, kind: int) -> bool:
	if state == null:
		return false
	var region: Dictionary = state.regions.get(REGION_ID, {})
	if stage_id == LAWN_ID and kind == StagePhaseDefinition.Kind.NORMAL:
		if region.get("stage_1_cleared", false) == true:
			return true
	var cleared: Dictionary = region.get("cleared_phases", {})
	return cleared.get(_clear_id(stage_id, kind), false) == true

static func mark_cleared(state: AdventureState, stage_id: StringName, kind: int) -> void:
	var region: Dictionary = state.regions.get(REGION_ID, {}).duplicate(true)
	var cleared: Dictionary = region.get("cleared_phases", {}).duplicate(true)
	cleared[_clear_id(stage_id, kind)] = true
	region["cleared_phases"] = cleared
	if stage_id == LAWN_ID and kind == StagePhaseDefinition.Kind.NORMAL:
		region["stage_1_cleared"] = true
	state.regions[REGION_ID] = region

static func _clear_id(stage_id: StringName, kind: int) -> String:
	var suffix := "normal" if kind == StagePhaseDefinition.Kind.NORMAL else "nightmare"
	return "%s/%s" % [stage_id, suffix]

static func is_unlocked(stage_number: int, state: AdventureState) -> bool:
	if AdventureStageRegistry.stage_id(stage_number) == &"":
		return false
	if stage_number == 1:
		return true
	return is_cleared(state, AdventureStageRegistry.previous_stage_id(stage_number),
		StagePhaseDefinition.Kind.NORMAL)

## 空字符串即允许进入。不可执行的事件或资源错误在这里拦截，不能静默退回原版。
static func entry_error(stage_number: int, kind: int, state: AdventureState,
		inventory: AdventureInventoryService) -> String:
	if state == null or inventory == null:
		return "玩家冒险数据未就绪。"
	if not is_unlocked(stage_number, state):
		return "请先通关上一关普通阶段。"
	var stage: StageDefinition = load_stage(stage_number)
	if stage == null:
		return "关卡配置不存在。"
	var issues: PackedStringArray = stage.validate(tier_ids(), key_ids())
	if not issues.is_empty():
		return "关卡配置无效：" + issues[0]
	var terrain_errors: PackedStringArray = AdventureBattleEnvironmentAdapter.validate_terrain(stage)
	if not terrain_errors.is_empty():
		return "关卡地形配置无效：" + terrain_errors[0]
	var phase: StagePhaseDefinition = find_phase(stage, kind)
	if phase == null:
		return "该战斗阶段不存在。"
	if inventory.list_cards().is_empty():
		return "当前玩家没有可出战植物卡。"
	if kind != StagePhaseDefinition.Kind.NORMAL:
		return "只能从普通阶段开始关卡；噩梦需要在本次普通阶段清场后继续。"
	# 普通入口必须同时验证后续噩梦配置，禁止玩家到达检查点后才发现非法阶段。
	for candidate: StagePhaseDefinition in stage.phases:
		var budget_errors: PackedStringArray = AdventureWavePlanner.validate_affordability(
			candidate.wave_profile, stage.environment.zombie_power_multiplier, tier_threat_costs())
		if not budget_errors.is_empty():
			return "阶段[%s]战力预算无效：%s" % [candidate.phase_id, budget_errors[0]]
	return ""

## 本次普通阶段成功落盘后才允许调用；不查询历史通关记录。
## 只有玩家当前库存中的钥匙决定是否出现继续挑战的选择。
static func continuation_error(stage: StageDefinition, inventory: AdventureInventoryService) -> String:
	if stage == null or inventory == null:
		return "关卡或库存数据未就绪。"
	if inventory.get_item_count(str(stage.nightmare_key_id)) < stage.nightmare_key_count:
		return "缺少本关的噩梦钥匙。"
	return ""

static func build_level(stage_number: int, kind: int) -> ResourceLevelData:
	var stage: StageDefinition = load_stage(stage_number)
	var phase: StagePhaseDefinition = find_phase(stage, kind)
	if stage == null or phase == null:
		return null
	return AdventureBattleEnvironmentAdapter.build(stage, phase)
