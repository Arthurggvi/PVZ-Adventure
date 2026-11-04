## 关卡掉落计算及道具入账：独立概率、权重、保底与首通奖励。
## 只处理内存；存档事务边界由 AdventureSession 统一负责。
extends RefCounted
class_name AdventureRewardService

static func roll(table: DropTable, rng: RandomNumberGenerator) -> Dictionary:
	if table == null or rng == null or not table.validate().is_empty():
		return {"ok": false}
	var items: Dictionary = {}
	var weighted: Array[DropEntryDefinition] = []
	for entry: DropEntryDefinition in table.entries:
		match entry.rule:
			DropEntryDefinition.Rule.GUARANTEED:
				_add(items, str(entry.asset_id), entry.quantity_min)
			DropEntryDefinition.Rule.CHANCE:
				if rng.randf() < entry.chance:
					_add(items, str(entry.asset_id), rng.randi_range(entry.quantity_min, entry.quantity_max))
			DropEntryDefinition.Rule.WEIGHTED:
				weighted.append(entry)
	for draw: int in range(table.weighted_draw_count):
		var total := 0
		for option: DropEntryDefinition in weighted:
			total += option.weight
		if total <= 0:
			return {"ok": false}
		var choice: int = rng.randi_range(1, total)
		for i: int in range(weighted.size()):
			var option: DropEntryDefinition = weighted[i]
			choice -= option.weight
			if choice <= 0:
				_add(items, str(option.asset_id), rng.randi_range(option.quantity_min, option.quantity_max))
				if table.weighted_selection == DropTable.WeightedSelection.WITHOUT_REPLACEMENT:
					weighted.remove_at(i)
				break
	if not _fill_floor(items, table, rng):
		return {"ok": false}
	return {"ok": true, "items": items}

static func _fill_floor(items: Dictionary, table: DropTable, rng: RandomNumberGenerator) -> bool:
	var material_ids: Array[String] = []
	var recipe_ids: Array[String] = []
	for entry: DropEntryDefinition in table.entries:
		var item_id: String = str(entry.asset_id)
		var category: String = str(ItemRegistry.get_item_definition(item_id).get("category", ""))
		if category == "material" and not material_ids.has(item_id):
			material_ids.append(item_id)
		elif category == "recipe" and not recipe_ids.has(item_id):
			recipe_ids.append(item_id)
	var distinct := 0
	for item_id: String in material_ids:
		if items.get(item_id, 0) > 0:
			distinct += 1
	for item_id: String in material_ids:
		if distinct >= table.min_distinct_materials:
			break
		if items.get(item_id, 0) == 0:
			_add(items, item_id, 1)
			distinct += 1
	return _fill_quantity(items, material_ids, table.min_material_count, rng) \
		and _fill_quantity(items, recipe_ids, table.min_recipe_count, rng)

static func _fill_quantity(items: Dictionary, candidates: Array[String], required: int,
		rng: RandomNumberGenerator) -> bool:
	var total := 0
	for id: String in candidates:
		total += int(items.get(id, 0))
	if total < required and candidates.is_empty():
		return false
	for missing: int in range(maxi(0, required - total)):
		_add(items, candidates[rng.randi_range(0, candidates.size() - 1)], 1)
	return true

static func _add(items: Dictionary, id: String, count: int) -> void:
	items[id] = int(items.get(id, 0)) + count

## 首通与 Boss 条件确定后合并所有奖励，不在此处修改玩家资产。
static func prepare(phase: StagePhaseDefinition, table: DropTable,
		claimed: Dictionary, boss_defeated: bool, rng: RandomNumberGenerator) -> Dictionary:
	var result: Dictionary = roll(table, rng)
	if not result.get("ok", false):
		return {"ok": false}
	var claim_id: String = "first_clear/" + str(phase.phase_id)
	var qualified: bool = not phase.first_clear_requires_boss_kill or boss_defeated
	var first: bool = qualified and not claimed.get(claim_id, false)
	var items: Dictionary = result["items"]
	if first:
		for id: StringName in phase.first_clear_items:
			_add(items, str(id), phase.first_clear_items[id])
	result["coin"] = phase.first_clear_coin if first else 0
	result["claim_id"] = claim_id if first else ""
	return result

## 整体预检成功才写入内存；失败时由调用方恢复事务快照。
static func apply(items: Dictionary, coin: int, state: AdventureState,
		inventory: AdventureInventoryService, global_state: GlobalGameState) -> bool:
	if state == null or inventory == null or global_state == null or coin < 0:
		return false
	if global_state.coin_value < 0 or global_state.coin_value > PlantCardInstance.MAX_JSON_INTEGER - coin:
		return false
	for key: Variant in items:
		var id: String = str(key)
		var qty: int = int(items[key])
		if not ItemRegistry.has_item(id) or qty < 1 or state.items.get(id, 0) > PlantCardInstance.MAX_JSON_INTEGER - qty:
			return false
	for key: Variant in items:
		if not inventory.add_item(str(key), int(items[key])):
			return false
	global_state.coin_value += coin
	return true
