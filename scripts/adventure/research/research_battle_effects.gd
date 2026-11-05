## Apply promotion and star-growth effects to frozen battle card snapshots.
## Ordinary modes have no snapshot and keep all original combat values.
extends RefCounted
class_name AdventureResearchBattleEffects

const Promotions = preload("res://scripts/adventure/research/research_promotion_catalog.gd")
const Growth = preload("res://scripts/adventure/adventure_plant_growth_catalog.gd")
const DamageBinding = preload("res://scripts/adventure/adventure_plant_damage_binding.gd")

static func _record(snapshot: Dictionary) -> PlantCardInstance:
	if snapshot.is_empty():
		return null
	return PlantCardInstance.from_dict(snapshot)

static func _stats(record: PlantCardInstance) -> Dictionary:
	var result: Dictionary = Promotions.effects(record).stats
	var from_stars: Dictionary = Growth.modifiers(record.stars)
	for stat: String in from_stars:
		var addition: Dictionary = from_stars[stat]
		var entry: Dictionary = result.get(stat, {"flat": 0.0, "percent": 0.0})
		entry.flat += float(addition.get("flat", 0.0))
		entry.percent += float(addition.get("percent", 0.0))
		result[stat] = entry
	return result

static func apply_card(card: Variant) -> void:
	var record := _record(card.battle_card_data)
	if record == null or card.research_applied_uid == record.uid:
		return
	var modifiers: Dictionary = _stats(record)
	card.research_applied_uid = record.uid
	if modifiers.has("sun_cost"):
		card.sun_cost = roundi(Promotions.resolve_stat(card.sun_cost, modifiers.sun_cost))
	if modifiers.has("cooldown"):
		card.cool_time = Promotions.resolve_stat(card.cool_time, modifiers.cooldown)

static func apply_plant(plant: Variant) -> void:
	var record := _record(plant.battle_card_data)
	if record == null or plant.research_effects_applied:
		return
	plant.research_effects_applied = true
	var modifiers: Dictionary = _stats(record)
	if modifiers.has("damage"):
		plant.battle_damage_multiplier = maxf(0.0, 1.0 + float(modifiers.damage.get("percent", 0.0)))
		DamageBinding.bind(plant, plant.battle_damage_multiplier)
	if modifiers.has("max_health"):
		var new_max: int = maxi(1, roundi(Promotions.resolve_stat(
			float(plant.hp_component.max_hp), modifiers.max_health)))
		plant.hp_component.max_hp = new_max
		plant.hp_component.curr_hp = new_max
	var component: CreateSunComponent = plant.get_node_or_null("CreateSunComponent")
	if component == null:
		return
	# Only subsequent production intervals change; first sun, sun amount, cost
	# and card cooldown are untouched. Ten-star growth is capped at +15%.
	if modifiers.has("sun_production_rate"):
		var bonus: float = clampf(float(modifiers.sun_production_rate.get("percent", 0.0)), 0.0, 0.15)
		component.create_time_range_other /= 1.0 + bonus
	if modifiers.has("sun_value"):
		component.change_sun_value(roundi(Promotions.resolve_stat(
			float(component.sun_value), modifiers.sun_value)))
	var resolved: Dictionary = Promotions.effects(record)
	for event: Dictionary in resolved.events:
		match str(event.get("kind", "")):
			"sun_production":
				component.extra_small_sun_min += int(event.get("extra_small_sun_min", 0))
				component.extra_small_sun_max += int(event.get("extra_small_sun_max", 0))
			"on_death":
				var reward: int = int(event.get("drop_sun", 0))
				if reward > 0:
					plant.signal_character_death.connect(
						func(): component.spawn_specific_sun(reward), CONNECT_ONE_SHOT)
