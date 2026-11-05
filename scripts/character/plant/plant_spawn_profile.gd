## An immutable battle spawn recipe, created by the owning game mode.
## Generic planting and transformations consume it without inspecting research.
extends RefCounted
class_name PlantSpawnProfile

var _snapshot: Dictionary
var _modifier: PlantSpawnModifier

static func create(snapshot: Dictionary, modifier: PlantSpawnModifier) -> PlantSpawnProfile:
	if snapshot.is_empty() or modifier == null:
		return null
	return PlantSpawnProfile.new(snapshot, modifier)

func _init(snapshot: Dictionary, modifier: PlantSpawnModifier) -> void:
	if snapshot.is_empty() or modifier == null:
		push_error("PlantSpawnProfile requires a snapshot and modifier")
		return
	_snapshot = snapshot.duplicate(true)
	_modifier = modifier

func is_valid_profile() -> bool:
	return _modifier != null and not _snapshot.is_empty()

func snapshot() -> Dictionary:
	return _snapshot.duplicate(true) if is_valid_profile() else {}

func card_stats(base_sun_cost: int, base_cooldown: float) -> Dictionary:
	if not is_valid_profile():
		return {}
	return _modifier.card_stats(_snapshot, base_sun_cost, base_cooldown)

func apply(plant: Plant000Base) -> bool:
	return is_valid_profile() and _modifier.apply(plant)
