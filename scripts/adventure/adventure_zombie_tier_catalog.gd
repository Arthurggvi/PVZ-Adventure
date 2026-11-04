## 冒险僵尸等阶的单一数据源。只改变新实例；原版/展示模式完全不处理。
extends RefCounted
class_name AdventureZombieTierCatalog

## 首版平衡参数：战力倍率独立于生命/攻击倍率，按关卡预算决定能否入场。
const DEFINITIONS: Dictionary = {
	&"base": {"hp": 1.0, "armor": 1.0, "attack": 1.0, "threat": 1.0,
		"tint": Color.WHITE},
	&"veteran": {"hp": 1.5, "armor": 1.5, "attack": 1.2, "threat": 1.75,
		"tint": Color(0.78, 0.9, 1.0)},
	&"elite": {"hp": 2.0, "armor": 2.0, "attack": 1.5, "threat": 2.5,
		"tint": Color(1.0, 0.78, 0.85)}
}

static func tier_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for id: StringName in DEFINITIONS:
		result.append(id)
	return result

static func threat_costs() -> Dictionary:
	var result: Dictionary = {}
	for id: StringName in DEFINITIONS:
		result[id] = float(DEFINITIONS[id]["threat"])
	return result

static func get_tier(id: StringName) -> Dictionary:
	return DEFINITIONS[id].duplicate(true) if DEFINITIONS.has(id) else {}

## 在 add_child() 前调用：Component 的 _ready 会基于等阶后的 max_hp 自行计算 UI 和部位阈值。
## 普通啃咬攻击按等阶强化；特殊动作伤害未统一建模，不擅自改变技能逻辑。
static func bind(zombie: Zombie000Base, id: StringName) -> bool:
	if zombie == null or zombie.is_inside_tree() or zombie.adventure_tier_id != &"":
		return false
	var tier: Dictionary = get_tier(id)
	if tier.is_empty():
		return false
	var hp: HpComponentZombie = zombie.get_node_or_null("HpComponent") as HpComponentZombie
	if hp == null:
		return false
	var attack: AttackComponentZombieNorm = zombie.get_node_or_null("AttackComponent") as AttackComponentZombieNorm
	hp.max_hp = _scaled(hp.max_hp, float(tier["hp"]))
	hp.max_hp_armor1 = _scaled(hp.max_hp_armor1, float(tier["armor"]))
	hp.max_hp_armor2 = _scaled(hp.max_hp_armor2, float(tier["armor"]))
	if attack != null:
		attack.init_attack_value_per_min = _scaled(attack.init_attack_value_per_min, float(tier["attack"]))
	zombie.adventure_tier_id = id
	zombie.modulate = tier["tint"]
	return true

static func _scaled(value: int, factor: float) -> int:
	return maxi(1, roundi(float(value) * factor)) if value > 0 else 0
