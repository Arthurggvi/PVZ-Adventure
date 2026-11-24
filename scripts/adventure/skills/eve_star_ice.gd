## 伊芙的星空冰。绘制传入的命中格，星图在晶面内循环，撞击余光在飞行层独立消退。
extends Node2D

## 玩家提供的 4 列 3 行透明序列图。
const ATLAS: Texture2D = preload("res://assets/adventure/skills/eve/star_ice_sheet.png")
## 结晶扩展、序列混合和冰缘过渡共用同一材质。
const ICE_SHADER: Shader = preload("res://shaders/adventure/eve_star_ice.gdshader")
## 用整个 3×3 的归一坐标取样；真实格保留各自的图案区域。
const GRID_SPAN := 3.0
## 雪山格线沿两段坡面剪切，原始星纹在去剪切的逻辑格网上连续铺设。
const SNOW_BOARD := &"wonderland.snow_mountains"
## 雪山末行外的冰沿深度，占真实单行高的比例。
const SNOW_FRONT_ICE_DEPTH: float = 0.64
## 雪山四边形的左上、右上、右下、左下在未倾斜格上的坐标。
const QUAD_UV: Array[Vector2] = [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN]
## 雪山多边形的左右上下顶点。顺序与相对一侧相同，便于验证共边。
const QUAD_EDGES: Array[Vector2i] = [Vector2i(0, 3), Vector2i(1, 2), Vector2i(0, 1), Vector2i(3, 2)]
## 只吸收世界坐标换算的亚像素误差，不吸附真空隙。单位为同平台像素。
const SLOPE_JOIN_EPSILON_SQ := 0.015625
## 左、右、上、下的逻辑行列偏移，也是送往材质的颜色通道顺序。
const SIDES: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
## 自然格缝小于此格宽/高比例才共享边，屋顶常见的 10 像素缝包含在内。
const JOIN_FRACTION := 0.17
## 短暂腾起的碎晶和撞击星芒共用这段持续时间，单位为战斗秒。
const SPARK_SECONDS := 0.38

## 同一平台只绘制一张裁好的网格；平台独立运动时各自跟随。
var _patches: Dictionary[CanvasItem, MeshInstance2D] = {}
## 本次落点的网格共用序列相位和凝固年龄。
var _ice_material: ShaderMaterial
## 冰面上短暂升起的碎晶，与厚冰和雾的贴地层分开。
var _sparks: Node2D
## 按屏幕地面投影归一的碎晶落点偏移和尺寸。
var _shards: Array[Vector3] = []
## 以战斗时钟计的撞击余光年龄，超过上限后停止重绘。
var _spark_age := 0.0

## [param center] 是爆心，[param cells] 是实际结算的格；[param anchor] 是爆心格内的针尖接触点。
## [param incoming] 为末段入射方向，[param visual_seed] 只偏置碎晶与序列，[param spark_z] 是碎晶的绝对绘制深度。
func configure(center: PlantCell, cells: Array[PlantCell], anchor: Vector2,
		incoming: Vector2, visual_seed: int, spark_z: int) -> void:
	_ice_material = ShaderMaterial.new()
	_ice_material.shader = ICE_SHADER
	_ice_material.set_shader_parameter(&"ice_atlas", ATLAS)
	_ice_material.set_shader_parameter(&"glint_offset", float(visual_seed % 13) / 13.0)

	var snow_slope: bool = center.board.board_id == SNOW_BOARD # 雪山冰面额外接收周边吹雪的散射色。
	_ice_material.set_shader_parameter(&"snow_slope", snow_slope)
	var by_address: Dictionary[Vector2i, PlantCell] = {} # 单发的实际覆盖格，包含对角且允许空洞。
	var groups: Dictionary[CanvasItem, Array] = {} # 按随动坐标系合并绘制。
	for cell: PlantCell in cells: # 所有格已经在命中事件上通过有效性检查。
		by_address[cell.row_col] = cell
		var surface: CanvasItem = center.board.surfaces.get(cell.board_definition.surface_id, cell) # 通常是共同的平台根。
		if not groups.has(surface):
			groups[surface] = []
		groups[surface].append(cell)
	for surface: CanvasItem in groups: # 只有各平台的变换需要随时间更新。
		_build_patch(surface, groups[surface], center, anchor, by_address, snow_slope)

	_sparks = Node2D.new()
	_sparks.z_as_relative = false
	_sparks.z_index = spark_z
	_sparks.draw.connect(_draw_sparks)
	add_child(_sparks)
	var random := RandomNumberGenerator.new() # 仅决定碎晶的散射，不影响落点或魅惑。
	random.seed = visual_seed
	var ground: Transform2D = center.get_global_transform() # 以真实格尺寸投影碎晶，避免屋顶斜坡压扁星芒。
	_sparks.scale = (Vector2(ground.x.length(), ground.y.length()) * center.size).max(Vector2.ONE)
	for index: int in range(8): # 少量向四周掠过的细碎反光。
		var angle: float = TAU * float(index) / 8.0 + random.randf_range(-0.23, 0.23) # 固定散开扇区。
		var offset: Vector2 = Vector2.from_angle(angle) * random.randf_range(0.36, 0.69) + incoming * 0.16 # 落点朝入射方向轻微偏移。
		_shards.append(Vector3(offset.x, offset.y, random.randf_range(0.04, 0.085)))

