## 本场脚底压暗和雪缘。只读已有脚点和雪面，每层提交一个有界三角形批次。
extends Node2D

## 两个场景独占材质共用的接触着色器。
const SHADER: Shader = preload("res://scripts/weather/snow/snow_footing.gdshader")
## 投影上方的植株与僵尸全场合计预算。
const MAX_CONTACTS: int = 256

## 单个绘制深度的 CPU 顶点与独占画布项。
class Batch:
	## 两个相邻四边形共享中间的两个顶点。
	const VERTICES_PER_CONTACT: int = 6
	## 每个四边形拆成两个三角形。
	const INDICES_PER_CONTACT: int = 12
	## 随场景释放的 RenderingServer 绘制项。
	var item: RID
	## 跨帧复用的世界像素缓冲，相邻半段共享中心边。
	var points: PackedVector2Array = PackedVector2Array()
	## 归一化松雪、压实、滚动权重和透明度。
	var styles: PackedColorArray = PackedColorArray()
	## 从固定模板截取的归一化坐标；顶点数改变时才截取。
	var uvs: PackedVector2Array = PackedVector2Array()
	## 从固定模板截取的三角形索引，连成两个相邻四边形。
	var indices: PackedInt32Array = PackedInt32Array()
	## 本帧有效顶点数；缓冲容量可大于实际提交数量。
	var vertex_count: int = 0
	## 上一帧提交的顶点数，用于避免重复清空空画布项。
	var uploaded_count: int = 0

	## 重置写入位置，保留原缓冲容量和画布项。
	func reset() -> void:
		vertex_count = 0

	## 追加由 [param left]、[param middle]、[param right] 确定的世界坡线。
	## [param up] 与 [param down] 为世界法线偏移，[param style] 为整个接触面的渲染数据。
	func append(left: Vector2, middle: Vector2, right: Vector2, up: Vector2, down: Vector2, style: Color) -> void:
		var base: int = vertex_count # 本接触的第一个顶点。
		vertex_count += VERTICES_PER_CONTACT
		if vertex_count > points.size():
			var capacity: int = maxi(vertex_count, points.size() * 2) # 只在超过历史容量时扩容。
			points.resize(capacity)
			styles.resize(capacity)
		points[base] = left + up
		points[base + 1] = left + down
		points[base + 2] = middle + up
		points[base + 3] = middle + down
		points[base + 4] = right + up
		points[base + 5] = right + down
		for vertex: int in range(base, vertex_count): # 各顶点共享同一地表样本。
			styles[vertex] = style

	## 用 [param uv_template] 和 [param index_template] 提交本帧的有效顶点；空批仅在原有内容时清空。
	func upload(uv_template: PackedVector2Array, index_template: PackedInt32Array) -> void:
		if vertex_count == 0 and uploaded_count == 0:
			return
		RenderingServer.canvas_item_clear(item)
		uploaded_count = vertex_count
		if vertex_count == 0:
			return
		if vertex_count != uvs.size():
			@warning_ignore("integer_division")
			var index_count: int = vertex_count * INDICES_PER_CONTACT / VERTICES_PER_CONTACT # 每个接触总有完整六顶点。
			uvs = uv_template.slice(0, vertex_count)
			indices = index_template.slice(0, index_count)
		var draw_points: PackedVector2Array = points if vertex_count == points.size() else points.slice(0, vertex_count) # 只上传实际接触。
		var draw_styles: PackedColorArray = styles if vertex_count == styles.size() else styles.slice(0, vertex_count) # 与顶点保持同长。
		RenderingServer.canvas_item_add_triangle_array(item, indices, draw_points, draw_styles, uvs)

## 权威雪面积雪状态和坡形。
var _surface: SnowSurface
## 紧贴雪面的暗部位于所有原生投影之前。
var _shadow: Batch
## 各行雪缘位于本行角色前和弹体后。
var _rims: Array[Batch] = []
## 两个材质的 RID 由场景引用保活。只有雪缘材质需要风输入。
var _shadow_material: ShaderMaterial
## 各行共享本场雪缘材质。
var _rim_material: ShaderMaterial
## 本场格区最右端，雪缘不得探入备战区。
var _board_right: float = 0.0
## 本次构建剩余的接触次数。
var _remaining: int = 0
## 所有接触批次共用的固定 UV 序列。
var _uv_template := PackedVector2Array()
## 所有接触批次共用的固定三角形序列。
var _index_template := PackedInt32Array()

## 使用 [param surface] 和 [param game] 的实际世界坡面与行深度装配画布。
func configure(surface: SnowSurface, game: MainGameManager) -> void:
	_surface = surface
	_board_right = BoardQueries.bounds(game.board.cells()).end.x
	_shadow_material = ShaderMaterial.new()
	_shadow_material.shader = SHADER
	_rim_material = ShaderMaterial.new()
	_rim_material.shader = SHADER
	_rim_material.set_shader_parameter(&"front_edge", true)
	_prepare_templates()
	_shadow = _create_batch(-1, _shadow_material)
	for row: ZombieRow in game.zombie_manager.all_zombie_rows: # 使用实际战斗行及其绘制深度。
		_rims.append(_create_batch(row.z_index + 9, _rim_material))

