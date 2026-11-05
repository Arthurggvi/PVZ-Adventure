## Pure combat progression values for permanent plant card stars.
## The battle adapter applies these to one frozen instance; no save/UI dependencies.
extends RefCounted
class_name AdventurePlantGrowthCatalog

const MAX_STARS := PlantCardInstance.MAX_STARS
const ATTACK_PER_STAR := 1.20
const HEALTH_PER_STAR := 1.12
const SUN_RATE_PER_STAR := 0.015
const SUN_RATE_CAP := 0.15

static func modifiers(stars: int) -> Dictionary:
	if stars < 1 or stars > MAX_STARS:
		return {}
	return {
		"damage": {"flat": 0.0, "percent": pow(ATTACK_PER_STAR, stars) - 1.0},
		"max_health": {"flat": 0.0, "percent": pow(HEALTH_PER_STAR, stars) - 1.0},
		"sun_production_rate": {
			"flat": 0.0, "percent": minf(SUN_RATE_CAP, SUN_RATE_PER_STAR * float(stars))
		}
	}
