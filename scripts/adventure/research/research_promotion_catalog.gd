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
		]},
	"promotion_sunflower_stellar": {
		"title": "恒星", "summary": "每次产阳光后，下次额外产量+15，累计最多+100", "plant_type": 2, "tier": 3,
		"effects": [{"kind": "sun_growth", "step": 15, "cap": 100}]},
	"promotion_sunflower_resonance": {
		"title": "共鸣", "summary": "付费种植后立刻恢复本卡冷却、下次种植免费；免费种植不再触发", "plant_type": 2, "tier": 3,
		"effects": [{"kind": "card_resonance"}]},
	"promotion_sunflower_holy_war": {
		"title": "圣战", "summary": "自身同排前后相邻一格的植物伤害+100%、受到伤害−50%", "plant_type": 2, "tier": 4,
		"effects": [{"kind": "adjacent_aura", "damage_bonus": 1.0, "damage_reduction": 0.5}]},
	"promotion_sunflower_flower_field": {
		"title": "花田", "summary": "每次种植本向日葵，使其他植物卡费用−25（可叠加，最低0）；使用各卡后重置该卡折扣", "plant_type": 2, "tier": 4,
		"effects": [{"kind": "deck_cost_discount", "step": 25}]}
}

static func definition(id: String) -> Dictionary:
	return BOOKS.get(id, {}).duplicate(true)

## A rank is a historical choice, independent of the card's current star count.
## Star thresholds are checked only when buying the next promotion.
static func is_valid_chain(card: PlantCardInstance) -> bool:
	if card == null:
		return false
	var gap := false
	for tier: int in range(1, 5):
		var book_id := card.get_promotion(tier)
		if book_id.is_empty():
			gap = true
			continue
		var book: Dictionary = definition(book_id)
		if gap or book.is_empty() or int(book.get("tier", 0)) != tier \
				or int(book.get("plant_type", 0)) != card.plant_type:
			return false
	return true

static func next_tier(card: PlantCardInstance) -> int:
	if not is_valid_chain(card):
		return 0
	for tier: int in range(1, 5):
		if card.get_promotion(tier).is_empty():
			return tier
	return 0

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
	if not is_valid_chain(card):
		return {"stats": stats, "events": events}
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
