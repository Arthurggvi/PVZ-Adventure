## 电弧画布的有色三角批次；按添加顺序保留半透明层次和抗锯齿边缘。
extends RefCounted

## 沿发光线两侧羽化的标准世界像素宽度，细线按自身宽度缩小。
const FEATHER: float = 0.5
## 直径不超过十六像素的命中光点只需十二边。
const DISC_STEPS: int = 12

## 本次绘制的画布局部顶点。
var _vertices := PackedVector2Array()
## 对应顶点色包含原笔画透明度和羽化端的零透明度。
var _colors := PackedColorArray()
## 三角形按原效果自后向前排列。
var _indices := PackedInt32Array()
## 共用的单位圆顶点，避免每个命中点重复计算角度。
var _disc := PackedVector2Array()
## 当前折线各点的斜接偏移方向，四色描边共用，换线时全部覆写。
var _polyline_joins := PackedVector2Array()
## 两层碎电弧共用的起点、终点和法向；仅读取本次已写入的三元组。
var _segment_sections := PackedVector2Array()


## 开始新批次，丢弃上一绘制帧的图形数据。
func clear() -> void:
	_vertices.clear()
	_colors.clear()
	_indices.clear()


## 先绘制 [param rim] 的完整外缘，再绘制 [param core] 的内芯；[param points] 内的点对互不相连。
## [param rim_width] 和 [param core_width] 为线宽像素；[param offset] 和 [param scale] 只变换各段的中线。
func add_segment_layers(points: PackedVector2Array, rim: Color, rim_width: float, core: Color, core_width: float,
		offset: Vector2 = Vector2.ZERO, scale: float = 1.0) -> void:
	if rim.a <= 0.0 and core.a <= 0.0:
		return
	@warning_ignore("integer_division")
	_segment_sections.resize(points.size() / 2 * 3)
	var used: int = 0 # 已提交三元组占用的槽位。
	for index: int in range(0, points.size() - 1, 2): # 各段独立连接，短枝间没有额外连线。
		var start: Vector2 = offset + points[index] * scale # 当前线段的实际起点。
		var finish: Vector2 = offset + points[index + 1] * scale # 当前线段的实际终点。
		var side: Vector2 = (finish - start).normalized().orthogonal() # 实际端点的法向，两层都用同一数值。
		if side == Vector2.ZERO:
			continue
		_segment_sections[used] = start
		_segment_sections[used + 1] = finish
		_segment_sections[used + 2] = side
		used += 3
	if used == 0:
		return
	@warning_ignore("integer_division")
	var count: int = used / 3 # 去掉退化段后的实际线段数。
	_add_segment_layer(count, rim, rim_width)
	_add_segment_layer(count, core, core_width)


## 依序写入前 [param count] 个独立线段的一层，[param color] 含透明度，[param width] 是像素宽度。
func _add_segment_layer(count: int, color: Color, width: float) -> void:
	if color.a <= 0.0:
		return
	var half_width: float = _solid_half_width(width) # 扣除羽化补足的线宽。
	var outside: float = half_width + FEATHER * minf(1.0, half_width * 2.0) # 羽化外缘到中线的距离。
	var clear_color := Color(color, 0.0) # 与不透明内缘沿用相同的色相。
	var vertex: int = _vertices.size() # 本层下一段的连续两排轮廓顶点。
	var triangle: int = _indices.size() # 本层下一段的六个三角形。
	_vertices.resize(vertex + count * 8)
	_colors.resize(vertex + count * 8)
	_indices.resize(triangle + count * 18)
	for segment: int in range(0, count * 3, 3): # 每个三元组包含一对端点及共用法向。
		var side: Vector2 = _segment_sections[segment + 2] # 此段两端使用相同的羽化方向。
		_write_section(vertex, _segment_sections[segment], side, half_width, outside, color, clear_color)
		_write_section(vertex + 4, _segment_sections[segment + 1], side, half_width, outside, color, clear_color)
		_write_join(triangle, vertex)
		vertex += 8
		triangle += 18


## 把 [param points] 连接成 [param width] 像素宽、[param color] 色的连续羽化折线。
func add_polyline(points: PackedVector2Array, color: Color, width: float) -> void:
	if points.size() < 2 or color.a <= 0.0:
		return
	_prepare_polyline_joins(points)
	_add_polyline_layer(points, color, width)


