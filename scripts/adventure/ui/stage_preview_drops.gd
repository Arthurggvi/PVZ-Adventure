## 关卡预览的静态掉落投影与配方来源汇总，不抽奖、不查询库存、不改写资源。
extends RefCounted

## 图标和底图沿用背包美术清单，不另建配方贴图映射。
const ItemArt = preload("res://scripts/adventure/ui/inventory_item_art.gd")
## 配方物种沿用研究室目录，不能由物品 ID 前缀推断。
const Recipes = preload("res://scripts/adventure/research/research_recipe_catalog.gd")

## 返回 [param table] 的候选，按配方、肥料、其他排序；空表返回空数组。
## 保留资源声明顺序和数量语义，不把概率、保底或多个来源合成为承诺数量。
static func from_table(table: DropTable) -> Array[Dictionary]:
	var recipes: Array[Dictionary] = [] # 优先展示的配方候选。
	var fertilizers: Array[Dictionary] = [] # 配方之后的强化肥料。
	var others: Array[Dictionary] = [] # 其他道具及配方附带材料。
	if table != null:
		for entry: DropEntryDefinition in table.entries: # 只读各独立掉落条目。
			if entry == null or entry.asset_id == &"":
				continue
			var item_id := str(entry.asset_id) # 道具目录和素材清单使用的稳定键。
			var definition: Dictionary = ItemRegistry.get_item_definition(item_id) # 分类与显示名的权威定义。
			var cap: int = entry.quantity_max if entry.cap_quantity_at_max else 0 # 零表示未启用数量上限角标。
			var row: Dictionary = _row(item_id, entry.quantity_min, cap) # 数量仍为原条目的基础数量。
			if row["is_recipe"]:
				recipes.append(row)
			elif definition.has("fertilizer_level"):
				fertilizers.append(row)
			else:
				others.append(row)
			for material_id: String in entry.included_materials(): # 只在配方条目显式附带时列出材料。
				others.append(_row(material_id, entry.quantity_min))
	var rows: Array[Dictionary] = [] # 合并各组，不改变原有候选和数量。
	rows.append_array(recipes)
	rows.append_array(fertilizers)
	rows.append_array(others)
	return rows

## 返回 [param item_id] 的名称和图标；[param count] 为基础数量，[param cap] 为可选上限。
## 配方类别取自物品目录，植物头像编号取自研究目录；未知编号不补画头像。
static func _row(item_id: String, count: int, cap: int = 0) -> Dictionary:
	var definition: Dictionary = ItemRegistry.get_item_definition(item_id) # 已解析中文名的只读定义副本。
	var is_recipe: bool = str(definition.get("category", "")) == "recipe" # 不猜测 ID 格式。
	var plant_type: int = int(Recipes.definition(item_id).get("plant_type", 0)) if is_recipe else 0 # 零表示无植物头像。
	return {
		"id": item_id,
		"title": str(definition.get("name", item_id)),
		"is_recipe": is_recipe,
		"icon": ItemArt.icon_uri(item_id),
		"backing": ItemArt.backing_uri(item_id),
		"plant_type": plant_type,
		"count": count,
		"cap": cap,
	}

## 从 [param events] 中读取击败 [param encounter_id] 时的掉落，保留各独立事件顺序。
## 逃跑或任意离场的事件不冒充击败奖励，候选内容不在预览中执行。
static func for_boss(events: Array[StageEventDefinition], encounter_id: StringName) -> Array[Dictionary]:
	var rows: Array[Dictionary] = [] # 同一遭遇可能配置多个独立掉落事件。
	for event: StageEventDefinition in events: # 只投影既有的击败过滤规则。
		if event != null and event.trigger == StageEventDefinition.Trigger.BOSS_EXITED \
				and event.encounter_id == encounter_id and event.action == StageEventDefinition.Action.REQUEST_DROP \
				and event.boss_exit_reason == StageEventDefinition.BossExitReason.DEFEATED:
			rows.append_array(from_table(event.action_drop_table))
	return rows

## 返回 [param events] 在阶段胜利时追加的候选，沿用原预览的通关事件筛选规则。
static func for_clear(events: Array[StageEventDefinition]) -> Array[Dictionary]:
	var rows: Array[Dictionary] = [] # 仅包含通关时发放的独立事件奖励。
	for event: StageEventDefinition in events: # 不把其他触发条件混入通关候选。
		if event != null and event.trigger == StageEventDefinition.Trigger.BATTLE_END \
				and event.action == StageEventDefinition.Action.REQUEST_DROP:
			rows.append_array(from_table(event.action_drop_table))
	return rows

## 将 [param blocks] 已展示的配方按 ID 去重，合并阶段、通关和 Boss 来源文字。
## 返回副本；数量保留首个来源的原值，不累加为必得数量；sources 为逐行来源字符串。
static func recipe_summary(blocks: Array[Dictionary]) -> Array[Dictionary]:
	var by_id: Dictionary = {} # 按首次出现顺序保留配方的完整展示字段。
	var source_lists: Dictionary = {} # 每张配方的去重来源列表，不暴露为库存或奖励状态。
	for block: Dictionary in blocks: # 沿用普通、噩梦、终末的分组顺序。
		var label: String = str(block.get("label", "")) # 标明奖励所属的真实阶段。
		var base_source: String = "阶段掉落候选" if block.get("phase") == "terminal" else "波次掉落候选" # 终末无自然波次。
		_collect(block.get("drops", []), label + " · " + base_source, by_id, source_lists)
		_collect(block.get("clear_drops", []), label + " · 通关掉落候选", by_id, source_lists)
		for boss: Dictionary in block.get("bosses", []): # 每个 Boss 的掉落仍以击败对应遭遇为条件。
			var boss_title: String = str(boss.get("title", "Boss")) # 使用同一预览行的中文名。
			var timing: String = str(boss.get("timing", "")) # 区分同名 Boss 在不同波次的遭遇。
			var source: String = "%s · 击败%s%s后掉落候选" % [label, boss_title, "（%s）" % timing if not timing.is_empty() else ""] # 不暗示必掉。
			_collect(boss.get("drops", []), source, by_id, source_lists)
	var rows: Array[Dictionary] = [] # 输出独立字典，普通掉落网格不受汇总字段影响。
	for item_id: String in by_id: # 保持各配方首次出现的顺序。
		var row: Dictionary = by_id[item_id] # 已在收集时深拷贝的展示条目。
		row["sources"] = "\n".join(PackedStringArray(source_lists[item_id]))
		rows.append(row)
	return rows

## 将 [param rows] 中的配方收集进 [param by_id]，把 [param source] 去重写入 [param source_lists]。
## 只修改汇总容器；原有阶段、Boss 和通关掉落字典保持不变。
static func _collect(rows: Array, source: String, by_id: Dictionary, source_lists: Dictionary) -> void:
	for row: Dictionary in rows: # 普通材料与道具不进入配方醒目区。
		if not bool(row.get("is_recipe", false)):
			continue
		var item_id: String = str(row.get("id", "")) # 同一种配方在所有来源中使用同一个稳定键。
		if not by_id.has(item_id):
			by_id[item_id] = row.duplicate(true)
			source_lists[item_id] = []
		var sources: Array = source_lists[item_id] # 同一配方各独立来源的可变列表。
		if not sources.has(source):
			sources.append(source)