## 将 [param cells] 烘焙进 [param surface] 局部坐标。用 [param center]、[param anchor] 和 [param by_address] 对准星核、冰纹及外缘。
## [param snow_slope] 使用雪山坡格的四角投影，共边连续。末行落点在前沿额外绘制一段星河冰。
func _build_patch(surface: CanvasItem, cells: Array, center: PlantCell, anchor: Vector2,
		by_address: Dictionary[Vector2i, PlantCell], snow_slope: bool) -> void:
	var vertices := PackedVector2Array() # 每个格的实际地面几何。
	var uv := PackedVector2Array() # 每个格在完整 3×3 图案中所占的连续范围。
	var edges := PackedColorArray() # 四个通道编码暴露的左右上下边。
	var indices := PackedInt32Array() # 各格多边形的三角面索引。
	var to_surface: Transform2D = surface.get_global_transform().affine_inverse() # 拍摄时无需重新计算网格。
	var welded: Dictionary[Vector2i, Vector2] = {} # 共用格角在平台空间只保留一份像素坐标。
	var last_row_impact: bool = snow_slope and center.row_col.x == center.board.extent.x - 1 # 落在末行时原图还留有一段下缘。
	for cell: PlantCell in cells: # 只在合法格里铺冰。
		var rect := Rect2(Vector2.ZERO, cell.size) # 不规则格仍使用原局部尺寸作为 UV 基准。
		var polygon: PackedVector2Array = cell.board_definition.hit_polygon # 有声明时保留其真实轮廓。
		var open := Color(0.0, 0.0, 0.0, 0.0) # 几何无法共享的边做柔化。
		var angled_quad: bool = snow_slope and polygon.size() == QUAD_UV.size() # 雪山采用顶点对应关系，其他棋盘沿用各自轮廓。
		var extend_front: bool = angled_quad and last_row_impact and cell.row_col.x == center.row_col.x # 仅沿被命中的最下排接出冰缘。
		if angled_quad:
			open = _snow_edges(cell, polygon, by_address)
			if extend_front:
				open.a = 0.0 # 格子底边已和装饰冰面共享，不留淡线。
		else:
			var seams: Vector4 = _tile_seams(cell, by_address) # 可拼接的半缝宽，外缘为无穷大。
			var margins := Vector4.ZERO # 暴露边不向格外延伸。
			for side: int in range(SIDES.size()): # 用同一接缝数据决定边界尺寸及淡边。
				if is_finite(seams[side]):
					margins[side] = seams[side]
				else:
					open[side] = 1.0
			if polygon.is_empty():
				rect = rect.grow_individual(margins.x, margins.z, margins.y, margins.w)
				polygon = PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y),
					rect.end, Vector2(rect.position.x, rect.end.y)])
		var tile_index := Vector2(cell.row_col.y - center.row_col.y + 1, cell.row_col.x - center.row_col.x + 1) # 左上为零。
		if cell == center:
			var contact_uv: Vector2 = (anchor - rect.position) / rect.size # 旧格以轴对齐矩形归一化。
			if angled_quad:
				var slope_projection := Transform2D(polygon[1] - polygon[0], polygon[3] - polygon[0], polygon[0]) # 从逻辑格投到真实雪坡。
				contact_uv = slope_projection.affine_inverse() * anchor
			_ice_material.set_shader_parameter(&"impact_uv", (tile_index + contact_uv) / GRID_SPAN)
		var cell_to_surface: Transform2D = to_surface * cell.get_global_transform() # 植物支撑物的动效不会影响冰面。
		var base: int = vertices.size() # 当前格局部三角索引的起点。
		for corner: int in range(polygon.size()): # 保留局部顶点，包括不规则格的折角。
			var point: Vector2 = polygon[corner] # 当前原始地面顶点。
			var projected: Vector2 = cell_to_surface * point # 坡面实际位置，保留每段地势的方向。
			var tile_uv: Vector2 = (point - rect.position) / rect.size # 默认使用现有局部归一化。
			if angled_quad:
				tile_uv = QUAD_UV[corner]
				projected = _weld_corner(projected, Vector2i(tile_index + tile_uv), welded)
			vertices.append(projected)
			uv.append((tile_index + tile_uv) / GRID_SPAN)
			edges.append(open)
		for index: int in Geometry2D.triangulate_polygon(polygon): # 棋盘已预检可用多边形。
			indices.append(base + index)
		if extend_front:
			var start := tile_index + Vector2.DOWN # 在原图剩余的下段继续取样，真实格的星纹和撞击点保持对齐。
			var left: Vector2 = vertices[base + 3] # 外延与实格复用左下和右下两个接点。
			var right: Vector2 = vertices[base + 2]
			var depth: Vector2 = (left - vertices[base]) * SNOW_FRONT_ICE_DEPTH # 根据去剪切前的单行纵向跨度沿平台向下铺设。
			var outer_left: Vector2 = _weld_corner(left + depth, Vector2i(start + Vector2.DOWN), welded) # 跨列的外沿也使用同一格角。
			var outer_right: Vector2 = _weld_corner(right + depth, Vector2i(start + Vector2.ONE), welded)
			var extra: int = vertices.size() # 外延只追加网格，不登记额外命中格。
			var front_edges := Color(open.r, open.g, 0.0, 1.0) # 最外端切回薄霜，左右沿用已有拼接状态。
			vertices.append_array(PackedVector2Array([left, right, outer_right, outer_left]))
			for corner_uv: Vector2 in QUAD_UV: # 末行实格与装饰下缘的 UV 在接点完全相同。
				uv.append((start + corner_uv) / GRID_SPAN)
				edges.append(front_edges)
			for index: int in [0, 1, 2, 0, 2, 3]: # 以同一对角线划分整个外延四边形。
				indices.append(extra + index)
	var arrays: Array = [] # 每个平台只提交一次静态几何和边界通道。
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_COLOR] = edges
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new() # 共用同一次冰面年龄及纹理。
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var patch := MeshInstance2D.new() # 作为冰效果的子节点统一回收。
	patch.mesh = mesh
	patch.material = _ice_material
	add_child(patch)
	_patches[surface] = patch

