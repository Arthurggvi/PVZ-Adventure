## 地图悬停预览的视图模型：把已解析的关卡资源投影成纯展示字典。
## 只读既有目录与美术清单，不持有节点、不写存档，也不重新解释波次预算。
extends RefCounted

## 图标/底图路径与中文名称都从既有清单取，避免 UI 层维护第二份映射。
const ItemArt = preload("res://scripts/adventure/ui/inventory_item_art.gd")
## 配方掉落要叠植物头像，物种与合成面板读取同一份定义。
const Recipes = preload("res://scripts/adventure/research/research_recipe_catalog.gd")
## Boss 名称和头像沿用图鉴从战斗场景读取的资料。
const BossData = preload("res://scripts/adventure/ui/boss_almanac_data.gd")

## 情报不可展示时只提供状态，关卡本身未解锁时不会请求预览。
const STATE_SEALED := "sealed"
## 情报可展示时附上关卡名与各阶段的内容。
const STATE_READY := "ready"

## 未通关时最多列出的波次区间数量，超出时以省略号收尾。
const MAX_WAVE_RANGES := 3

## 根据 [param normal_cleared] 决定是否展示情报。
## [param stage] 为已解析关卡，缺失时也显示问号；[param title] 仅用于完整情报。
static func build(stage: StageDefinition, title: String, normal_cleared: bool) -> Dictionary:
	if not normal_cleared or stage == null:
		return {"state": STATE_SEALED}
	Global.global_read_data.ensure_almanac_loaded() # 中文名与图鉴共用同一份数据，首次读取时加载。
	var blocks: Array[Dictionary] = [] # 按普通、噩梦、终末的顺序组织情报。
	for phase: StagePhaseDefinition in _ordered_phases(stage): # 每个可展示阶段生成一块情报。
		blocks.append(_block(phase))
	return {"state": STATE_READY, "title": title, "blocks": blocks}

## 按 [param stage] 的挑战顺序列出已配置阶段。
static func _ordered_phases(stage: StageDefinition) -> Array[StagePhaseDefinition]:
	var result: Array[StagePhaseDefinition] = [] # 仅包含关卡实际配置的阶段。
	for kind: int in [StagePhaseDefinition.Kind.NORMAL, StagePhaseDefinition.Kind.NIGHTMARE, StagePhaseDefinition.Kind.TERMINAL]: # 续战顺序。
		var phase: StagePhaseDefinition = AdventureStageCatalog.find_phase(stage, kind) # 阶段可独立缺省。
		if phase != null:
			result.append(phase)
	return result

## 返回 [param phase] 的波次摘要、敌人、Boss 与掉落。
static func _block(phase: StagePhaseDefinition) -> Dictionary:
	var label: String = "普通阶段" # 预览分组的中文标题。
	var wave_text: String = "波次配置无效" # 波次或终末的胜利条件。
	if phase.kind == StagePhaseDefinition.Kind.NIGHTMARE:
		label = "噩梦阶段"
	elif phase.kind == StagePhaseDefinition.Kind.TERMINAL:
		label = "终末阶段"
		wave_text = "持续出怪 · 击败僵王博士"
	var profile: WaveProfile = phase.wave_profile # 终末阶段无波次表。
	if profile != null:
		wave_text = "%d 波 · 旗帜 %d 次" % [profile.wave_count, _flag_count(profile)]
	return {
		"phase": AdventureStageCatalog.phase_slug(phase.kind),
		"label": label,
		"wave_text": wave_text,
		"enemies": _enemies(phase),
		"bosses": _bosses(phase),
		"drops": _drops(phase.drop_table),
		"clear_drops": _clear_drops(phase.events),
	}

## 末波即使没有写进 flag_waves 也会被规划器当作大波，这里与预算口径保持一致。
static func _flag_count(profile: WaveProfile) -> int:
	var count: int = profile.flag_waves.size()
	if not profile.flag_waves.has(profile.wave_count):
		count += 1
	return count

