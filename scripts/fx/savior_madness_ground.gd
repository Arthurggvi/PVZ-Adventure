## 没入疯狂的石面。接收真实触地点，在角色下方提交裂隙和可遮挡的余热。
extends MultiMeshInstance2D

## 分段弧长采样、冷却和共享三角形网格。
const FissureGeometry = preload("res://scripts/fx/savior_fissure_geometry.gd")
## 教堂地表裁剪数组的容量，与裂隙材质的行数一致。
const FLOOR_ROW_CAPACITY := 8

## 地贴原点固定在首次触地的世界脚点。
var _impact_point := Vector2.ZERO
## 真实棋盘外包矩形，用于粗裁和限制世界合成的余热读取区域。
var _floor := Rect2()
## 柱底接触半径，单位为世界像素。
var _radius := 1.0
## 当前施法是否已触地并向采样器提交实迹。
var _tracing := false
## 跟随实际命中所在的物理步，单位为战斗秒。
var _clock := 0.0
## 本场已经收到的触地更新数，在暂停时应保持不变。
var _contact_updates := 0
## 本战斗独占的有限轨迹记录。
var _geometry := FissureGeometry.new()
## 持久网格，只在样点新增或过期时提交表面。
var _mesh := ArrayMesh.new()

## 当前柱底及触地裂光的材质。
@onready var _contact := material as ShaderMaterial
## 六条主裂和所有分支使用的地表绘制节点。
@onready var _fissures: MeshInstance2D = $Fissures
## 按各段出生时间衰减地表材质和余热的共用着色器参数。
@onready var _fissure_material := _fissures.material as ShaderMaterial

## [param ground_y] 和 [param beam_scale] 标定原有柱脚，[param board] 提供实测行边界和格宽。
func configure(ground_y: float, beam_scale: Vector2, board: BoardRuntime) -> void:
	_contact.set_shader_parameter(&"ground_y", ground_y)
	_contact.set_shader_parameter(&"section_in_radii", beam_scale)
	_fissures.mesh = _mesh
	_fissure_material.set_shader_parameter(&"lifetime", FissureGeometry.LIFETIME_SECONDS)
	_configure_floor(board)

## 记录 [param points] 的撞地锚点和接触 [param radius]。上一轮余热继续消散。
func begin(points: PackedVector2Array, radius: float) -> void:
	_impact_point = points[0]
	_radius = radius
	end_trace()

## 每个命中物理步收到实际 [param points]，保持低帧率下路径的真实转折。
func track(points: PackedVector2Array) -> void:
	_contact_updates += 1
	if not _tracing:
		_geometry.begin(points, _clock)
		_tracing = true
	_geometry.sample(points, _clock)

## 停止写入新的接触点，网格中的余热仍照常冷却。
func end_trace() -> void:
	_geometry.end()
	_tracing = false

## [param lead_point] 是当前首束的柱底，[param age] 是触地后的秒数，供原有冲击材质使用。
func present(lead_point: Vector2, age: float) -> void:
	_contact.set_shader_parameter(&"seconds_after_impact", age)
	_contact.set_shader_parameter(&"impact_offset", (lead_point - _impact_point) / _radius)

## 用 [param delta] 推进冷却，柱身退场后仍执行直到最后一道裂隙熄灭。
func advance(delta: float) -> void:
	_clock += delta

## 提交本帧产生或过期的几何；冷却期间每帧只更新时间。
func flush() -> void:
	_geometry.expire(_clock)
	_geometry.flush(_mesh)
	var active: bool = _mesh.get_surface_count() > 0 # 待冷却图元全部移除后停止绘制。
	_fissures.visible = active
	if active:
		_fissure_material.set_shader_parameter(&"battle_clock", _clock)

## 换场和离开活动战斗时同步清除所有地表余热。
func clear_fissures() -> void:
	_geometry.clear()
	_tracing = false
	_clock = 0.0
	_contact_updates = 0
	flush()

