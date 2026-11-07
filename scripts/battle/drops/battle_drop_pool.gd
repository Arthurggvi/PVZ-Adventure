## 通用掉落池：先按 [member chance] 判定是否掉落，再按条目权重抽一个具体条目。
## 池子只描述“掉什么、各占多少权重”，与掉落物的表现、入账方式完全解耦。
extends RefCounted
class_name BattleDropPool

## 未显式指定时使用的单次掉落概率。
const DEFAULT_CHANCE := 0.1

## 单次掉落判定使用的概率，取值 [0, 1]。
var chance := DEFAULT_CHANCE
## 可选条目，每项形如 {"id": StringName, "weight": int, "quantity": int}。
var entries: Array[Dictionary] = []

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

## 抽取一次：未命中几率返回空字典，命中则返回对应条目字典。
## [param rng] 留空时使用全局随机数。
func roll(rng: RandomNumberGenerator = null) -> Dictionary:
	if entries.is_empty():
		return {}
	var hit := rng.randf() < chance if rng != null else randf() < chance
	if not hit:
		return {}
	var total := total_weight()
	if total <= 0:
		return {}
	var pick := rng.randi_range(1, total) if rng != null else randi_range(1, total)
	var accumulated := 0
	for entry in entries:
		accumulated += int(entry.weight)
		if pick <= accumulated:
			return entry
	return entries.back()
