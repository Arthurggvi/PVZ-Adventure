## Apply promotion and star-growth effects to frozen battle card snapshots.
## Ordinary modes have no snapshot and keep all original combat values.
extends PlantSpawnModifier
class_name AdventureResearchBattleEffects

const Promotions = preload("res://scripts/adventure/research/research_promotion_catalog.gd")
const Growth = preload("res://scripts/adventure/adventure_plant_growth_catalog.gd")

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

func card_stats(snapshot: Dictionary, base_sun_cost: int, base_cooldown: float) -> Dictionary:
	var record := _record(snapshot)
	if record == null:
		return {}
	var modifiers: Dictionary = _stats(record)
	return {
		"sun_cost": roundi(Promotions.resolve_stat(float(base_sun_cost),
			modifiers.get("sun_cost", {}))),
		"cooldown": Promotions.resolve_stat(base_cooldown,
			modifiers.get("cooldown", {}))
	}

func apply(plant: Plant000Base, snapshot: Dictionary) -> bool:
	var record := _record(snapshot)
	if record == null:
		return false
	var modifiers: Dictionary = _stats(record)
	if modifiers.has("damage"):
		plant.battle_damage_multiplier = maxf(0.0, 1.0 + float(modifiers.damage.get("percent", 0.0)))
	if modifiers.has("max_health"):
		var health: HpComponent = plant.get_node_or_null("HpComponent") as HpComponent
		if health == null:
			push_error("Adventure plant has no HpComponent")
			return false
		var new_max: int = maxi(1, roundi(Promotions.resolve_stat(
			float(health.max_hp), modifiers.max_health)))
		var stages: HpStageChangeComponent = plant.get_node_or_null(
			"HpStageChangeComponent") as HpStageChangeComponent
		if stages != null:
			stages.set_spawn_max_health(new_max)
		else:
			health.set_spawn_max_health(new_max)
	var component: CreateSunComponent = plant.get_node_or_null("CreateSunComponent")
	if component == null:
		return true
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
	return true
