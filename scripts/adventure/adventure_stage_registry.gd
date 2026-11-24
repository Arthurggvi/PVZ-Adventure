## 冒险关卡身份目录，统一解析专属配置与没落营地模板。
extends RefCounted
class_name AdventureStageRegistry

## 致幻洋流正式编号，供初次开放与战场资源加载使用。
const PSYCHEDELIC_CURRENT: int = 101
## 圣堂正式编号，沿用奇境大陆的顺序解锁。
const ZOMBIE_CHURCH: int = 102
## 边境雪山正式编号，圣堂普通阶段通关后解锁。
const SNOW_MOUNTAINS: int = 103
## 安息平原正式编号，沿用奇境大陆同地区的顺序解锁。
const RESTING_PLAIN: int = 104
## 花园飞艇沿用地图现有 garden_airship 锚点，安息平原继续使用 104。
const GARDEN_AIRSHIP: int = 105

## 僵尸岛地区存档 ID。
const REGION_ID := "zombie_island"
## 没落营地自身使用模板的原始身份，并额外应用单关覆盖。
const FALLEN_CAMP_ID: StringName = &"zombie_island.fallen_camp"
## 地图编号对应的存档 ID 与关卡显示名称。
const STAGES: Dictionary[int, Dictionary] = {
	1: {"id": &"zombie_island.lawn", "name": "草坪"},
	2: {"id": FALLEN_CAMP_ID, "name": "没落营地"},
	3: {"id": &"zombie_island.grave_upstream", "name": "墓地上游"},
	4: {"id": &"zombie_island.grave_downstream", "name": "墓地下游"},
	5: {"id": &"zombie_island.sewer", "name": "下水道"},
	6: {"id": &"zombie_island.edgar_temple", "name": "埃德加神殿"},
	PSYCHEDELIC_CURRENT: {"id": &"wonderland.psychedelic_current", "name": "致幻洋流"},
	ZOMBIE_CHURCH: {"id": &"wonderland.zombie_church", "name": "圣堂"},
	SNOW_MOUNTAINS: {"id": &"wonderland.snow_mountains", "name": "边境雪山"},
	RESTING_PLAIN: {"id": &"wonderland.resting_plain", "name": "安息平原"},
	GARDEN_AIRSHIP: {"id": &"wonderland.garden_airship", "name": "花园飞艇"},
}
## 这些已有局部配置的僵尸岛关卡继续沿用原来的地区基底。
const LEGACY_ISLAND_STAGES: Array[StringName] = [
	&"zombie_island.grave_upstream", &"zombie_island.grave_downstream",
	&"zombie_island.sewer", &"zombie_island.edgar_temple",
]
## 兼容已有僵尸岛局部覆盖的原地区基底。
const LEGACY_ISLAND_BASE := "res://resources/adventure/stages/zombie_island_default.tres"
## 新关卡采用的通用战场、两阶段及 Boss 遭遇模板。
const DEFAULT_TEMPLATE := "res://resources/adventure/stages/templates/fallen_camp.tres"
## 单关完整配置目录，文件名由关卡 ID 派生。
const OVERRIDE_ROOT := "res://resources/adventure/stages/"
## 单关局部覆盖目录，与完整配置共用文件名规则。
const PARTIAL_OVERRIDES := "res://resources/adventure/stages/overrides/"
## 套用模板的跨地区关卡返回自己的地图；僵尸岛沿用会话默认返图。
const REGION_RETURN_SCENES: Dictionary[String, String] = {
	"wonderland": "res://scenes/adventure/wonderland_map.tscn",
}

## 仅缓存已经合并的私有模板；对外始终给独立副本，避免本局或预览污染下一次请求。
static var _resolved_templates: Dictionary[int, StageDefinition] = {}

## 开发版可以访问奇境大陆，Windows 和 Android 正式导出共用僵尸岛发行范围。
static func is_wonderland_available() -> bool:
	return not OS.has_feature("release_shipping")

## 从 [param id] 的稳定关卡身份取得存档地区。
static func region_for(id: StringName) -> String:
	return str(id).get_slice(".", 0)

## 返回 [param index] 对应的稳定关卡 ID，未登记的编号返回空值。
static func stage_id(index: int) -> StringName:
	var id: StringName = STAGES.get(index, {}).get("id", &"") # 发行范围跟随地区身份。
	if not is_wonderland_available() and region_for(id) == "wonderland":
		return &""
	return id

## 返回 [param index] 的本关噩梦钥匙 ID，保留草坪旧存档的物品 ID。
static func key_id(index: int) -> StringName:
	if index == 1:
		return &"lawn_nightmare_key"
	var id: StringName = stage_id(index) # 模板续战始终使用当前关卡身份。
	return StringName(str(id) + ".nightmare_key") if id != &"" else &""

## 返回 [param index] 的同地区前一关 ID，供普通阶段通关解锁使用。
static func previous_stage_id(index: int) -> StringName:
	var previous: StringName = stage_id(index - 1) # 地区内连续登记的前一关。
	return previous if region_for(previous) == region_for(stage_id(index)) else &""

## 返回 [param index] 在地图及战斗结算中使用的显示名称。
static func display_name(index: int) -> String:
	return STAGES.get(index, {}).get("name", "未知关卡")

## 返回 [param index] 的独立关卡配置；同一地图访问内只读取并合并一次源资源。
## 缓存模板不对外发布，调用方可以继续安全地调整本局副本。
static func resolve(index: int) -> StageDefinition:
	if not _resolved_templates.has(index):
		var resolved: StageDefinition = _resolve_template(index) # 首次请求才读取并合并本关资源。
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

