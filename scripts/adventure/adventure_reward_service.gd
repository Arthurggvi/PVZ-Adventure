## 关卡掉落计算及道具入账：独立概率、权重、保底与首通奖励。
## 只处理内存；存档事务边界由 AdventureSession 统一负责。
extends RefCounted
class_name AdventureRewardService

## 首通钱币沿用战场银币、金币与钻石的面额，且不受装备加成。
const FIRST_CLEAR_COIN_VALUES := {"diamond": 1000, "gold": 50, "silver": 10}
## 地区存档中按领取 ID 保存尚未拾取的各面额钱币数量。
const PENDING_FIRST_CLEAR_COINS := "pending_first_clear_coins"

## 抽取 [param table]；[param effects] 仅修正随机材料/消耗品，固定与补齐奖励保持原配置。
static func roll(table: DropTable, rng: RandomNumberGenerator, effects: PlayerEffects = null) -> Dictionary:
	if table == null or rng == null or not table.validate().is_empty():
		return {"ok": false}
	var items: Dictionary = {}
	var weighted: Array[DropEntryDefinition] = []
	for entry: DropEntryDefinition in table.entries:
		var eligible: bool = effects != null and PlayerEffects.is_random_loot(str(entry.asset_id)) # 来源规则在计算处判定。
		match entry.rule:
			DropEntryDefinition.Rule.GUARANTEED:
				_add_entry(items, entry, entry.quantity_min)
			DropEntryDefinition.Rule.CHANCE:
				var chance: float = minf(1.0, entry.chance * effects.drop_chance_multiplier) if eligible else entry.chance # 相对概率封顶。
				if rng.randf() < chance:
					var quantity: int = _random_quantity(entry, rng, effects) # 生成时只应用一次数量加成。
					if quantity < 1:
						return {"ok": false}
					_add_entry(items, entry, quantity)
			DropEntryDefinition.Rule.WEIGHTED:
				weighted.append(entry)
	for draw: int in range(table.weighted_draw_count): # 每次尝试最多选中一个候选。
		if table.weighted_draw_chance < 1.0 and rng.randf() >= table.weighted_draw_chance:
			continue
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
				var quantity: int = _random_quantity(option, rng, effects) # 加权选中后的数量可加成，权重不整体乘倍。
				if quantity < 1:
					return {"ok": false}
				_add_entry(items, option, quantity)
				if table.weighted_selection == DropTable.WeightedSelection.WITHOUT_REPLACEMENT:
					weighted.remove_at(i)
				break
	if not _fill_floor(items, table, rng):
		return {"ok": false}
	return {"ok": true, "items": items}

## 用 [param rng] 抽取 [param entry] 数量并应用 [param effects]，最后执行条目上限；溢出返回 -1。
static func _random_quantity(entry: DropEntryDefinition, rng: RandomNumberGenerator, effects: PlayerEffects) -> int:
	var quantity: int = rng.randi_range(entry.quantity_min, entry.quantity_max) # 每个条目只抽一次。
	if effects != null and PlayerEffects.is_random_loot(str(entry.asset_id)):
		quantity = PlayerEffects.scale_amount(quantity, float(effects.loot_multiplier))
	return mini(quantity, entry.quantity_max) if entry.cap_quantity_at_max else quantity

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

## 把抽中的 [param entry] 写入 [param items]；每份 [param count] 配方可附带一套材料。
static func _add_entry(items: Dictionary, entry: DropEntryDefinition, count: int) -> void:
	_add(items, str(entry.asset_id), count)
	for material_id: String in entry.included_materials(): # 随配方发放，不单独抽概率或装备倍率。
		_add(items, material_id, count)

static func _add(items: Dictionary, id: String, count: int) -> void:
	items[id] = int(items.get(id, 0)) + count

