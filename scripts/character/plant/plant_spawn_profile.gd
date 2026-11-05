## An immutable battle spawn recipe, created by the owning game mode.
## Generic planting and transformations consume it without inspecting research.
extends RefCounted
class_name PlantSpawnProfile

var _snapshot: Dictionary
var _modifier: PlantSpawnModifier

func _init(snapshot: Dictionary, modifier: PlantSpawnModifier) -> void:
	assert(not snapshot.is_empty() and modifier != null)
	_snapshot = snapshot.duplicate(true)
	_modifier = modifier

func snapshot() -> Dictionary:
	return _snapshot.duplicate(true)

func apply(plant: Plant000Base) -> bool:
	return _modifier.apply(plant)
