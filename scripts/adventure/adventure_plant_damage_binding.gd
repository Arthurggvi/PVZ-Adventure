## Compatibility adapter between the shared star-growth model and existing
## vanilla plant damage sources. Called once for each adventure combat instance.
## New direct attacks should expose an integer attack_value.
extends RefCounted
class_name AdventurePlantDamageBinding

const DIRECT_DAMAGE_PROPERTIES := [&"attack_value", &"eat_attack", &"boss_attack_value"]

static func bind(plant: Plant000Base, multiplier: float) -> void:
	if plant == null or not is_finite(multiplier) or multiplier <= 0.0:
		return
	var properties: Dictionary = {}
	for descriptor: Dictionary in plant.get_property_list():
		properties[StringName(descriptor.name)] = int(descriptor.type)
	for key: StringName in DIRECT_DAMAGE_PROPERTIES:
		if not properties.has(key):
			continue
		if int(properties[key]) != TYPE_INT:
			push_error("Invalid plant damage property type: " + str(key))
			continue
		var source: int = int(plant.get(key))
		plant.set(key, maxi(0, roundi(float(source) * multiplier)))
	var bomb: BombComponentBase = plant.get_node_or_null("BombComponent") as BombComponentBase
	if bomb != null:
		bomb.apply_damage_multiplier(multiplier)