## 敌人条目来自唯一的阶段名单，等阶徽章只做显示名与配色投影。
static func _enemies(phase: StagePhaseDefinition) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for entry: Dictionary in AdventureStageRoster.entries(phase):
		var zombie_type: int = int(entry["type"])
		if zombie_type <= 0: # 未配置的物种不参与展示。
			continue
		rows.append({
			"card_type": ResourceCardReference.CardType.Zombie,
			"type": zombie_type,
			"title": _zombie_name(zombie_type),
			"waves": _waves_text(entry["waves"]),
			"tiers": _tier_badges(entry["tiers"]),
		})
	return rows

## 返回 [param phase] 的 Boss 行，身份取自 Boss 图鉴，登场时机与掉落取自遭遇和事件配置。
static func _bosses(phase: StagePhaseDefinition) -> Array[Dictionary]:
	var rows: Array[Dictionary] = [] # 按阶段遭遇顺序输出可展示的 Boss。
	for encounter: BossEncounterDefinition in phase.boss_encounters: # 各遭遇独立显示时机与奖励。
		if encounter == null or encounter.boss_type == CharacterRegistry.ZombieBossType.Null:
			continue
		var boss_type: int = int(encounter.boss_type) # 地图行、图鉴和战斗共用的编号。
		var profile: Dictionary = BossData.profile(boss_type) # 独立图鉴尚未收录的 Boss 返回空字典。
		var title: String = str(profile.get("title", "")) # 优先采用实战界面使用的名称。
		rows.append({
			"card_type": ResourceCardReference.CardType.ZombieBoss,
			"type": boss_type,
			"title": title if not title.is_empty() else _boss_name(boss_type),
			"portrait": profile.get("portrait"),
			"timing": _timing_text(encounter),
			"drops": _boss_drops(phase.events, encounter.encounter_id),
		})
	return rows

## 从 [param events] 中读取仅在击败 [param encounter_id] 时触发的掉落，沿用波次掉落的图标字段。
static func _boss_drops(events: Array[StageEventDefinition], encounter_id: StringName) -> Array[Dictionary]:
	var rows: Array[Dictionary] = [] # 同一遭遇可能配置多个独立掉落事件。
	for event: StageEventDefinition in events: # 只投影配置，不执行事件。
		if event != null and event.trigger == StageEventDefinition.Trigger.BOSS_EXITED \
				and event.encounter_id == encounter_id and event.action == StageEventDefinition.Action.REQUEST_DROP \
				and event.boss_exit_reason == StageEventDefinition.BossExitReason.DEFEATED:
			rows.append_array(_drops(event.action_drop_table))
	return rows

## 返回 [param events] 在本阶段胜利时追加的掉落候选。
static func _clear_drops(events: Array[StageEventDefinition]) -> Array[Dictionary]:
	var rows: Array[Dictionary] = [] # 汇总胜利事件的奖励，用于单独显示通关掉落。
	for event: StageEventDefinition in events: # 仅展示结算时发放的奖励。
		if event != null and event.trigger == StageEventDefinition.Trigger.BATTLE_END \
				and event.action == StageEventDefinition.Action.REQUEST_DROP:
			rows.append_array(_drops(event.action_drop_table))
	return rows

## 掉落条目按“配方 → 肥料 → 其他”分组展示，同组内保持资源声明顺序。
## 网格只画图标，因此同时给出数量与配方头像所需字段。
static func _drops(table: DropTable) -> Array[Dictionary]:
	var recipes: Array[Dictionary] = []
	var fertilizers: Array[Dictionary] = []
	var others: Array[Dictionary] = []
	if table != null:
		for entry: DropEntryDefinition in table.entries:
			if entry == null or entry.asset_id == &"":
				continue
			var item_id := str(entry.asset_id)
			var definition: Dictionary = ItemRegistry.get_item_definition(item_id)
			var is_recipe: bool = str(definition.get("category", "")) == "recipe"
			var plant_type: int = int(Recipes.definition(item_id).get("plant_type", 0)) if is_recipe else 0 # 仅配方叠加植物头像。
			var cap: int = entry.quantity_max if entry.cap_quantity_at_max else 0 # 0 表示不显示上限。
			var row: Dictionary = _drop_row(item_id, entry.quantity_min, plant_type, cap) # 保留现有显示次序。
			if is_recipe:
				recipes.append(row)
			elif definition.has("fertilizer_level"):
				fertilizers.append(row)
			else:
				others.append(row)
			for material_id: String in entry.included_materials(): # 奖励抽中配方时附带的材料也展示在同组。
				others.append(_drop_row(material_id, entry.quantity_min))
	var rows: Array[Dictionary] = []
	rows.append_array(recipes)
	rows.append_array(fertilizers)
	rows.append_array(others)
	return rows