## 添加 [param points] 的四色描边；[param energy] 是发光强度，[param core_width] 是细芯像素宽度。
func add_strand(points: PackedVector2Array, colors: Dictionary, energy: float, core_width: float = 1.1) -> void:
	if energy <= 0.001 or points.size() < 2:
		return
	_prepare_polyline_joins(points)
	_add_polyline_layer(points, Color(colors.glow, energy * 0.065), core_width + 6.2)
	_add_polyline_layer(points, Color(colors.rim, energy * 0.18), core_width + 3.0)
	_add_polyline_layer(points, Color(colors.rim, energy * 0.62), core_width + 0.9)
	_add_polyline_layer(points, Color(colors.core, energy), core_width)


## 绘制端点和节点固定的 [param points]。首次沿用原网格生成并返回顶点，之后复用 [param cached]。
## [param colors] 和 [param energy] 逐帧按原顺序更新四色透明度，三角索引从本批次的当前位置开始。
func add_complete_strand(points: PackedVector2Array, colors: Dictionary, energy: float,
		cached: PackedVector2Array) -> PackedVector2Array:
	if energy <= 0.001 or points.size() < 2:
		return cached
	var first: int = _vertices.size() # 本主弧四层在当前批次的起始点。
	if cached.is_empty():
		add_strand(points, colors, energy)
		return _vertices.slice(first)
	var point_count: int = points.size() # 一层在每个折点拥有四个轮廓顶点。
	var layer_vertices: int = point_count * 4 # 同一根主弧的四层拓扑相同。
	var layer_indices: int = (point_count - 1) * 18 # 每对相邻折点仍绘制六个三角形。
	var triangle: int = _indices.size() # 第一层的起始索引槽位。
	_vertices.append_array(cached)
	_colors.resize(first + cached.size())
	_indices.resize(triangle + layer_indices * 4)
	_write_cached_layer(first, triangle, point_count, Color(colors.glow, energy * 0.065))
	_write_cached_layer(first + layer_vertices, triangle + layer_indices, point_count, Color(colors.rim, energy * 0.18))
	_write_cached_layer(first + layer_vertices * 2, triangle + layer_indices * 2, point_count, Color(colors.rim, energy * 0.62))
	_write_cached_layer(first + layer_vertices * 3, triangle + layer_indices * 3, point_count, Color(colors.core, energy))
	return cached


## 只写缓存层的 [param color] 及新索引；[param first] 和 [param triangle] 是本层的起始槽位。
## [param point_count] 包含两端，轮廓每排从外缘、实体、实体到外缘。
func _write_cached_layer(first: int, triangle: int, point_count: int, color: Color) -> void:
	var clear_color := Color(color, 0.0) # 外缘保留原始色相及零透明度。
	for index: int in range(point_count): # 四色顶点此前已按同一顺序拷入。
		var vertex: int = first + index * 4 # 当前折点的一排顶点。
		_colors[vertex] = clear_color
		_colors[vertex + 1] = color
		_colors[vertex + 2] = color
		_colors[vertex + 3] = clear_color
		if index > 0:
			_write_join(triangle + (index - 1) * 18, vertex - 4)


## 由 [param points] 生成与线宽无关的斜接方向，输入至少含两个点。
func _prepare_polyline_joins(points: PackedVector2Array) -> void:
	var point_count: int = points.size() # 当前折线的实际点数。
	_polyline_joins.resize(point_count)
	var previous: Vector2 = (points[1] - points[0]).normalized().orthogonal() # 上一段的单位法向。
	for index: int in range(point_count): # 所有层在同一个折点使用相邻段法向。
		var next: Vector2 = (points[index + 1] - points[index]).normalized().orthogonal() if index + 1 < point_count else previous # 下一段的单位法向。
		if next == Vector2.ZERO:
			next = previous
		var side: Vector2 = (previous + next).normalized() # 相邻法向的角平分向量。
		if side == Vector2.ZERO:
			side = next
		_polyline_joins[index] = side / maxf(1.0 / 3.0, side.dot(next)) # 限制极锐角外伸，不让拐点形成尖峰。
		previous = next


