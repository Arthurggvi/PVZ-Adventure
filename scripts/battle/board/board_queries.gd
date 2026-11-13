## 地块拓扑及当前几何查询；所有坐标均即时读取，不缓存移动前的位置。
extends RefCounted
class_name BoardQueries

## 查询 [param origin] 的 [param radius] 步邻接；规则地址与显式关系统一返回地块。
static func neighbors(board: BoardRuntime, origin: PlantCell, radius: int) -> Array[PlantCell]:
	var result: Array[PlantCell] = [] # 稳定去重的结果。
	if origin == null or origin.board != board or radius < 0:
		return result
	result.append(origin)
	if origin.board_definition.explicit_neighbors:
		var frontier: Array[PlantCell] = [origin] # 广度展开的当前边界。
		for step: int in range(radius): # 按逻辑步数展开，不使用像素距离。
			var next: Array[PlantCell] = [] # 下一步的新邻格。
			for cell: PlantCell in frontier: # 当前地块的显式邻接。
				for target: PlantCell in _direct_neighbors(board, cell): # 每个边界点独立选择其邻接契约。
					if not result.has(target):
						result.append(target)
						next.append(target)
			frontier = next
		return result
	for cell: PlantCell in board.cells(): # 规则拓扑按逻辑坐标，不按稀疏数组下标。
		if cell != origin and cell.board_definition.surface_id == origin.board_definition.surface_id \
				and absi(cell.row_col.x - origin.row_col.x) <= radius \
				and absi(cell.row_col.y - origin.row_col.y) <= radius:
			result.append(cell)
	return result

## 按当前世界锚点寻找最近地块；[param lane] 为 -1 时跨行。
static func nearest(board: BoardRuntime, point: Vector2, lane: int = -1) -> PlantCell:
	var result: PlantCell = null # 没有候选返回 null。
	var distance: float = INF # 当前最佳平方距离。
	for cell: PlantCell in board.cells(): # 独立几何，不假定每行首格代表全行。
		if lane >= 0 and cell.row_col.x != lane:
			continue
		var candidate: float = cell.get_global_rect().get_center().distance_squared_to(point) # 当前距离。
		if candidate < distance:
			distance = candidate
			result = cell
	return result

## 在 [param board] 的 [param lane] 内精确匹配世界脚点 [param point]，失败返回 null。
## 底边闭合以兼容地块生成脚点；水平边界保持左闭右开，不跨空洞寻找邻格。
static func cell_at_ground_point(board: BoardRuntime, point: Vector2, lane: int) -> PlantCell:
	var result: PlantCell = null # 重叠地块按现有 GUI 场景树顺序选取。
	if lane < 0 or not point.is_finite():
		return null
	for cell: PlantCell in board.row_cells(lane): # 即时查询当前地块，不缓存平台运动前的几何。
		if not is_instance_valid(cell) or cell.is_queued_for_deletion() \
				or not cell.is_visible_in_tree() or board.cell_by_id(cell.cell_id) != cell:
			continue
		var local_point: Vector2 = cell.get_global_transform().affine_inverse() * point # 当前地块局部脚点。
		if local_point.x < 0.0 or local_point.x >= cell.size.x \
				or local_point.y < 0.0 or local_point.y > cell.size.y:
			continue
		if cell.board_definition != null and not cell.board_definition.hit_polygon.is_empty() \
				and not Geometry2D.is_point_in_polygon(local_point, cell.board_definition.hit_polygon):
			continue
		if result == null or cell.is_greater_than(result):
			result = cell
	return result

## 返回 [param cells] 的世界包围矩形；空结果为零矩形。
static func bounds(cells: Array[PlantCell]) -> Rect2:
	var result := Rect2() # 当前合并包围盒。
	var first: bool = true # 第一个有效格子不与原点合并。
	for cell: PlantCell in cells: # 每格可有独立尺寸与位置。
		if not is_instance_valid(cell):
			continue
		result = cell.get_global_rect() if first else result.merge(cell.get_global_rect())
		first = false
	return result


## 单步邻接只返回同平台有效地块；[param cell] 可选择显式或规则拓扑。
static func _direct_neighbors(board: BoardRuntime, cell: PlantCell) -> Array[PlantCell]:
	var result: Array[PlantCell] = [] # 由当前节点的契约决定下一步。
	if cell.board_definition.explicit_neighbors:
		for id: StringName in cell.board_definition.neighbor_ids: # 配置已验证稳定引用。
			var target: PlantCell = board.cell_by_id(id) # 失效节点不加入结果。
			if target != null:
				result.append(target)
	else:
		result = neighbors(board, cell, 1)
		result.erase(cell)
	return result


## 读取 [param origin] 的同平台邻点几何；没有相邻点时退回该点自身尺寸。
static func local_pitch(board: BoardRuntime, origin: PlantCell) -> Vector2:
	if origin == null:
		return Vector2.ZERO
	var pitch: Vector2 = origin.size # 单个种植点仍有有意义的几何尺寸。
	var column_distance: float = INF # 最近同路地块横向距离。
	var row_distance: float = INF # 最近相邻攻击行的纵向距离。
	var point: Vector2 = origin.get_global_rect().get_center() # 当前世界中心。
	for cell: PlantCell in board.cells(): # 使用当前位姿，平台移动不会留下缓存。
		if cell == origin or cell.board_definition.surface_id != origin.board_definition.surface_id:
			continue
		var delta: Vector2 = (cell.get_global_rect().get_center() - point).abs() # 当前几何间距。
		if cell.row_col.x == origin.row_col.x and delta.x > 0.0:
			column_distance = minf(column_distance, delta.x)
		elif absi(cell.row_col.x - origin.row_col.x) == 1 and delta.y > 0.0:
			row_distance = minf(row_distance, delta.y)
	if is_finite(column_distance):
		pitch.x = column_distance
	if is_finite(row_distance):
		pitch.y = row_distance
	return pitch
