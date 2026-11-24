## Grid-distance query for one-off zombie abilities; no spatial logic in species scripts.
extends RefCounted
class_name AdventureZombieTierNeighbors

## [param manager] 提供活体分行登记。[param source] 周围 [param radius_cells] 条行内，
## 使用当前横坐标与 [param cell_width] 世界像素格宽判断距离。
static func nearby_allies(manager: ZombieManager, source: Zombie000Base,
		cell_width: float, radius_cells: int) -> Array[Zombie000Base]:
	if manager.all_zombies_2d.is_empty():
		return allied_in_range(source, manager.all_zombies_1d, cell_width, radius_cells)
	var result: Array[Zombie000Base] = [] # 本次有效盟友，不包含来源。
	if not is_instance_valid(source) or source.is_hypno or source.is_death \
			or source.lane < 0 or cell_width <= 0.0 or radius_cells <= 0:
		return result
	var source_x: float = source.global_position.x # 整次查询复用来源横坐标。
	var reach: float = cell_width * radius_cells # 横向世界像素范围。
	var last: int = mini(manager.all_zombies_2d.size() - 1, source.lane + radius_cells) # 最后一条候选行。
	for lane: int in range(maxi(0, source.lane - radius_cells), last + 1): # 只查看可能命中的行。
		for ally: Zombie000Base in manager.all_zombies_2d[lane]: # 分行登记中的敌方候选。
			if is_instance_valid(ally) and ally != source and not ally.is_queued_for_deletion() \
					and not ally.is_death and not ally.is_hypno \
					and absf(ally.global_position.x - source_x) <= reach:
				result.append(ally)
	return result

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
