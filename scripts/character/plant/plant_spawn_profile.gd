## An immutable battle spawn recipe, created by the owning game mode.
## Generic planting and transformations consume it without inspecting research.
extends RefCounted
class_name PlantSpawnProfile

var _snapshot: Dictionary = {}
var _modifier: PlantSpawnModifier

static func create(card_snapshot: Dictionary, modifier: PlantSpawnModifier) -> PlantSpawnProfile:
	if modifier == null or not _has_plant_identity(card_snapshot):
		return null
	return PlantSpawnProfile.new(card_snapshot, modifier)

static func _has_plant_identity(card_snapshot: Dictionary) -> bool:
	var plant_id: Variant = card_snapshot.get("plant_type", null)
	return (
		not card_snapshot.is_empty()
		and (typeof(plant_id) == TYPE_INT or typeof(plant_id) == TYPE_FLOAT)
		and int(plant_id) > 0
		and float(plant_id) == float(int(plant_id))
	)

func _init(card_snapshot: Dictionary, modifier: PlantSpawnModifier) -> void:
	if modifier == null or not _has_plant_identity(card_snapshot):
		push_error("PlantSpawnProfile requires a valid species and modifier")
		return
	_snapshot = card_snapshot.duplicate(true)
	_modifier = modifier

func is_valid_profile() -> bool:
	return _modifier != null and _has_plant_identity(_snapshot)

func matches_plant_type(plant_type: int) -> bool:
	return is_valid_profile() and int(_snapshot["plant_type"]) == plant_type

func snapshot() -> Dictionary:
	return _snapshot.duplicate(true) if is_valid_profile() else {}

func card_stats(base_sun_cost: int, base_cooldown: float) -> Dictionary:
	if not is_valid_profile():
		return {}
	return _modifier.card_stats(_snapshot.duplicate(true), base_sun_cost, base_cooldown)

func apply(plant: Plant000Base, plant_type: int) -> bool:
	if plant == null or not matches_plant_type(plant_type):
		return false
	if plant.spawn_species_id() != plant_type:
		return false
	if plant.spawn_attributes_applied:
		return false
	if not _modifier.apply(plant, _snapshot.duplicate(true)):
		return false
	plant.spawn_attributes_applied = true
	return true
