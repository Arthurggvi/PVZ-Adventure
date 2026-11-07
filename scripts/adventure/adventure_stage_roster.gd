## 单阶段敌人名单的唯一遍历：物种、可出现的等阶与波次区间。
## 战斗开场预览与地图悬停预览都从这里取数，避免波段、预排、Boss 援军和事件各解释一遍规则。
extends RefCounted
class_name AdventureStageRoster

## 返回 [param phase] 的敌人条目，按首次出现顺序去重，不读取进度或实例化战斗角色。
## 每项为 ``{"type": ZombieType, "tiers": Array[StringName], "waves": Array[Vector2i]}``；
## ``tiers`` 只含正权重等阶，``waves`` 为合并后的闭区间，空数组表示没有固定波次（Boss/事件召唤）。
static func entries(phase: StagePhaseDefinition) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if phase == null or phase.wave_profile == null:
		return result
	var profile: WaveProfile = phase.wave_profile
	for band: WaveBandDefinition in profile.bands: # 波段池：出现区间由波段本身给出。
		if band == null:
			continue
		_merge_pool(result, band.zombie_weights, band.tier_weights,
			Vector2i(band.first_wave, band.last_wave))
	for group: WaveSpawnGroup in profile.scheduled_spawns: # 预排出怪：只占自己那一波。
		if group == null:
			continue
		_merge_pool(result, group.zombie_weights, group.tier_weights,
			Vector2i(group.wave, group.wave))
	for encounter: BossEncounterDefinition in phase.boss_encounters: # Boss 援军不属于固定波次。
		if encounter == null:
			continue
		for zombie_type: CharacterRegistry.ZombieType in encounter.summon_zombie_weights:
			if encounter.summon_zombie_weights[zombie_type] > 0:
				_merge(result, zombie_type, _positive_tiers(encounter.summon_tier_weights),
					Vector2i.ZERO)
	for event: StageEventDefinition in phase.events: # 事件突袭保留自己的触发波次。
		if event == null or event.action != StageEventDefinition.Action.SPAWN_ZOMBIES:
			continue
		var event_tiers: Array[StringName] = [] # 事件只声明一个等阶。
		if event.action_tier_id != &"":
			event_tiers.append(event.action_tier_id)
		var event_wave := Vector2i(event.wave, event.wave) if event.wave > 0 else Vector2i.ZERO
		_merge(result, event.action_zombie_type, event_tiers, event_wave)
	for row: Dictionary in result: # 波段与预排可能覆盖同一物种，最后统一合并区间。
		row["waves"] = _merged_ranges(row["waves"])
	return result

## 返回 [param phase] 中出现的物种，顺序与 [method entries] 一致，供战斗预览直接投影。
static func zombie_types(phase: StagePhaseDefinition) -> Array[CharacterRegistry.ZombieType]:
	var types: Array[CharacterRegistry.ZombieType] = []
	for row: Dictionary in entries(phase):
		types.append(row["type"])
	return types

## 把一组权重池按 [param waves] 区间并入结果；权重非正的物种不参与预览。
static func _merge_pool(result: Array[Dictionary], zombie_weights: Dictionary,
		tier_weights: Dictionary, waves: Vector2i) -> void:
	var tiers := _positive_tiers(tier_weights) # 同一池子的所有物种共享等阶集合。
	for zombie_type: CharacterRegistry.ZombieType in zombie_weights:
		if zombie_weights[zombie_type] > 0:
			_merge(result, zombie_type, tiers, waves)

## 把 [param zombie_type] 合并进同名条目；[param waves] 为零向量时只补充等阶。
static func _merge(result: Array[Dictionary], zombie_type: CharacterRegistry.ZombieType,
		tiers: Array[StringName], waves: Vector2i) -> void:
	var row: Dictionary = {}
	for existing: Dictionary in result:
		if existing["type"] == zombie_type:
			row = existing
			break
	if row.is_empty():
		var empty_tiers: Array[StringName] = []
		var empty_waves: Array[Vector2i] = []
		row = {"type": zombie_type, "tiers": empty_tiers, "waves": empty_waves}
		result.append(row)
	var row_tiers: Array = row["tiers"]
	for tier_id: StringName in tiers:
		if not row_tiers.has(tier_id):
			row_tiers.append(tier_id)
	var row_waves: Array = row["waves"]
	if waves != Vector2i.ZERO and not row_waves.has(waves):
		row_waves.append(waves)

## 汇总 [param weights] 中权重大于 0 的等阶，保留资源里的声明顺序。
static func _positive_tiers(weights: Dictionary) -> Array[StringName]:
	var tiers: Array[StringName] = []
	for key: Variant in weights:
		var tier_id := StringName(key)
		if int(weights[key]) > 0 and not tiers.has(tier_id):
			tiers.append(tier_id)
	return tiers

## 把可能重叠或相邻的闭区间合并成升序列表，避免同一物种重复列出连续波次。
static func _merged_ranges(ranges: Array) -> Array[Vector2i]:
	var sorted: Array[Vector2i] = []
	for value: Variant in ranges:
		var value_range: Vector2i = value
		sorted.append(value_range)
	sorted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x)
	var merged: Array[Vector2i] = []
	for value: Vector2i in sorted:
		if merged.is_empty():
			merged.append(value)
			continue
		var last: Vector2i = merged[merged.size() - 1]
		if value.x <= last.y + 1:
			merged[merged.size() - 1] = Vector2i(last.x, maxi(last.y, value.y))
		else:
			merged.append(value)
	return merged
