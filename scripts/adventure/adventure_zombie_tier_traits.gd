## Per-species adventure abilities. Generic tier stats live in AdventureZombieTierCatalog.
## Only explicitly registered species/tier pairs receive combat traits.
extends RefCounted
class_name AdventureZombieTierTraits

const DEFINITIONS: Dictionary = {
	CharacterRegistry.ZombieType.Z003Cone: {
		&"elite": [
			{"trigger": &"armor1_lost", "effect": &"timed_speed_boost",
				"multiplier": 1.2, "duration": 0.5, "radius_cells": 0},
		],
		&"tier4": [
			{"trigger": &"armor1_lost", "effect": &"timed_speed_boost",
				"multiplier": 1.5, "duration": 0.8, "radius_cells": 0},
		],
		&"tier5": [
			{"trigger": &"armor1_lost", "effect": &"timed_speed_boost",
				"multiplier": 1.5, "duration": 0.8, "radius_cells": 1},
		],
	},
}

static func for_spawn(zombie_type: int, tier_id: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var species: Dictionary = DEFINITIONS.get(zombie_type, {})
	for rule: Dictionary in species.get(tier_id, []):
		result.append(rule.duplicate(true))
	return result
