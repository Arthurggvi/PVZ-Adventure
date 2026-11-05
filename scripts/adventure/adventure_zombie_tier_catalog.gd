## 冒险僵尸等阶的单一数据源。只改变新实例；原版/展示模式完全不处理。
extends RefCounted
class_name AdventureZombieTierCatalog

## Stable IDs for existing stage resources. Tiers 1–5 scale the body and both
## armor pools together; ordinary biting uses a separate multiplier. Spawn threat
## is a wave-budget cost, not a second combat multiplier.
const DEFINITIONS: Dictionary = {
	&"base": {"hp": 1.0, "armor": 1.0, "attack": 1.0, "threat": 1.0,
		"tint": Color.WHITE},
	&"veteran": {"hp": 1.5, "armor": 1.5, "attack": 1.2, "threat": 1.75,
		"tint": Color(0.78, 0.9, 1.0)},
	&"elite": {"hp": 3.0, "armor": 3.0, "attack": 2.0, "threat": 3.5,
		"tint": Color(1.0, 0.78, 0.85)},
	&"tier4": {"hp": 5.0, "armor": 5.0, "attack": 3.0, "threat": 6.0,
		"tint": Color(0.9, 0.72, 1.0)},
	&"tier5": {"hp": 10.0, "armor": 10.0, "attack": 5.0, "threat": 12.0,
		"tint": Color(1.0, 0.65, 0.5)}
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

## Pure numeric rounding shared with the battle-time tier binding adapter.
static func scaled(value: int, factor: float) -> int:
	return maxi(1, roundi(float(value) * factor)) if value > 0 else 0