## 返回世界合成需检查 Alpha 余热的世界范围。没有裂隙时返回空矩形。
func heat_bounds() -> Rect2:
	if not _fissures.visible:
		return Rect2()
	var envelope: AABB = _mesh.get_aabb() # 只检查活跃几何的包围区域。
	return _floor.intersection(Rect2(Vector2(envelope.position.x, envelope.position.y),
		Vector2(envelope.size.x, envelope.size.y)).grow(1.0))

## 返回当前共用几何和上传统计，采集时不读取 GPU 贴图。
func profile_snapshot() -> Dictionary:
	var stats: Dictionary = _geometry.profile_snapshot() # 同一帧的缓存和轨迹输入数量。
	stats["contact_updates"] = _contact_updates
	return stats

## 取 [param board] 上实际石砖行的左右轮廓。行内的细砖缝属于同一连续石面。
func _configure_floor(board: BoardRuntime) -> void:
	var cells: Array[PlantCell] = board.cells() # 格宽与粗裁边界来自同一棋盘。
	_floor = BoardQueries.bounds(cells)
	var width_sum := 0.0 # 汇总已应用战场变换后的格宽。
	for cell: PlantCell in cells: # 网格等比例适配不同版面和相机。
		width_sum += cell.get_global_rect().size.x
	_geometry.configure(maxf(1.0, width_sum / maxi(1, cells.size())), _floor)
	var tops := PackedVector4Array() # 每行依次保存顶底 Y 和顶沿的左右 X。
	var bottoms := PackedVector2Array() # 各行底沿的左右 X，控制透视斜边。
	for row: Array in board.rows(): # 教堂每行边界与可交互地块同源。
		var corners: PackedVector2Array = _row_corners(row) # 几何面积外的墙和装饰不能留痕。
		if corners.is_empty():
			continue
		var limits := Rect2(corners[0], Vector2.ZERO) # 当前行在世界坐标中的上下沿。
		for point: Vector2 in corners: # 范围只用于识别各行的顶、底边。
			limits = limits.expand(point)
		var top := Vector2(INF, -INF) # 取顶边最左和最右的原始顶点。
		var bottom := top # 取底边最左和最右的原始顶点。
		for point: Vector2 in corners: # 根据地块实际的透视边缘约束裂隙。
			if is_equal_approx(point.y, limits.position.y):
				top = Vector2(minf(top.x, point.x), maxf(top.y, point.x))
			if is_equal_approx(point.y, limits.end.y):
				bottom = Vector2(minf(bottom.x, point.x), maxf(bottom.y, point.x))
		if not limits.has_area() or top.x >= top.y or bottom.x >= bottom.y:
			continue
		tops.append(Vector4(limits.position.y, limits.end.y, top.x, top.y))
		bottoms.append(bottom)
		if tops.size() >= FLOOR_ROW_CAPACITY:
			break
	_fissure_material.set_shader_parameter(&"floor_row_count", tops.size())
	tops.resize(FLOOR_ROW_CAPACITY)
	bottoms.resize(FLOOR_ROW_CAPACITY)
	_fissure_material.set_shader_parameter(&"floor_row_tops", tops)
	_fissure_material.set_shader_parameter(&"floor_row_bottoms", bottoms)

## 返回 [param row] 的地块多边形顶点，已转换为世界坐标。矩形格沿用自身范围。
func _row_corners(row: Array) -> PackedVector2Array:
	var corners := PackedVector2Array() # 只在战场装配阶段收集一次。
	for cell: PlantCell in row: # 真实种植区允许不同的局部裁边。
		var transform_to_world: Transform2D = cell.get_global_transform() # 不混入相机震动。
		var outline: PackedVector2Array = cell.board_definition.hit_polygon # 地块自身的实际边缘。
		if outline.is_empty():
			outline = PackedVector2Array([Vector2.ZERO, Vector2(cell.size.x, 0.0), cell.size, Vector2(0.0, cell.size.y)])
		for point: Vector2 in outline: # 每个顶点都与棋盘的世界裁边保持同一坐标系。
			corners.append(transform_to_world * point)
	return corners
