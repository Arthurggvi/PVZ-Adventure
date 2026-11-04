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
	var phase: StagePhaseDefinition = find_phase(stage, kind)
	if phase == null:
		return "该战斗阶段不存在。"
	if inventory.list_cards().is_empty():
		return "当前玩家没有可出战植物卡。"
	if kind == StagePhaseDefinition.Kind.NIGHTMARE:
		if not is_cleared(state, stage.stage_id, StagePhaseDefinition.Kind.NORMAL):
			return "请先通关普通阶段。"
		if phase.boss_encounters.is_empty():
			return "噩梦阶段必须配置 Boss 遭遇。"
	elif kind != StagePhaseDefinition.Kind.NORMAL:
		return "该阶段类型尚未支持。"
	if phase.unlock_rule in [StagePhaseDefinition.UnlockRule.KEY,
			StagePhaseDefinition.UnlockRule.NORMAL_CLEARED_AND_KEY]:
		if inventory.get_item_count(str(phase.key_id)) < phase.key_count:
			return "缺少进入该阶段的钥匙。"
	for event: StageEventDefinition in phase.events:
		if event.trigger == StageEventDefinition.Trigger.BATTLE_END and event.action not in [
				StageEventDefinition.Action.REQUEST_DROP, StageEventDefinition.Action.SET_REGION_FLAG]:
			return "BATTLE_END 仅可发放奖励或更新地区状态。"
		if event.action not in [StageEventDefinition.Action.REQUEST_DROP,
				StageEventDefinition.Action.SET_REGION_FLAG, StageEventDefinition.Action.FINISH_BATTLE,
				StageEventDefinition.Action.SPAWN_ZOMBIES,
				StageEventDefinition.Action.BEGIN_BOSS_ENCOUNTER,
				StageEventDefinition.Action.PAUSE_NATURAL_WAVES,
				StageEventDefinition.Action.RESUME_NATURAL_WAVES,
				StageEventDefinition.Action.MODIFY_CARD_COOLDOWN]:
			return "该阶段存在未实装的事件动作。"
	var check_rng := RandomNumberGenerator.new()
	check_rng.seed = 1
	for band: WaveBandDefinition in phase.wave_profile.bands:
		var index: int = band.first_wave - 1
		var power: int = index / 3 + 1
		var is_flag_wave: bool = phase.wave_profile.is_flag_wave(band.first_wave) or band.first_wave == phase.wave_profile.wave_count
		var budget: int = (int(power * 2.5) if is_flag_wave else power) * stage.environment.zombie_power_multiplier
		if AdventureWavePlanner.build_plan(phase.wave_profile, band.first_wave,
				budget, 1, tier_threat_costs(), check_rng).is_empty():
			return "波段[%s]首波战力预算不足。" % band.band_id
	return ""

static func build_level(stage_number: int, kind: int) -> ResourceLevelData:
	var stage: StageDefinition = load_stage(stage_number)
	var phase: StagePhaseDefinition = find_phase(stage, kind)
	if stage == null or phase == null:
		return null
	return AdventureBattleEnvironmentAdapter.build(stage.environment, phase)
