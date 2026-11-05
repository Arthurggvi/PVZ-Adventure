## Typed pre-tree plant spawn configuration. Keeps generic planting independent
## from adventure cards, research rules and other game modes.
extends RefCounted
class_name PlantSpawnModifier

func apply(_plant: Plant000Base) -> bool:
	return false

## Optional card presentation values calculated from original registry values.
func card_stats(_snapshot: Dictionary, base_sun_cost: int, base_cooldown: float) -> Dictionary:
	return {"sun_cost": base_sun_cost, "cooldown": base_cooldown}
