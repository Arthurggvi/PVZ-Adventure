## 出手瞬间的世界横向几何快照；不承担僵尸地面高度或平台跟随。
extends RefCounted
class_name BoardLandingGeometry

## 忽略不可可靠选点的极窄截段，并令旧脚点截线稍离矩形底边。
const EDGE_EPSILON: float = 0.001
## 每个连续截段两侧的内缩比例，避免落在边缘或接缝。
const EDGE_INSET: float = 0.1
## 按左端排序的有效世界 X 闭区间，不填补区间之间的空洞。
var spans: Array[Vector2] = []
## 全部原始截段的左右边界；不包含内缩，空快照为零。
var bounds: Vector2 = Vector2.ZERO
## 每格原始有效截段总宽的中位数，不把格间或格内空洞算作宽度。
var pitch: float = 0.0

## 读取 [param board] 中 [param lane] 行的当前几何，返回独立快照；无效时返回空快照。
static func capture(board: BoardRuntime, lane: int) -> BoardLandingGeometry:
	var result := BoardLandingGeometry.new() # 不保存地块或平台引用。
	var widths: Array[float] = [] # 每个有效地块贡献一次原始有效宽度。
	if not is_instance_valid(board) or not board.configured or lane < 0:
		return result
	for cell: PlantCell in board.row_cells(lane): # 枚举顺序不代表实际左右位置。
		if not is_instance_valid(cell) or cell.is_queued_for_deletion() \
				or not cell.is_visible_in_tree() or cell.board != board \
				or cell.combat_lane != lane or board.cell_by_id(cell.cell_id) != cell:
			continue
		var width: float = 0.0 # 同格多段求有效长度之和，不包含凹形缺口。
		for span: Vector2 in _cell_spans(cell): # 每段均已与当前地块矩形取交集。
			var length: float = span.y - span.x # 内缩前的连续有效宽度。
			if result.spans.is_empty():
				result.bounds = span
			else:
				result.bounds = Vector2(minf(result.bounds.x, span.x), maxf(result.bounds.y, span.y))
			result.spans.append(Vector2(span.x + length * EDGE_INSET, span.y - length * EDGE_INSET))
			width += length
		if width > EDGE_EPSILON:
			widths.append(width)
	result.spans.sort_custom(_left_before)
	if not widths.is_empty():
		widths.sort()
		var middle: int = floori(widths.size() * 0.5) # 偶数样本取两个中位值的均值。
		result.pitch = widths[middle] if widths.size() % 2 != 0 else (widths[middle - 1] + widths[middle]) * 0.5
	return result

## 将 [param preferred] 投影到真实区间与 [param minimum]、[param maximum] 的交集；返回最近 X，无解或 NaN 输入返回 NaN。
func nearest_x(preferred: float, minimum: float = -INF, maximum: float = INF) -> float:
	var result: float = NAN # 空集及无交集均保持无解。
	var distance: float = INF # 等距时保留排序靠左的候选。
	if not is_finite(preferred) or is_nan(minimum) or is_nan(maximum) or minimum > maximum:
		return result
	for span: Vector2 in spans: # 单独约束每段，不能向整体包围区间投影。
		if not span.is_finite() or span.x > span.y:
			continue
		var left: float = maxf(span.x, minimum) # 该段与调用方下界的交集。
		var right: float = minf(span.y, maximum) # 该段与调用方上界的交集。
		if left > right:
			continue
		var candidate: float = clampf(preferred, left, right) # 在连续区间内投影，不吸附格心。
		var candidate_distance: float = absf(candidate - preferred) # 世界横向距离。
		if is_nan(result) or candidate_distance < distance:
			result = candidate
			distance = candidate_distance
	return result