## 将 [param point] 写入 [param welded] 的逻辑格角 [param key]，只复用物理位置重合的格角。
static func _weld_corner(point: Vector2, key: Vector2i, welded: Dictionary[Vector2i, Vector2]) -> Vector2:
	var shared: Vector2 = welded.get(key, Vector2.INF) # 同一格角在平台坐标内已经登记的实际位置。
	if shared.distance_squared_to(point) <= SLOPE_JOIN_EPSILON_SQ:
		return shared
	welded[key] = point
	return point

## 返回 [param cell] 的雪坡 [param polygon] 外露边；[param by_address] 里两端都重合的命中格才连续铺冰。
func _snow_edges(cell: PlantCell, polygon: PackedVector2Array, by_address: Dictionary[Vector2i, PlantCell]) -> Color:
	var open := Color.WHITE # 缺格、盘外以及不相连的边保留外沿霜化。
	var to_cell: Transform2D = cell.get_global_transform().affine_inverse() # 共边比较在同一格的像素坐标内进行。
	for side: int in range(SIDES.size()): # 每格只检查四个真实相接的逻辑邻居。
		var neighbor: PlantCell = by_address.get(cell.row_col + SIDES[side]) # 命中范围以外的格不参与拼接。
		if neighbor == null or neighbor.board_definition.surface_id != cell.board_definition.surface_id:
			continue
		var other: PackedVector2Array = neighbor.board_definition.hit_polygon # 读取同坡其他方向的格角。
		if other.size() != QUAD_UV.size():
			continue
		var edge: Vector2i = QUAD_EDGES[side] # 当前侧首尾格角。
		var across: Vector2i = QUAD_EDGES[side ^ 1] # 邻格相对侧，沿同一方向取两个端点。
		var local: Transform2D = to_cell * neighbor.get_global_transform() # 邻格顶点换到当前格。
		if polygon[edge.x].distance_squared_to(local * other[across.x]) <= SLOPE_JOIN_EPSILON_SQ \
				and polygon[edge.y].distance_squared_to(local * other[across.y]) <= SLOPE_JOIN_EPSILON_SQ:
			open[side] = 0.0
	return open

