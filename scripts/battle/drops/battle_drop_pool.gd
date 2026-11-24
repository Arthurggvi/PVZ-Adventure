## 通用掉落池：先判定普通或额外材料掉落，再按候选条目权重抽一个具体条目。
## 池子只描述“掉什么、各占多少权重”，与掉落物的表现、入账方式完全解耦。
extends RefCounted
class_name BattleDropPool

## 未显式指定时使用的单次掉落概率。
const DEFAULT_CHANCE := 0.1

## 单次掉落判定使用的概率，取值 [0, 1]。
var chance := DEFAULT_CHANCE
## 可选条目，每项形如 {"id": StringName, "weight": int, "quantity": int}。
var entries: Array[Dictionary] = []
## 本池中属于材料分类的物品 ID；额外掉落只使用这些候选。
var _material_ids: Dictionary[StringName, bool] = {}

## 从阶段掉落表构造材料池；只收集材料与消耗品，配方与钥匙仍走战后结算。
static func from_phase(phase: StagePhaseDefinition) -> BattleDropPool:
	if phase == null or phase.drop_table == null:
		return BattleDropPool.new()
	return from_drop_table(phase.drop_table)

## 从任意掉落表构造材料池；同一物品的多条配置按权重累加、数量取最大。
static func from_drop_table(table: DropTable) -> BattleDropPool:
	var pool := BattleDropPool.new()
	if table == null:
		return pool
	for entry in table.entries:
		if entry == null or entry.asset_kind != DropEntryDefinition.AssetKind.ITEM:
			continue
		var definition := ItemRegistry.get_item_definition(entry.asset_id)
		var category := str(definition.get("category", ""))
		if category != "material" and category != "consumable":
			continue
		var weight := 1
		if entry.rule == DropEntryDefinition.Rule.WEIGHTED:
			weight = maxi(1, entry.weight)
		pool.add(entry.asset_id, weight, maxi(1, entry.quantity_min))
		if category == "material":
			pool._material_ids[entry.asset_id] = true
	return pool

## 追加一个可选条目；重复条目按权重累加、数量取最大值。
func add(item_id: StringName, weight: int, quantity: int) -> void:
	if item_id.is_empty():
		return
	for entry in entries:
		if entry.id == item_id:
			entry.weight = int(entry.weight) + maxi(0, weight)
			entry.quantity = maxi(int(entry.quantity), maxi(1, quantity))
			return
	entries.append({"id": item_id, "weight": maxi(0, weight), "quantity": maxi(1, quantity)})

## 池中是否没有任何可选条目。
func is_empty() -> bool:
	return entries.is_empty()

## 全部条目权重之和；为空时返回 0。
func total_weight() -> int:
	var total := 0
	for entry in entries:
		total += int(entry.weight)
	return total

## 抽取一次：未命中返回空字典，命中则返回对应条目字典。
## [param rng] 留空时使用全局随机数。[param material_multiplier] 仅从未掉落的概率中增加材料概率，每次仍至多掉一份。
func roll(rng: RandomNumberGenerator = null, material_multiplier: float = 1.0) -> Dictionary:
	if entries.is_empty():
		return {}
	var chance_roll: float = rng.randf() if rng != null else randf() # 普通掉落和材料加成使用同一次概率判定。
	var use_material_bonus: bool = chance_roll >= chance # 普通掉落未命中时才进入材料加成区间。
	if use_material_bonus and material_multiplier <= 1.0:
		return {}
	var candidates: Array[Dictionary] = entries # 普通掉落保留完整候选池。
	var total: int = total_weight() # 普通掉落池的总权重，也是材料占比的分母。
	if total <= 0:
		return {}
	if use_material_bonus:
		candidates = []
		var material_weight := 0 # 额外抽取限定为材料，保留材料之间的权重比例。
		for entry: Dictionary in entries: # 过滤原池条目，保留它们的顺序。
			if _material_ids.has(entry.id):
				candidates.append(entry)
				material_weight += int(entry.weight)
		if material_weight <= 0:
			return {}
		var material_chance: float = chance * float(material_weight) / float(total) # 原本独立于消耗品的材料总概率。
		var boosted_threshold: float = minf(1.0, chance + material_chance * (material_multiplier - 1.0)) # 新增材料概率占用原先的空掉落区间。
		if chance_roll >= boosted_threshold and boosted_threshold < 1.0:
			return {}
		total = material_weight
	var pick: int = rng.randi_range(1, total) if rng != null else randi_range(1, total) # 在当前候选中抽取整数权重位置。
	var accumulated := 0 # 按顺序累计权重，找到落点对应的条目。
	for entry: Dictionary in candidates: # 普通池与材料池使用同样的权重选择。
		accumulated += int(entry.weight)
		if pick <= accumulated:
			return entry
	return candidates.back()
