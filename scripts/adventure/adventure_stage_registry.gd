## 僵尸岛唯一关卡身份目录。默认阶段资源属于地区配置，不逐关复制关卡脚本。
extends RefCounted
class_name AdventureStageRegistry

const REGION_ID := "zombie_island"
const SLUGS: Array[String] = [
	"lawn", "fallen_camp", "grave_upstream",
	"grave_downstream", "sewer", "edgar_temple"
]
const DEFAULT_PATH := "res://resources/adventure/stages/zombie_island_default.tres"
const OVERRIDE_ROOT := "res://resources/adventure/stages/"
const LEGACY_LAWN_PATH := "res://resources/adventure/stages/zombie_island_lawn.tres"
const PARTIAL_OVERRIDES := "res://resources/adventure/stages/overrides/"

static func stage_id(index: int) -> StringName:
	if index < 1 or index > SLUGS.size():
		return &""
	return StringName(REGION_ID + "." + SLUGS[index - 1])

static func key_id(index: int) -> StringName:
	if stage_id(index) == &"":
		return &""
	if index == 1:
		return &"lawn_nightmare_key" # 兼容已经发放的第一关钥匙及旧存档。
	return StringName(REGION_ID + "." + SLUGS[index - 1] + ".nightmare_key")

static func previous_stage_id(index: int) -> StringName:
	return stage_id(index - 1) if index > 1 else &""

static func display_name(index: int) -> String:
	const NAMES := ["草坪", "没落营地", "墓地上游", "墓地下游", "下水道", "埃德加神殿"]
	return NAMES[index - 1] if index >= 1 and index <= NAMES.size() else "未知关卡"

## 完整阶段资源覆盖优先于地区默认资源；只对默认对象注入身份和关联钥匙。
static func resolve(index: int) -> StageDefinition:
	var id: StringName = stage_id(index)
	if id == &"":
		return null
	var override_path: String = OVERRIDE_ROOT + REGION_ID + "_" + SLUGS[index - 1] + ".tres"
	if not ResourceLoader.exists(override_path):
		if index == 1 and ResourceLoader.exists(LEGACY_LAWN_PATH):
			override_path = LEGACY_LAWN_PATH
		else:
			override_path = ""
	if not override_path.is_empty():
		var override: StageDefinition = load(override_path) as StageDefinition
		if override == null or override.stage_id != id:
			push_error("关卡覆盖资源 ID 错误：" + override_path)
			return null
		return override.duplicate(true) as StageDefinition
	if not ResourceLoader.exists(DEFAULT_PATH):
		return null
	var base: StageDefinition = load(DEFAULT_PATH) as StageDefinition
	if base == null:
		return null
	var stage: StageDefinition = base.duplicate(true) as StageDefinition
	stage.stage_id = id
	for phase: StagePhaseDefinition in stage.phases:
		var suffix := "normal" if phase.kind == StagePhaseDefinition.Kind.NORMAL else "nightmare"
		phase.phase_id = StringName(str(id) + "." + suffix)
		phase.wave_profile.profile_id = StringName(str(phase.phase_id) + ".waves")
		phase.drop_table.table_id = StringName(str(phase.phase_id) + ".drops")
		for band: WaveBandDefinition in phase.wave_profile.bands:
			band.band_id = StringName(str(phase.phase_id) + ".wave_" + str(band.first_wave))
		if phase.kind == StagePhaseDefinition.Kind.NIGHTMARE:
			phase.unlock_rule = StagePhaseDefinition.UnlockRule.NORMAL_CLEARED_AND_KEY
			phase.key_id = key_id(index)
			phase.key_count = 1
			phase.key_use = StagePhaseDefinition.KeyUse.KEEP
		elif phase.kind == StagePhaseDefinition.Kind.NORMAL:
			phase.first_clear_items.erase(&"lawn_nightmare_key")
			phase.first_clear_items[key_id(index)] = 1
	var partial_path: String = PARTIAL_OVERRIDES + REGION_ID + "_" + SLUGS[index - 1] + ".tres"
	if ResourceLoader.exists(partial_path):
		var partial: AdventureStageOverride = load(partial_path) as AdventureStageOverride
		if partial == null or not partial.apply(stage):
			push_error("关卡覆盖资源无效：" + partial_path)
			return null
	return stage