## 返回 [param item_id] 的图标数据；[param count] 是基础数量，[param plant_type] 和 [param cap] 为可选角标数据。
static func _drop_row(item_id: String, count: int, plant_type: int = 0, cap: int = 0) -> Dictionary:
	return {
		"id": item_id,
		"icon": ItemArt.icon_uri(item_id),
		"backing": ItemArt.backing_uri(item_id),
		"plant_type": plant_type,
		"count": count,
		"cap": cap,
	}


## 波次区间文字；没有固定波次的物种由 Boss 或事件召唤产生。
static func _waves_text(ranges: Array) -> String:
	if ranges.is_empty():
		return "额外召唤"
	var parts := PackedStringArray()
	for index: int in range(mini(ranges.size(), MAX_WAVE_RANGES)):
		var value: Vector2i = ranges[index]
		parts.append("第 %d 波" % value.x if value.x == value.y else "第 %d–%d 波" % [value.x, value.y])
	if ranges.size() > MAX_WAVE_RANGES:
		parts.append("…")
	return "、".join(parts)

## 等阶徽章只投影显示名与配色，按等阶目录顺序升序排列，不依赖池子里的声明顺序。
static func _tier_badges(tiers: Array) -> Array[Dictionary]:
	var badges: Array[Dictionary] = []
	for tier_id: StringName in AdventureZombieTierCatalog.tier_ids():
		if not tiers.has(tier_id):
			continue
		var definition: Dictionary = AdventureZombieTierCatalog.get_tier(tier_id)
		if definition.is_empty():
			continue
		badges.append({
			"label": AdventureZombieTierCatalog.display_name(tier_id),
			"color": definition["tint"],
		})
	return badges

## 僵尸中文名来自图鉴；未登记时退回编号，避免静默显示空标题。
static func _zombie_name(zombie_type: int) -> String:
	if Global.character_registry == null or Global.global_read_data == null:
		return "僵尸 #%d" % zombie_type
	if not Global.character_registry.ZombieInfo.has(zombie_type):
		return "僵尸 #%d" % zombie_type
	var key := str(Global.character_registry.get_zombie_info(
		zombie_type as CharacterRegistry.ZombieType,
		CharacterRegistry.ZombieInfoAttribute.ZombieName))
	var entry: Dictionary = Global.global_read_data.data_almanac.get("Zombie", {}).get(key, {})
	return str(entry.get("名字", "僵尸 #%d" % zombie_type))

## 从旧版图鉴查找 [param boss_type] 的名称，供独立 Boss 图鉴尚未收录的角色使用。
static func _boss_name(boss_type: int) -> String:
	if Global.character_registry == null or Global.global_read_data == null:
		return "僵王 #%d" % boss_type
	if not Global.character_registry.ZombieBossInfo.has(boss_type):
		return "僵王 #%d" % boss_type
	var key := str(Global.character_registry.get_zombie_boss_info(
		boss_type as CharacterRegistry.ZombieBossType,
		CharacterRegistry.ZombieBossInfoAttribute.BossName))
	var entry: Dictionary = Global.global_read_data.data_almanac.get("ZombieBoss", {}).get(key, {})
	return str(entry.get("名字", "僵王 #%d" % boss_type))

## Boss 登场时机的中文说明，未知时机原样提示而不是猜测。
static func _timing_text(encounter: BossEncounterDefinition) -> String:
	match encounter.timing:
		BossEncounterDefinition.Timing.PHASE_START:
			return "开场登场"
		BossEncounterDefinition.Timing.WAVE_BEFORE:
			return "第 %d 波前登场" % encounter.wave
		BossEncounterDefinition.Timing.WAVE_STARTED:
			return "第 %d 波登场" % encounter.wave
		BossEncounterDefinition.Timing.WAVE_CLEARED:
			return "第 %d 波清场后登场" % encounter.wave
		BossEncounterDefinition.Timing.EVENT_ONLY:
			return "由事件召唤"
	return "登场时机未配置"