## 解析 [param index] 的私有模板；完整关卡优先，局部覆盖按所用基底合并。
static func _resolve_template(index: int) -> StageDefinition:
	var id: StringName = stage_id(index) # 参数无效时不读取磁盘。
	if id == &"":
		return null
	var file_name: String = str(id).replace(".", "_") + ".tres" # 两种专属配置共享地区和关卡文件名规则。
	var override_path: String = OVERRIDE_ROOT + file_name # 独立 StageDefinition 资源。
	if ResourceLoader.exists(override_path):
		# 地图访问显式失效后重新读覆盖资源，保留编辑器重进地图刷新约定。
		var override: StageDefinition = ResourceLoader.load( # 本关完整资源，保持作者指定的阶段与钥匙。
			override_path, "", ResourceLoader.CACHE_MODE_IGNORE) as StageDefinition
		if override == null or override.stage_id != id:
			push_error("关卡覆盖资源 ID 错误：" + override_path)
			return null
		return override
	var partial_path: String = PARTIAL_OVERRIDES + file_name # 可选的关卡差异资源。
	var has_partial: bool = ResourceLoader.exists(partial_path) # 已有配置时保留对应基底选择。
	var use_legacy_base: bool = has_partial and id in LEGACY_ISLAND_STAGES # 兼容既有地区配置。
	var base_path: String = LEGACY_ISLAND_BASE if use_legacy_base else DEFAULT_TEMPLATE # 本关继承的资源路径。
	var stage: StageDefinition = ResourceLoader.load( # 跳过主资源缓存，为当前编号创建独立基底。
		base_path, "", ResourceLoader.CACHE_MODE_IGNORE) as StageDefinition
	if stage == null:
		return null
	var template_id: StringName = stage.stage_id # 保留模板身份以同步改写 Boss 及事件引用。
	stage.stage_id = id
	stage.nightmare_key_id = key_id(index)
	for phase: StagePhaseDefinition in stage.phases: # 两套基底均声明普通和噩梦阶段。
		if not use_legacy_base:
			# 阶段掉落表来自外部资源，先复制再为当前关卡写入掉落与 ID。
			phase.drop_table = phase.drop_table.duplicate(true) as DropTable
			for event: StageEventDefinition in phase.events: # 事件掉落表同样属于本关快照。
				if event.action_drop_table != null:
					event.action_drop_table = event.action_drop_table.duplicate(true) as DropTable
		if id == template_id:
			continue
		var suffix := "normal" if phase.kind == StagePhaseDefinition.Kind.NORMAL else "nightmare" # 既有存档的阶段后缀。
		phase.phase_id = StringName(str(id) + "." + suffix)
		phase.wave_profile.profile_id = StringName(str(phase.phase_id) + ".waves")
		phase.drop_table.table_id = StringName(str(phase.phase_id) + ".drops")
		for band: WaveBandDefinition in phase.wave_profile.bands: # 波段按起始波次获得本关身份。
			band.band_id = StringName(str(phase.phase_id) + ".wave_" + str(band.first_wave))
	if not use_legacy_base and id != template_id:
		_prepare_fallback_stage(stage, template_id)
	if has_partial:
		# 模板缓存未命中时重读单关覆盖，避免编辑器刷新后旧 Boss 残留。
		var partial: AdventureStageOverride = ResourceLoader.load( # 只将显式声明的差异应用到基底。
			partial_path, "", ResourceLoader.CACHE_MODE_IGNORE) as AdventureStageOverride
		if partial == null or not partial.apply(stage):
			push_error("关卡覆盖资源无效：" + partial_path)
			return null
	return stage

## 为套用营地模板的 [param stage] 配置返图和续战，并将 [param template_id] 的 Boss 事件关联到本关。
static func _prepare_fallback_stage(stage: StageDefinition, template_id: StringName) -> void:
	stage.return_scene = REGION_RETURN_SCENES.get(region_for(stage.stage_id), "")
	var template_prefix: String = str(template_id) + "." # 只改写模板自身命名空间下的资源 ID。
	var stage_prefix: String = str(stage.stage_id) + "." # 本关独立的任务与遭遇身份。
	for phase: StagePhaseDefinition in stage.phases: # 补完续战来源，并同步 Boss 遭遇与触发事件。
		if phase.kind == StagePhaseDefinition.Kind.NORMAL:
			var key_drop := DropEntryDefinition.new() # 每次普通清场可获得本局续战所需的钥匙。
			key_drop.entry_id = StringName(str(phase.phase_id) + ".nightmare_key_drop")
			key_drop.rule = DropEntryDefinition.Rule.GUARANTEED
			key_drop.asset_kind = DropEntryDefinition.AssetKind.KEY
			key_drop.asset_id = stage.nightmare_key_id
			key_drop.quantity_min = stage.nightmare_key_count
			key_drop.quantity_max = stage.nightmare_key_count
			phase.drop_table.entries.append(key_drop)
		for encounter: BossEncounterDefinition in phase.boss_encounters: # 击败事件以本关遭遇 ID 上报任务。
			encounter.encounter_id = StringName(str(encounter.encounter_id).replace(template_prefix, stage_prefix))
		for event: StageEventDefinition in phase.events: # 同步事件身份与它引用的遭遇。
			event.event_id = StringName(str(event.event_id).replace(template_prefix, stage_prefix))
			event.encounter_id = StringName(str(event.encounter_id).replace(template_prefix, stage_prefix))
			if event.action == StageEventDefinition.Action.BEGIN_BOSS_ENCOUNTER:
				event.action_target_id = StringName(str(event.action_target_id).replace(template_prefix, stage_prefix))
