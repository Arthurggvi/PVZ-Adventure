## Typed pre-tree plant spawn configuration. Keeps generic planting independent
## from adventure cards, research rules and other game modes.
extends RefCounted
class_name PlantSpawnModifier

func apply(_plant: Plant000Base) -> bool:
	return false
