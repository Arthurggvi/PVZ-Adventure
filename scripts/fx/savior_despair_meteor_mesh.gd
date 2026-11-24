## 四束从拱顶垂落的血光。红灯与材质前沿采样同一条世界曲线。
extends MeshInstance2D

## 每条带的等弧长分段数。
const SEGMENTS := 20
## 贝塞尔到累计弧长映射的查表精度。
const LOOKUP_STEPS := 64
## 允许的同时坠落数量与材质的四个光头槽一致。
const CAPACITY := 4
## 光束从拱顶抽回地面的总战斗秒数。
const RELEASE_SECONDS := 0.50

## 一条由原始落点、原始贝塞尔和归一化弧长表描述的带。
class FlightPath:
	## 世界空间中的贝塞尔起点、控制点、末端。
	var start: Vector2
	var control: Vector2
	var end: Vector2
	## t 均匀采样时对应的归一化弧长。
	var lengths := PackedFloat32Array()

	## 在二次贝塞尔的 [param t] 位置获取中心。
	func sample(t: float) -> Vector2:
		return start.lerp(control, t).lerp(control.lerp(end, t), t)

	## 在二次贝塞尔的 [param t] 位置获取屏幕宽度的世界法向。
	func normal(t: float) -> Vector2:
		return (control - start).lerp(end - control, t).normalized().orthogonal()

## 色带在同一个场景本地网格中重建，每轮只提交一个表面。
var _ribbon := ArrayMesh.new()
## 当前四条带及其光头查表。
var _curves: Array[FlightPath] = []
## 当前帧前沿的曲线参数，实景红灯使用相同位置。
var _front_param := 0.0
## 采样期间实际提交网格的次数，供性能验收读取。
var generation_count := 0
## 当前一轮的发光材质。
@onready var _material := material as ShaderMaterial

## 入树后使用持久网格和独占材质。
func _ready() -> void:
	mesh = _ribbon
	visible = false

## 从真实 [param points] 和平均格宽 [param span] 构造合批带，仅在施法起手调用一次。
func begin(points: PackedVector2Array, span: float) -> void:
	_curves.clear()
	_ribbon.clear_surfaces()
	if points.is_empty():
		visible = false
		return
	var arrays: Array = [] # 2D Canvas 的顶点、UV、颜色和共享索引。
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array()
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array()
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray()
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array()
	for index: int in range(mini(points.size(), CAPACITY)): # 每束的索引区间始终独立。
		var curve: FlightPath = _make_curve(points[index], span, index) # 沿用原有效果使用的入射曲线。
		_curves.append(curve)
		_write_strip(curve, span, index, arrays)
	_ribbon.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	generation_count += 1
	visible = true

## [param elapsed] 和 [param fall_seconds] 直接使用坠落结算的战斗秒。
func present(elapsed: float, fall_seconds: float) -> void:
	visible = not _curves.is_empty()
	if not visible:
		return
	var ratio: float = clampf(elapsed / fall_seconds, 0.0, 1.0) # 用现有战斗秒推进下沿，越近地面落得越快。
	_front_param = pow(ratio, 1.78)
	var param: float = _front_param * LOOKUP_STEPS # 与 CPU 上的发光点对应同一条曲线。
	var low: int = mini(floori(param), LOOKUP_STEPS - 1) # 光束前沿落在这一段查表内。
	var heads := Vector4.ZERO # Shader 一次收到四束独立弧长。
	for index: int in range(_curves.size()): # 不上传顶点或索引。
		var lengths: PackedFloat32Array = _curves[index].lengths # 共用初始化时写好的累计路程。
		heads[index] = lerpf(lengths[low], lengths[low + 1], param - low)
	_material.set_shader_parameter(&"head_arc", heads)
	_material.set_shader_parameter(&"flight_time", elapsed)
	_material.set_shader_parameter(&"shaft_drain", 0.0)
	_material.set_shader_parameter(&"shaft_energy", smoothstep(0.025, 0.25, ratio) * lerpf(0.71, 1.0, ratio))

## 返回第 [param index] 束这一帧的世界前沿坐标，供真实红光使用。
func front(index: int) -> Vector2:
	return _curves[index].sample(_front_param)