## 按 [param phase]、[param table]、[param claimed] 与 [param boss_defeated] 合并奖励。
## [param rng] 决定本次抽取，[param effects] 仅进入随机掉落计算，首通奖励不加成；不修改玩家资产。
static func prepare(phase: StagePhaseDefinition, table: DropTable,
		claimed: Dictionary, boss_defeated: bool, rng: RandomNumberGenerator, effects: PlayerEffects = null) -> Dictionary:
	var result: Dictionary = roll(table, rng, effects)
	if not result.get("ok", false):
		return {"ok": false}
	var claim_id: String = first_clear_claim_id(phase) # 沿用已有存档的首通领取标记。
	var qualified: bool = not phase.first_clear_requires_boss_kill or boss_defeated
	var first: bool = qualified and not claimed.get(claim_id, false)
	var items: Dictionary = result["items"]
	if first:
		for id: StringName in phase.first_clear_items:
			_add(items, str(id), phase.first_clear_items[id])
	result["first_clear_coins"] = {"diamond": 9 if phase.kind == StagePhaseDefinition.Kind.NIGHTMARE else 4,
		"gold": 19, "silver": 5} if first else {}
	result["claim_id"] = claim_id if first else ""
	return result

## 返回 [param phase] 对应的历史领取 ID，用于查重和定位未拾取钱币。
static func first_clear_claim_id(phase: StagePhaseDefinition) -> String:
	return "first_clear/" + str(phase.phase_id)

## 返回 [param state] 中 [param claim_id] 未拾取的钱币数量副本；没有记录时返回空字典。
static func pending_first_clear_coins(state: AdventureState, claim_id: String) -> Dictionary:
	var region: Dictionary = state.regions.get(AdventureStageCatalog.REGION_ID, {}) # 钱币属于当前地区的关卡记录。
	var pending: Dictionary = region.get(PENDING_FIRST_CLEAR_COINS, {}) # 按首通领取 ID 索引的余量。
	var coins: Dictionary = pending.get(claim_id, {}) # 仅返回本阶段的钱堆。
	return coins.duplicate()

## 把 [param state] 中 [param claim_id] 的余量更新为 [param coins]；收完时清理记录。
static func set_pending_first_clear_coins(state: AdventureState, claim_id: String, coins: Dictionary) -> void:
	var region: Dictionary = state.regions.get(AdventureStageCatalog.REGION_ID, {}) # 与通关进度一起写入全局存档。
	var pending: Dictionary = region.get(PENDING_FIRST_CLEAR_COINS, {}) # 保留其他阶段的未拾取钱币。
	if coins.is_empty():
		pending.erase(claim_id)
	else:
		pending[claim_id] = coins.duplicate()
	if pending.is_empty():
		region.erase(PENDING_FIRST_CLEAR_COINS)
	else:
		region[PENDING_FIRST_CLEAR_COINS] = pending
	state.regions[AdventureStageCatalog.REGION_ID] = region

## 从 [param state] 的 [param claim_id] 中扣除一枚 [param denomination]；没有余量时返回 false。
## 调用方在成功后立即更新钱包，使自动存档同时观察到这两项变化。
static func take_first_clear_coin(state: AdventureState, claim_id: String, denomination: String) -> bool:
	var coins: Dictionary = pending_first_clear_coins(state, claim_id) # 当前钱堆的独立余量。
	var count: int = int(coins.get(denomination, 0)) # 此面额尚未领取的枚数。
	if count <= 0:
		return false
	if count == 1:
		coins.erase(denomination)
	else:
		coins[denomination] = count - 1
	set_pending_first_clear_coins(state, claim_id, coins)
	return true

## 计算 [param coins] 的总面额，供跳过奖杯演出的一键通关结算。
static func first_clear_coin_total(coins: Dictionary) -> int:
	var total := 0 # 钱包使用的统一金币单位。
	for denomination: String in FIRST_CLEAR_COIN_VALUES: # 只统计三种已知面额。
		total += int(coins.get(denomination, 0)) * int(FIRST_CLEAR_COIN_VALUES[denomination])
	return total

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