## 按每个接触的原有顶点顺序生成本场批次共用的 UV 和三角形索引。
func _prepare_templates() -> void:
	var uv_pattern := PackedVector2Array([Vector2.ZERO, Vector2.DOWN, Vector2(0.5, 0.0),
		Vector2(0.5, 1.0), Vector2.RIGHT, Vector2.ONE]) # 单个接触沿坡和法线的归一化范围。
	var index_pattern := PackedInt32Array([0, 1, 2, 2, 1, 3, 2, 3, 4, 4, 3, 5]) # 两段坡边的四个三角形。
	_uv_template.clear()
	_index_template.clear()
	for contact: int in range(MAX_CONTACTS): # 任意单批最多可占满同帧全局预算。
		var base: int = contact * Batch.VERTICES_PER_CONTACT # 此接触的世界顶点基址。
		_uv_template.append_array(uv_pattern)
		for index: int in index_pattern: # 索引顺序与提交接触的顺序一致。
			_index_template.append(base + index)

## 用 [param order] 显式约束世界画布深度，以本场 [param material] 绘制。
func _create_batch(order: int, material: ShaderMaterial) -> Batch:
	var batch: Batch = Batch.new() # 与角色节点无父子关联，不参加点选或动画复制。
	batch.item = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(batch.item, get_canvas_item())
	RenderingServer.canvas_item_set_z_index(batch.item, order)
	RenderingServer.canvas_item_set_material(batch.item, material.get_rid())
	return batch

## 开始一帧的接触采样，[param wind_x] 是横风像素/秒，[param gust] 是归一化阵风。
func begin_step(wind_x: float, gust: float) -> void:
	_shadow.reset()
	for rim: Batch in _rims: # 清掉上一帧已离地或离场的足缘。
		rim.reset()
	_remaining = MAX_CONTACTS
	_rim_material.set_shader_parameter(&"wind_breakup", clampf(wind_x / 260.0, -1.0, 1.0) * gust)

## 将 [param point] 的真实脚点投影至 [param lane]；[param width] 为世界全宽，[param weight] 为 0..1 接触强度。
## [param pulse] 为近期同源脚步或落地的归一响应，[param rolling] 选择贴地窄带。
## [param on_ground] 表示 [param point] 已取自同一行的坡面脚点，可直接复用。
func add_contact(point: Vector2, lane: int, width: float, weight: float, pulse: float = 0.0,
		rolling: bool = false, on_ground: bool = false) -> void:
	if _remaining <= 0 or lane < 0 or lane >= _rims.size() or weight <= 0.01:
		return
	var snow: Vector2 = _surface.snow_at_contact(point, lane) # 从本行权威格位读取松雪和压实。
	if snow.x < 0.0:
		return
	var radius: float = minf(width * 0.5, _board_right - point.x) # 裁去备战区一侧，保留场内脚点。
	if radius < 2.0:
		return
	var ground: Vector2 = point if on_ground else _surface.ground_point(point.x, lane) # 角色实际脚点已由接触记录采样。
	var offset: Vector2 = point - ground # 保留植株槽位与角色原影子给出的美术锚点。
	var left: Vector2 = _surface.ground_point(point.x - radius, lane) + offset # 左端真实坡点。
	var right: Vector2 = _surface.ground_point(point.x + radius, lane) + offset # 右端真实坡点。
	var slope: Vector2 = (right - left).normalized() # 世界向右的切线。
	var down := Vector2(-slope.y, slope.x) # 朝画面前方的坡面法线。
	var style := Color(snow.x, snow.y, float(rolling), weight) # 着色器中各分量表示不同的接触量。
	var bottom: bool = lane == _rims.size() - 1 # 最下一行的前缘高度更小。
	_remaining -= 1
	_shadow.append(left, point, right, down * -3.5, down * (4.5 + pulse), style)
	if snow.x > 0.025:
		var rise: float = lerpf(1.6, 5.7, snow.x) * (1.0 - 0.49 * snow.y) # 松雪越薄或越压实，鞋边越低。
		if bottom:
			rise = minf(rise, 2.5)
		style.a *= 0.80 if bottom else 1.0
		_rims[lane].append(left, point, right, down * -rise, down * 3.0, style)

## 将本帧批次交给渲染服务器。不写入角色自己的影子与材质。
func finish_step() -> void:
	_shadow.upload(_uv_template, _index_template)
	for rim: Batch in _rims: # 一行至多提交一条绘制命令。
		rim.upload(_uv_template, _index_template)

## 解绑所有直接创建的画布 RID，天气控制器退出时统一释放。
func _exit_tree() -> void:
	if _shadow != null:
		RenderingServer.free_rid(_shadow.item)
	for rim: Batch in _rims: # 阶段切换和场景退出共用画布生命周期。
		RenderingServer.free_rid(rim.item)
	_rims.clear()
