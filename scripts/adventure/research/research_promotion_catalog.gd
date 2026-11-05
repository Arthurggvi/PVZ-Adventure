## Promotion books are authoritative skill definitions; one irreversible choice per tier.
extends RefCounted
class_name AdventurePromotionCatalog

const COST := 5000
const REQUIREMENTS := [5, 7, 9, 10]
const BOOKS: Dictionary = {
	"promotion_sunflower_light_conversion": {
		"title": "光能转化", "summary": "阳光费用−25，生命+50%", "plant_type": 2, "tier": 1,
		"effects": [
			{"kind": "stat", "stat": "sun_cost", "flat": -25.0},
			{"kind": "stat", "stat": "max_health", "percent": 0.5}
		]},
	"promotion_sunflower_photosynthesis": {
		"title": "光合作用", "summary": "每次额外生产1–2个小阳光", "plant_type": 2, "tier": 1,
		"effects": [{"kind": "sun_production", "extra_small_sun_min": 1,
			"extra_small_sun_max": 2}]},
	"promotion_sunflower_radiance": {
		"title": "辉光", "summary": "自身生产的阳光价值+100%", "plant_type": 2, "tier": 2,
		"effects": [{"kind": "stat", "stat": "sun_value", "percent": 1.0}]},
	"promotion_sunflower_synergy": {
		"title": "协同", "summary": "冷却−30%；生命+300%；死亡时掉落50阳光", "plant_type": 2, "tier": 2,
		"effects": [
			{"kind": "stat", "stat": "cooldown", "percent": -0.3},
			{"kind": "stat", "stat": "max_health", "percent": 3.0},
			{"kind": "on_death", "drop_sun": 50}
		]}
}

static func definition(id: String) -> Dictionary:
	return BOOKS.get(id, {}).duplicate(true)

static func next_tier(card: PlantCardInstance) -> int:
	if card == null:
		return 0
	var next := 0
	for tier: int in range(1, 5):
		var filled: bool = not card.get_promotion(tier).is_empty()
		if not filled and next == 0:
			next = tier
		elif filled and next != 0:
			return 0 # A higher tier without its prerequisite is invalid.
		if filled:
			var existing: Dictionary = definition(card.get_promotion(tier))
			if existing.is_empty() or int(existing.tier) != tier \
					or int(existing.plant_type) != card.plant_type:
				return 0
	return next

static func options(card: PlantCardInstance) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var tier := next_tier(card)
	if tier == 0:
		return result
	for id: String in BOOKS:
		var book: Dictionary = BOOKS[id]
		if int(book.tier) == tier and int(book.plant_type) == card.plant_type:
			var entry := definition(id)
			entry["id"] = id
			result.append(entry)
	return result

## Cumulative flat and percentage modifiers are additive against base stats.
## Event effects are declared separately for gameplay feature consumers.
static func effects(card: PlantCardInstance) -> Dictionary:
	var stats: Dictionary = {}
	var events: Array[Dictionary] = []
	for tier: int in range(1, 5):
		var id := card.get_promotion(tier)
		if not BOOKS.has(id):
			continue
		for effect: Dictionary in BOOKS[id].effects:
			if effect.kind != "stat":
				events.append(effect.duplicate(true))
				continue
			var stat: String = effect.stat
			var aggregate: Dictionary = stats.get(stat, {"flat": 0.0, "percent": 0.0})
			aggregate.flat += float(effect.get("flat", 0.0))
			aggregate.percent += float(effect.get("percent", 0.0))
			stats[stat] = aggregate
	return {"stats": stats, "events": events}

static func resolve_stat(base: float, modifier: Dictionary) -> float:
	return maxf(0.0, base * (1.0 + float(modifier.get("percent", 0.0)))
		+ float(modifier.get("flat", 0.0)))
