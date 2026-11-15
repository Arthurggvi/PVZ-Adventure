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

## 仅缓存已经合并的私有模板；对外始终给独立副本，避免本局或预览污染下一次请求。
static var _resolved_templates: Dictionary[int, StageDefinition] = {}

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

## 返回 [param index] 的独立关卡配置；同一地图访问内只读取并合并一次源资源。
## 缓存模板不对外发布，调用方可以继续安全地调整本局副本。
static func resolve(index: int) -> StageDefinition:
	if not _resolved_templates.has(index):
		var resolved: StageDefinition = _resolve_template(index) # 首次请求才解析完整覆盖或地区默认值。
		if resolved == null:
			return null
		_resolved_templates[index] = resolved
	return _resolved_templates[index].duplicate(true) as StageDefinition

## 显式丢弃解析缓存；[param index] 为零时清空全部关卡，否则仅刷新对应关卡。
## 已发布的本局副本保持有效，不会在战斗中被热更新修改。
static func invalidate_cache(index: int = 0) -> void:
	if index == 0:
		_resolved_templates.clear()
	else:
		_resolved_templates.erase(index)

## 开始一次地图访问；编辑器运行在重进地图时重读配置，发行包继续复用已解析模板。
static func begin_map_visit() -> void:
	if OS.has_feature("editor"):
		invalidate_cache()

## 解析 [param index] 的私有模板；完整覆盖优先，默认模板补齐身份与续战钥匙。
static func _resolve_template(index: int) -> StageDefinition:
	var id: StringName = stage_id(index) # 参数无效时不读取磁盘。
	if id == &"":
		return null
	var override_path: String = OVERRIDE_ROOT + REGION_ID + "_" + SLUGS[index - 1] + ".tres"
	if not ResourceLoader.exists(override_path):
		if index == 1 and ResourceLoader.exists(LEGACY_LAWN_PATH):
			override_path = LEGACY_LAWN_PATH
		else:
			override_path = ""
	if not override_path.is_empty():
		# 地图访问显式失效后重新读覆盖资源，保留编辑器重进地图刷新约定。
		var override: StageDefinition = ResourceLoader.load(
			override_path, "", ResourceLoader.CACHE_MODE_IGNORE) as StageDefinition
		if override == null or override.stage_id != id:
			push_error("关卡覆盖资源 ID 错误：" + override_path)
			return null
		return override
	if not ResourceLoader.exists(DEFAULT_PATH):
		return null
	var base: StageDefinition = load(DEFAULT_PATH) as StageDefinition
	if base == null:
		return null
	var stage: StageDefinition = base.duplicate(true) as StageDefinition
	stage.stage_id = id
	stage.nightmare_key_id = key_id(index)
	for phase: StagePhaseDefinition in stage.phases:
		var suffix := "normal" if phase.kind == StagePhaseDefinition.Kind.NORMAL else "nightmare"
		phase.phase_id = StringName(str(id) + "." + suffix)
		phase.wave_profile.profile_id = StringName(str(phase.phase_id) + ".waves")
		phase.drop_table.table_id = StringName(str(phase.phase_id) + ".drops")
		for band: WaveBandDefinition in phase.wave_profile.bands:
			band.band_id = StringName(str(phase.phase_id) + ".wave_" + str(band.first_wave))
	var partial_path: String = PARTIAL_OVERRIDES + REGION_ID + "_" + SLUGS[index - 1] + ".tres"
	if ResourceLoader.exists(partial_path):
		# 模板缓存未命中时重读单关覆盖，避免编辑器刷新后旧 Boss 残留。
		var partial: AdventureStageOverride = ResourceLoader.load(
			partial_path, "", ResourceLoader.CACHE_MODE_IGNORE) as AdventureStageOverride
		if partial == null or not partial.apply(stage):
			push_error("关卡覆盖资源无效：" + partial_path)
			return null
	return stage
