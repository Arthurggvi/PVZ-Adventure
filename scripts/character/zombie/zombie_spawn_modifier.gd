## Typed pre-tree spawn contract. World-specific rules implement this without
## coupling ZombieManager to adventure level, wave or tier catalogs.
extends RefCounted
class_name ZombieSpawnModifier

func apply(_zombie: Zombie000Base) -> bool:
	return false