## 返回 [param cell] 的原始世界截段；矩形、命中多边形或脚点无效时返回空数组。
static func _cell_spans(cell: PlantCell) -> Array[Vector2]:
	var result: Array[Vector2] = [] # 自定义多边形与矩形的交集。
	if not cell.size.is_finite() or cell.size.x <= 0.0 or cell.size.y <= 0.0:
		return result
	var frame: Transform2D = cell.get_global_transform() # 出手瞬间的完整世界变换。
	var rectangle: PackedVector2Array = _to_world(PackedVector2Array([Vector2.ZERO, Vector2(cell.size.x, 0.0), cell.size, Vector2(0.0, cell.size.y)]), frame) # 当前矩形轮廓。
	var foot: Vector2 = cell.get_spawn_global_position() # 兼容已有新旧关生成脚点规则。
	if cell.board_definition != null and cell.board_definition.ground_anchor_y >= 0.0:
		# 异形坡格用画面脚点截取轮廓，平面出怪基线可能完全落在该格外。
		foot = frame * Vector2(cell.size.x * 0.5, cell.board_definition.ground_anchor_y)
	if rectangle.is_empty() or not foot.is_finite():
		return result
	var top: float = INF # 变换后矩形的最上端。
	var bottom: float = -INF # 变换后矩形的最下端。
	for point: Vector2 in rectangle: # 支持旋转、缩放及镜像后的水平截线。
		top = minf(top, point.y)
		bottom = maxf(bottom, point.y)
	if bottom - top <= EDGE_EPSILON:
		return result
	var padding: float = minf(EDGE_EPSILON, (bottom - top) * 0.25) # 极小矩形也保留非空截线范围。
	var ordinate: float = clampf(foot.y, top + padding, bottom - padding) # 旧关脚点可在格外，截线仅在当前矩形内取样。
	var rectangle_spans: Array[Vector2] = _slice(rectangle, ordinate) # 矩形的真实水平截段。
	if cell.board_definition == null or cell.board_definition.hit_polygon.is_empty():
		return rectangle_spans
	for hit: Vector2 in _slice(_to_world(cell.board_definition.hit_polygon, frame), ordinate): # 凹多边形可能贡献多个不连续区间。
		for rect: Vector2 in rectangle_spans: # 与现有地块查询一样，同时受矩形约束。
			var intersection := Vector2(maxf(hit.x, rect.x), minf(hit.y, rect.y)) # 原始有效交集。
			if intersection.y - intersection.x > EDGE_EPSILON:
				result.append(intersection)
	return result

## 将 [param polygon] 依 [param frame] 转换到世界坐标，返回新多边形；非有限坐标返回空数组。
static func _to_world(polygon: PackedVector2Array, frame: Transform2D) -> PackedVector2Array:
	var result := PackedVector2Array() # 不修改资源中的原多边形。
	for point: Vector2 in polygon: # 逐点验证也排除无效变换产生的坐标。
		var world: Vector2 = frame * point # 当前世界顶点。
		if not world.is_finite():
			return PackedVector2Array()
		result.append(world)
	return result

## 返回 [param polygon] 与世界水平线 [param ordinate] 的全部连续闭区间；无面积或无交集时返回空数组。
static func _slice(polygon: PackedVector2Array, ordinate: float) -> Array[Vector2]:
	var result: Array[Vector2] = [] # 相邻内部截段合并，真实空洞保留。
	var crossings: Array[float] = [] # 包括水平边端点和普通边交点。
	var area: float = 0.0 # 平移后求两倍有向面积，拒绝退化轮廓。
	if polygon.size() < 3 or not is_finite(ordinate):
		return result
	for index: int in range(polygon.size()): # 闭合最后一条边，无需资源重复首顶点。
		var first: Vector2 = polygon[index] # 当前边起点。
		var second: Vector2 = polygon[(index + 1) % polygon.size()] # 当前边终点。
		area += (first - polygon[0]).cross(second - polygon[0])
		if first.y == second.y:
			if first.y == ordinate:
				crossings.append(first.x)
				crossings.append(second.x)
		elif ordinate >= minf(first.y, second.y) and ordinate <= maxf(first.y, second.y):
			crossings.append(lerpf(first.x, second.x, (ordinate - first.y) / (second.y - first.y)))
	if not is_finite(area) or absf(area) <= EDGE_EPSILON * EDGE_EPSILON:
		return result
	crossings.sort()
	for index: int in range(crossings.size() - 1): # 分段中点判内，避免凹形多交点被当成单个包围区间。
		var left: float = crossings[index] # 当前候选左端。
		var right: float = crossings[index + 1] # 当前候选右端。
		if right - left <= EDGE_EPSILON or not Geometry2D.is_point_in_polygon(Vector2((left + right) * 0.5, ordinate), polygon):
			continue
		if not result.is_empty() and left <= result[-1].y:
			result[-1] = Vector2(result[-1].x, right)
		else:
			result.append(Vector2(left, right))
	return result

## 比较 [param left] 与 [param right] 的左端；返回左区间是否应排在前面。
static func _left_before(left: Vector2, right: Vector2) -> bool:
	return left.x < right.x