## 返回 [param cell] 和 [param by_address] 内同平台相邻格的半缝宽；负数修齐轻微重叠，无法相接时为 INF。
func _tile_seams(cell: PlantCell, by_address: Dictionary[Vector2i, PlantCell]) -> Vector4:
	var seams := Vector4(INF, INF, INF, INF) # 开边及多边形边保持自己的实际几何。
	if not cell.board_definition.hit_polygon.is_empty():
		return seams
	var to_cell: Transform2D = cell.get_global_transform().affine_inverse() # 用当前格局部宽高测相邻边。
	for side: int in range(SIDES.size()): # 只接同平台上的矩形格，避免填掉真正的缺口。
		var neighbor: PlantCell = by_address.get(cell.row_col + SIDES[side]) # 只有本次会结算的格才可共享边。
		if neighbor == null or neighbor.board_definition.surface_id != cell.board_definition.surface_id \
				or not neighbor.board_definition.hit_polygon.is_empty():
			continue
		var axis: int = 0 if side < 2 else 1 # 左右沿 X，上下沿 Y。
		var negative: bool = side % 2 == 0 # 左边和上边沿轴负向。
		var relative: Transform2D = to_cell * neighbor.get_global_transform() # 邻格原点在当前格的相对偏移。
		var gap: float = -relative.origin[axis] - neighbor.size[axis] if negative \
			else relative.origin[axis] - cell.size[axis] # 两个相邻面的有符号间距。
		var cross: int = 1 - axis # 正交方向偏移过大时属于独立边。
		if absf(gap) <= minf(cell.size[axis], neighbor.size[axis]) * JOIN_FRACTION \
				and absf(relative.origin[cross]) <= minf(cell.size[cross], neighbor.size[cross]) * 0.26:
			seams[side] = gap * 0.5
	return seams

## 使用 [param seconds] 取样凝固、循环序列和碎晶；[param opacity] 控制地表整体消散。
func set_age(seconds: float, opacity: float) -> void:
	_ice_material.set_shader_parameter(&"age", maxf(seconds, 0.0))
	_ice_material.set_shader_parameter(&"opacity", opacity)
	var to_ice: Transform2D = get_global_transform().affine_inverse() # 把世界位姿换算至当前星核的局部空间。
	for surface: CanvasItem in _patches: # 更新刚体位姿，网格和星纹不重建。
		var mesh: MeshInstance2D = _patches[surface] # 任一平台独立离场时只隐藏它的冰面。
		if not is_instance_valid(surface) or surface.is_queued_for_deletion():
			mesh.hide()
			continue
		var transform_in_ice: Transform2D = to_ice * surface.get_global_transform() # 让地面几何随平台走。
		if mesh.transform != transform_in_ice:
			mesh.transform = transform_in_ice
	if _spark_age < SPARK_SECONDS:
		_spark_age = clampf(seconds, 0.0, SPARK_SECONDS)
		_sparks.queue_redraw()

## 从地表锚点吐出一次银蓝的碎晶与星芒，碎屑先升后落，末段在空气中淡出。
func _draw_sparks() -> void:
	if _spark_age >= SPARK_SECONDS:
		return
	var phase: float = _spark_age / SPARK_SECONDS # 一次撞击的归一相位。
	var expand: float = 1.0 - pow(1.0 - phase, 2.4) # 碎晶先散开，再慢下来落地。
	var loft: float = 4.0 * phase * (1.0 - phase) # 从真实落点抛起，再落回地面。
	var alpha: float = smoothstep(0.0, 0.09, phase) * (1.0 - smoothstep(0.45, 1.0, phase)) # 独立散射不影响冰面亮度。
	for shard: Vector3 in _shards: # 每个碎晶用三角高光和一条亮脊表示。
		var direction := Vector2(shard.x, shard.y * 0.72) # 散射方向压到地面投影。
		var point: Vector2 = direction * expand + Vector2.UP * loft * (0.16 + shard.z) # 叠加短促的升空弧线。
		var axis: Vector2 = direction.normalized().rotated(phase * 0.7) * shard.z # 亮脊随碎晶略微翻转。
		var width: Vector2 = axis.orthogonal() * 0.25 # 三角形的两侧。
		_sparks.draw_colored_polygon(PackedVector2Array([point + axis, point - axis + width,
			point - axis - width]), Color(0.45, 0.79, 1.0, alpha * 0.56))
		_sparks.draw_line(point + axis, point - axis, Color(0.82, 0.98, 1.0, alpha), 0.009, true)
	var flash: float = 1.0 - smoothstep(0.0, 0.34, phase) # 针尖消失时同位置出现的短闪。
	var ray: float = lerpf(0.10, 0.23, expand) # 星芒先展长，再由亮度包络收走。
	_sparks.draw_line(Vector2.LEFT * ray, Vector2.RIGHT * ray, Color(0.70, 0.91, 1.0, flash), 0.010, true)
	_sparks.draw_line(Vector2.UP * ray * 0.76, Vector2.DOWN * ray * 0.76, Color(0.89, 0.99, 1.0, flash), 0.012, true)
