## 装备解析后的数值和能力快照；战斗与奖励消费效果，不识别具体装备 ID。
extends RefCounted
class_name PlayerEffects

## 经验倍率，仅用于显式经验奖励来源。
var experience_multiplier: float = 1.0
## 随机材料/消耗品数量倍率。
var loot_multiplier: int = 1
## 随机材料/消耗品概率相对倍率。
var drop_chance_multiplier: float = 1.0
## 战场金币价值倍率。
var coin_multiplier: float = 1.0
## 阳光收集能力的到期 Unix 秒；-1 表示未装配，0 表示永久。
var _sun_deadline: int = -1
## 掉落收集能力的到期 Unix 秒；-1 表示未装配，0 表示永久。
var _drop_deadline: int = -1
## 装备定义副本与绝对到期时间，出战后不再读取玩家背包。
var _frozen_items: Array[Dictionary] = []

## 从 [param state] 生成独立效果；同类倍率乘算，槽位约束控制叠加来源。
static func resolve(state: PlayerEquipmentState) -> PlayerEffects:
	var result := PlayerEffects.new() # 未装备时所有数值保持中性。
	var now: int = int(Time.get_unix_time_from_system()) # 已到期的实例不进入出战快照。
	for key: String in state.equipped: # 只解析已装配的持有实例。
		var uid: String = state.equipped[key] # 从实例读取固定期限。
		if state.is_expired(uid, now):
			continue
		var item: EquipmentDefinition = EquipmentCatalog.definition(state.owned.get(uid, "")) # 不读取 UI。
		if item != null:
			result._frozen_items.append({"definition": item, "deadline": state.expires_at.get(uid, 0)})
	result._apply_equipment(now)
	return result

## 按 [param now] 重算快照中仍有效的效果，在全新结果上调用。
func _apply_equipment(now: int) -> void:
	for entry: Dictionary in _frozen_items: # 固定装备身份和数值，只重验到期时间。
		var deadline: int = entry.deadline # 0 表示永久。
		if deadline > 0 and now >= deadline:
			continue
		var item: EquipmentDefinition = entry.definition # 定义是出战时的独立副本。
		experience_multiplier *= item.experience_multiplier
		loot_multiplier *= item.loot_multiplier
		drop_chance_multiplier *= item.drop_chance_multiplier
		coin_multiplier *= item.coin_multiplier
		if item.slot == EquipmentDefinition.Slot.SUN_COLLECTOR:
			_sun_deadline = deadline
		elif item.slot == EquipmentDefinition.Slot.DROP_COLLECTOR:
			_drop_deadline = deadline

## [param sun] 区分两类收集能力；每次判定时检查实时时钟，局中到期立即停止自动拾取。
func can_collect(sun: bool) -> bool:
	var deadline: int = _sun_deadline if sun else _drop_deadline # 出战时已冻结装备身份和到期秒。
	return deadline == 0 or deadline > int(Time.get_unix_time_from_system())

## 返回当前有效效果的副本，局中到期的倍率也在下一次取用时失效。
func copy() -> PlayerEffects:
	var result := PlayerEffects.new() # 从中性倍率重算，避免重复叠乘。
	result._frozen_items.assign(_frozen_items)
	result._apply_equipment(int(Time.get_unix_time_from_system()))
	return result

## [param item_id] 是否属于可加成的普通随机掉落；钥匙、配方与装备不进入此规则。
static func is_random_loot(item_id: String) -> bool:
	return str(ItemRegistry.get_item_definition(item_id).get("category", "")) in ["material", "consumable"]

## 对 [param amount] 应用 [param multiplier] 并四舍五入；超出 JSON 安全整数返回 -1。
static func scale_amount(amount: int, multiplier: float) -> int:
	if amount < 0 or amount > PlantCardInstance.MAX_JSON_INTEGER or not is_finite(multiplier) or multiplier < 1.0:
		return -1
	if multiplier == 1.0:
		return amount
	var scaled: float = round(float(amount) * multiplier) # 先验证范围，不能让 int 转换吞掉溢出。
	return int(scaled) if is_finite(scaled) and scaled < float(PlantCardInstance.MAX_JSON_INTEGER) else -1