## 复用 [param points] 已准备的斜接方向，按 [param color] 和像素 [param width] 添加一整层。
func _add_polyline_layer(points: PackedVector2Array, color: Color, width: float) -> void:
	var half_width: float = _solid_half_width(width) # 发光线实体区域的半宽。
	var outside: float = half_width + FEATHER * minf(1.0, half_width * 2.0) # 外缘仍围绕原折线。
	var clear_color := Color(color, 0.0) # 外缘与内缘保持同色。
	var count: int = points.size() # 每个折点对应一排轮廓顶点。
	var vertex: int = _vertices.size() # 当前折点的顶点写入位置。
	var triangle: int = _indices.size() # 当前折点与前一点之间的三角索引写入位置。
	_vertices.resize(vertex + count * 4)
	_colors.resize(vertex + count * 4)
	_indices.resize(triangle + (count - 1) * 18)
	_write_section(vertex, points[0], _polyline_joins[0], half_width, outside, color, clear_color)
	for index: int in range(1, count): # 层内保持既有顶点及三角顺序。
		_write_section(vertex + 4, points[index], _polyline_joins[index], half_width, outside, color, clear_color)
		_write_join(triangle, vertex)
		vertex += 4
		triangle += 18


## 在 [param center] 添加半径为 [param radius] 像素、颜色为 [param color] 的命中光点。
func add_disc(center: Vector2, radius: float, color: Color) -> void:
	if _disc.is_empty():
		for index: int in range(DISC_STEPS): # 用单位尺度预备圆边界。
			_disc.append(Vector2.from_angle(TAU * float(index) / DISC_STEPS))
	var first: int = _vertices.size() # 圆心顶点紧接本圆的全部边界点。
	var triangle: int = _indices.size() # 第一片扇形的索引写入位置。
	_vertices.resize(first + 1 + DISC_STEPS)
	_colors.resize(first + 1 + DISC_STEPS)
	_indices.resize(triangle + DISC_STEPS * 3)
	_vertices[first] = center
	_colors[first] = color
	for index: int in range(DISC_STEPS): # 相邻边界和圆心组成扇片。
		var vertex: int = first + 1 + index # 本片扇形的起始边界点。
		_vertices[vertex] = center + _disc[index] * radius
		_colors[vertex] = color
		_indices[triangle] = first
		_indices[triangle + 1] = vertex
		_indices[triangle + 2] = first + 1 + (index + 1) % DISC_STEPS
		triangle += 3


## 把本次批次提交到 [param canvas]，没有可见三角形时跳过。
func submit(canvas: CanvasItem) -> void:
	if not _indices.is_empty():
		RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(), _indices, _vertices, _colors)


## 返回 [param width] 的实体部分半宽，细芯羽化后保持与抗锯齿线条相近的亮度。
static func _solid_half_width(width: float) -> float:
	var fine: float = width * 0.5 # 小于一个像素的线芯留出对称羽化空间。
	var wide: float = width - FEATHER * 0.5 # 较宽线芯补偿固定羽化区域。
	return lerpf(fine, wide, clampf(width - 1.0, 0.0, 1.0)) * 0.5


## 从 [param first] 写入一排轮廓，横跨 [param point] 的 [param side] 方向。
## [param inner] 和 [param outer] 为距中心的两档像素半宽。
## [param color] 与 [param clear_color] 供两侧半透明羽化。
func _write_section(first: int, point: Vector2, side: Vector2, inner: float, outer: float,
		color: Color, clear_color: Color) -> void:
	var edge: Vector2 = side * outer # 本排外缘的法线偏移。
	var solid: Vector2 = side * inner # 本排有色内缘的法线偏移。
	_vertices[first] = point - edge
	_vertices[first + 1] = point - solid
	_vertices[first + 2] = point + solid
	_vertices[first + 3] = point + edge
	_colors[first] = clear_color
	_colors[first + 1] = color
	_colors[first + 2] = color
	_colors[first + 3] = clear_color


## 连接从 [param first] 开始的两排轮廓，在 [param index] 依序写入外缘、实体、外缘各两片。
func _write_join(index: int, first: int) -> void:
	_indices[index] = first
	_indices[index + 1] = first + 4
	_indices[index + 2] = first + 1
	_indices[index + 3] = first + 1
	_indices[index + 4] = first + 4
	_indices[index + 5] = first + 5
	_indices[index + 6] = first + 1
	_indices[index + 7] = first + 5
	_indices[index + 8] = first + 2
	_indices[index + 9] = first + 2
	_indices[index + 10] = first + 5
	_indices[index + 11] = first + 6
	_indices[index + 12] = first + 2
	_indices[index + 13] = first + 6
	_indices[index + 14] = first + 3
	_indices[index + 15] = first + 3
	_indices[index + 16] = first + 6
	_indices[index + 17] = first + 7
