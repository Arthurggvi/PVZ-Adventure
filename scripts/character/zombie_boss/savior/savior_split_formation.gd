## 半血分裂的队形与提交。教堂使用固定两格，其他棋盘依实际出怪行和地块选择替代落点。
extends RefCounted

## 按镜头出场顺序指定首选的行、列，均从零计数。
const PREFERRED: Array[Vector2i] = [Vector2i(1, 5), Vector2i(3, 5)]

## [param original] 与 [param game] 属于同一战斗；[param prepare_clone] 给树外分身分配行，[param commit_origin] 只在两名增援都入树后执行。
## 返回完整队形中的两名分身；棋盘或工厂未能提供两人时返回空数组，由本体带现有生命完成二阶段。
static func spawn(original: ZB000Base, game: MainGameManager, prepare_clone: Callable,
		commit_origin: Callable) -> Array[ZB000Base]:
	var manager: ZombieManager = game.zombie_manager # 所有增援仍经普通僵王的注册、计数及退场管线。
	var cells: Array[PlantCell] = _choose_cells(original, game.board, manager) # 先确定两名独立落点，再申请任何实体。
	if cells.is_empty():
		push_warning("救主分裂：棋盘缺少两个独立有效落点，按当前生命继续单体二阶段。")
		return []
	var positions: Array[Vector2] = [] # 公共工厂使用僵王容器的局部坐标。
	for cell: PlantCell in cells: # 真实地板的脚点同时服务判定与镜头。
		var foot: Vector2 = cell.get_slot_anchor_global_position(CharacterRegistry.PlacePlantInCell.Norm) # 采用格子配置的锚点。
		positions.append(manager.zombie_boss_root.to_local(foot))
	var prepare := func(member: ZB000Base, index: int) -> bool: # 每名分身在入树前获得实际行和同组身份。
		return prepare_clone.call(member, cells[index].row_col.x)
	var members: Array[ZB000Base] = manager.try_create_boss_reinforcements(
		CharacterRegistry.ZombieBossType.ZB005Savior, positions, prepare, commit_origin)
	if members.is_empty():
		push_warning("救主分裂：未能登记完整的两名分身，按当前生命继续单体二阶段。")
	return members

## [param original] 所在格不分配给分身。[param board] 优先保留原定格，[param manager] 用于排除没有有效僵尸行的地块。
static func _choose_cells(original: ZB000Base, board: BoardRuntime, manager: ZombieManager) -> Array[PlantCell]:
	var formation: Array[PlantCell] = [] # 空位暂时保留，确保后一名的有效原定格不会被前一名占用。
	formation.resize(PREFERRED.size())
	var taken: Dictionary[PlantCell, bool] = {} # 分身不能互相重合，也不能落在本体脚下的格子。
	var used_lanes: Dictionary[int, bool] = {} # 有其他可用行时，避免与本体或同组另一名分身共行。
	used_lanes[original.lane] = true
	var home := BoardQueries.nearest(board, original.global_position, original.lane) # 场外本体保留邻近的本行边缘格。
	if home != null:
		taken[home] = true
	for index: int in PREFERRED.size(): # 两个指定格均存在时沿用教堂原队形。
		var exact: PlantCell = board.cell_at(PREFERRED[index]) # 在非矩形、稀疏棋盘上允许没有该格。
		if _usable(exact, manager) and not taken.has(exact):
			formation[index] = exact
			taken[exact] = true
			used_lanes[exact.row_col.x] = true
	var available: Array[PlantCell] = board.cells() # 只在分裂时检查当前实际地块。
	for index: int in PREFERRED.size(): # 缺失位置优先独立行，再按原定行列的距离选格。
		if formation[index] != null:
			continue
		var best: PlantCell # 同分时保留棋盘稳定遍历顺序。
		var best_rank := Vector3i(2, 0, 0) # 第一分量为重复行惩罚，合法候选的上限为一。
		for cell: PlantCell in available: # 每次只为一个缺失位置寻找最近候选。
			if not _usable(cell, manager) or taken.has(cell):
				continue
			var distance: Vector2i = (cell.row_col - PREFERRED[index]).abs() # 行距优先于列距。
			var rank := Vector3i(int(used_lanes.has(cell.row_col.x)), distance.x, distance.y) # 同类落点按行列距离排序。
			if rank < best_rank:
				best = cell
				best_rank = rank
		if best == null:
			return []
		formation[index] = best
		taken[best] = true
		used_lanes[best.row_col.x] = true
	return formation

## 只有 [param cell] 位于 [param manager] 有效的出怪行且本帧脚点有限，才能用于准备分身。
static func _usable(cell: PlantCell, manager: ZombieManager) -> bool:
	if not is_instance_valid(cell) or cell.is_queued_for_deletion() or not cell.is_inside_tree() \
			or cell.row_col.x < 0 or cell.row_col.x >= manager.all_zombie_rows.size():
		return false
	var row: ZombieRow = manager.all_zombie_rows[cell.row_col.x] # 行容器与棋盘可能在切场时先后离树。
	return is_instance_valid(row) and row.is_inside_tree() and not row.is_queued_for_deletion() \
		and cell.get_slot_anchor_global_position(CharacterRegistry.PlacePlantInCell.Norm).is_finite()
