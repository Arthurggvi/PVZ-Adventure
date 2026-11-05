## Apply declarative promotion-book effects only to frozen adventure card snapshots.
## Legacy cards have empty battle data and remain unmodified.
extends RefCounted
class_name AdventureResearchBattleEffects

const Promotions = preload("res://scripts/adventure/research/research_promotion_catalog.gd")
const Enhancement = preload("res://scripts/adventure/research/research_enhancement_rules.gd")

static func _record(snapshot: Dictionary) -> PlantCardInstance:
	if snapshot.is_empty():
		return null
	return PlantCardInstance.from_dict(snapshot)

static func _stats(record: PlantCardInstance) -> Dictionary:
	var result: Dictionary = Promotions.effects(record).stats
	var from_stars: Dictionary = Enhancement.stat_modifiers(record.stars)
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
	if record == null:
		return
	var modifiers: Dictionary = _stats(record)
	if modifiers.has("max_health"):
		var new_max: int = maxi(1, roundi(Promotions.resolve_stat(
			float(plant.hp_component.max_hp), modifiers.max_health)))
		plant.hp_component.max_hp = new_max
		plant.hp_component.curr_hp = new_max
	var component: CreateSunComponent = plant.get_node_or_null("CreateSunComponent")
	if component == null:
		return
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
