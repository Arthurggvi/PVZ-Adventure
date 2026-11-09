## Grid-distance query for one-off zombie abilities; no spatial logic in species scripts.
extends RefCounted
class_name AdventureZombieTierNeighbors

## One cell = one lane vertically and one actual plant-cell width horizontally.
## Includes other zombies in the source cell; excludes the source and charmed foes.
static func allied_in_range(source: Zombie000Base, candidates: Array[Zombie000Base],
		cell_width: float, radius_cells: int) -> Array[Zombie000Base]:
	var result: Array[Zombie000Base] = []
	if not is_instance_valid(source) or radius_cells <= 0 or cell_width <= 0.0 			or source.lane < 0 or source.is_hypno or source.is_death:
		return result
	for candidate: Zombie000Base in candidates:
		if not is_instance_valid(candidate) or candidate == source 				or candidate.is_death or candidate.is_hypno 				or candidate.is_queued_for_deletion() or candidate.lane < 0:
			continue
		if absi(candidate.lane - source.lane) <= radius_cells 				and absf(candidate.global_position.x - source.global_position.x) 				<= cell_width * float(radius_cells):
			result.append(candidate)
	return result