## 触地后向下撤去高处光束。[param age] 为触地战斗秒，[param fall_seconds] 延续亮纹相位。
## [param heads] 只将成功触地的束延伸至各自落点。
func release(age: float, fall_seconds: float, heads: Vector4) -> void:
	if _curves.is_empty():
		return
	if age >= RELEASE_SECONDS:
		clear()
		return
	_material.set_shader_parameter(&"head_arc", heads)
	_material.set_shader_parameter(&"flight_time", fall_seconds + age)
	_material.set_shader_parameter(&"shaft_drain", smoothstep(0.026, RELEASE_SECONDS, age))
	_material.set_shader_parameter(&"shaft_energy", 1.0 - smoothstep(0.22, RELEASE_SECONDS, age))

## 在退光完成或战斗被中断时停止绘制。持久网格可由下一次施法复用。
func clear() -> void:
	visible = false
	_curves.clear()

## 使用实际世界格心 [param point]、格宽 [param span] 与束号 [param index] 生成现有曲线及查表。
func _make_curve(point: Vector2, span: float, index: int) -> FlightPath:
	var curve := FlightPath.new() # 每束各自计算累计弧长。
	var angle_offset: float = -0.38 + 0.24 * float(index) # 拱顶有一点横向偏移，前沿仍主要向下。
	curve.start = point + Vector2(angle_offset, -4.65) * span
	curve.control = point + Vector2(angle_offset * 0.44 - 0.08, -2.32) * span
	curve.end = point
	curve.lengths.resize(LOOKUP_STEPS + 1)
	var last: Vector2 = curve.start # 上一个查表点仍用世界像素。
	var distance := 0.0 # 从起点沿曲线累计的世界距离。
	for step: int in range(1, LOOKUP_STEPS + 1): # 细查表与稀疏渲染截面分开。
		var point_on_curve: Vector2 = curve.sample(float(step) / LOOKUP_STEPS) # 贝塞尔均匀参数采样。
		distance += last.distance_to(point_on_curve)
		curve.lengths[step] = distance
		last = point_on_curve
	for step: int in range(1, curve.lengths.size()): # 归一化使命中点稳定落在 UV.x=1。
		curve.lengths[step] /= maxf(distance, 0.001)
	return curve

## 将 [param curve] 的独立条带按 [param span] 及 [param index] 追加到 [param arrays]。
func _write_strip(curve: FlightPath, span: float, index: int, arrays: Array) -> void:
	var positions: PackedVector2Array = arrays[Mesh.ARRAY_VERTEX] # 曲线两侧在世界空间中的位置。
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] # 纵向是累计路程，横向是零至一截面。
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] # 束号和稳定种子不参与最终调色。
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] # 相邻截面共用一条边。
	var cursor := 0 # 单调扫描弧长表，查找当前截面落在曲线何处。
	var data := Color(float(index) / 3.0, fposmod(curve.end.dot(Vector2(0.0133, 0.0239)), 1.0), 0.0, 1.0) # 画面帧之间保持不变的每束种子。
	for step: int in range(SEGMENTS + 1): # 均匀弧长截面使内部细丝的速度不被曲线拉扯。
		var arc: float = float(step) / SEGMENTS # 当前截面归一化弧长。
		while cursor < LOOKUP_STEPS - 1 and curve.lengths[cursor + 1] < arc:
			cursor += 1
		var ratio: float = inverse_lerp(curve.lengths[cursor], curve.lengths[cursor + 1], arc) # 两个实测查表点之间的分量。
		var t: float = (cursor + ratio) / LOOKUP_STEPS # 从弧长反查回原始贝塞尔。
		var center: Vector2 = curve.sample(t) # 左右点的中间位置是权威曲线。
		var side: Vector2 = curve.normal(t) * span * lerpf(0.258, 0.31, arc) # 横截面略微展开，到地面仍保有宽度。
		var pair: int = positions.size() # 这对顶点在合批网格中的首索引。
		positions.append(center - side)
		positions.append(center + side)
		uvs.append(Vector2(arc, 0.0))
		uvs.append(Vector2(arc, 1.0))
		colors.append(data)
		colors.append(data)
		if step > 0:
			indices.append_array(PackedInt32Array([pair - 2, pair - 1, pair, pair, pair - 1, pair + 1]))
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
