## 僵尸岛关卡静态目录、阶段进入约束与原版波次模板适配。
## P2 波段与物种权重由 AdventureWavePlanner 执行；等阶强度规则未冻结前只开放基础等阶。
extends RefCounted
class_name AdventureStageCatalog

const REGION_ID := "zombie_island"
const BASE_TIER: StringName = &"base"
const LAWN_ID: StringName = &"zombie_island.lawn"
const LAWN_PATH := "res://resources/adventure/stages/zombie_island_lawn.tres"
const LAWN_NIGHTMARE_KEY := "lawn_nightmare_key"

static func tier_ids() -> Array[StringName]:
	return [BASE_TIER]

static func tier_threat_costs() -> Dictionary:
	return {BASE_TIER: 1.0}

static func key_ids() -> Array[StringName]:
	var keys: Array[StringName] = []
	if ItemRegistry.has_item(LAWN_NIGHTMARE_KEY):
		keys.append(&"lawn_nightmare_key")
	return keys

static func load_stage(stage_number: int) -> StageDefinition:
	if stage_number != 1 or not ResourceLoader.exists(LAWN_PATH, "Resource"):
		return null
	return ResourceLoader.load(LAWN_PATH) as StageDefinition

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
	if stage_id == LAWN_ID and kind == StagePhaseDefinition.Kind.NORMAL and region.get("stage_1_cleared", false) == true:
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

## 空字符串表示可进入；所有未实现模式明确拒绝，不能静默退回原版规则。
static func entry_error(stage_number: int, kind: int, state: AdventureState, inventory: AdventureInventoryService) -> String:
	if state == null or inventory == null:
		return "玩家冒险数据未就绪。"
	var stage: StageDefinition = load_stage(stage_number)
	if stage == null:
		return "该关卡尚未配置战斗。"
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
		if inventory.get_item_count(str(phase.key_id)) < phase.key_count:
			return "缺少进入噩梦阶段的钥匙。"
		if phase.key_use == StagePhaseDefinition.KeyUse.CONSUME:
			return "消耗式钥匙入口尚未接入。"
		if phase.boss_encounters.is_empty():
			return "噩梦阶段必须配置 Boss 遭遇。"
	if kind not in [StagePhaseDefinition.Kind.NORMAL, StagePhaseDefinition.Kind.NIGHTMARE]:
		return "该阶段类型尚未支持。"
	for event: StageEventDefinition in phase.events:
		if event.trigger == StageEventDefinition.Trigger.BATTLE_END:
			return "该阶段存在未实装的事件触发时机。"
		if event.action not in [StageEventDefinition.Action.SPAWN_ZOMBIES,
				StageEventDefinition.Action.BEGIN_BOSS_ENCOUNTER,
				StageEventDefinition.Action.PAUSE_NATURAL_WAVES,
				StageEventDefinition.Action.RESUME_NATURAL_WAVES,
				StageEventDefinition.Action.MODIFY_CARD_COOLDOWN]:
			return "该阶段存在未实装的事件动作。"
	var check_rng := RandomNumberGenerator.new()
	check_rng.seed = 1
	for band: WaveBandDefinition in phase.wave_profile.bands:
		for tier_id: StringName in band.tier_weights:
			if tier_id != BASE_TIER and band.tier_weights[tier_id] > 0:
				return "高级僵尸等阶尚未接入。"
		var wave_index: int = band.first_wave - 1
		var base_power: int = wave_index / 3 + 1
		var is_flag_wave: bool = wave_index % 10 == 9
		var budget: int = (int(base_power * 2.5) if is_flag_wave else base_power) * stage.battle_template.zombie_multy
		if AdventureWavePlanner.build_plan(phase.wave_profile, band.first_wave,
				budget, 1, tier_threat_costs(), check_rng).is_empty():
			return "波段[%s]首波的战力预算不足以生成配置中的僵尸。" % band.band_id
	return ""

static func build_level(stage_number: int, kind: int) -> ResourceLevelData:
	var stage: StageDefinition = load_stage(stage_number)
	var phase: StagePhaseDefinition = find_phase(stage, kind)
	if phase == null:
		return null
	var level: ResourceLevelData = AdventureLevelTemplateAdapter.build(stage.battle_template, phase.max_selected_cards)
	if level == null:
		return null
	level.max_wave = phase.wave_profile.wave_count
	level.zombie_refresh_types.clear()
	for band: WaveBandDefinition in phase.wave_profile.bands:
		for zombie_type: int in band.zombie_weights:
			if band.zombie_weights[zombie_type] > 0 and not level.zombie_refresh_types.has(zombie_type):
				level.zombie_refresh_types.append(zombie_type as CharacterRegistry.ZombieType)
	if level.zombie_refresh_types.is_empty():
		return null
	return level
