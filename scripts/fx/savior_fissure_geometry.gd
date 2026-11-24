## 六束世界轨迹共用的索引 Ribbon 网格。CPU 只在拓扑变化时重新提交，热衰减由着色器处理。
extends RefCounted

## 单段热量存在的战斗秒数。
const LIFETIME_SECONDS := 1.8
## 单束的弧长状态和确定性分叉。
const Stroke = preload("res://scripts/fx/savior_fissure_stroke.gd")
## 同一技能最多接收的真实柱底数量。
const BEAM_COUNT := 6
## 压力条件下最多保留最近三轮的余热。
const STROKE_LIMIT := BEAM_COUNT * 3
## Ribbon 半包络宽度，相对实际世界格宽。材质只填窄裂芯与周边热带。
const ENVELOPE_CELLS := 0.09
## 斜接最大倍率，避免锐角产生过长并覆盖别处的尖刺。
const MITER_LIMIT := 1.28
## 每顶点第四组数据使用四个完整浮点数，保留跨帧插值后的出生秒数。
const MESH_FLAGS := Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)

## 当前整张网格所用的世界格宽。
var _cell_span := 1.0
## 送进网格前粗裁，实际石砖外沿由材质按权威地面多边形裁切。
var _clip: Rect2
## 所有尚可能存在余热的裂隙，包括先前已经收束的扫掠。
var _strokes: Array[Stroke] = []
## 目前仍接收真实接触点的束，结束施法时只清这组引用。
var _current: Array[Stroke] = []
## 本场的施法序号，用于打散不同轮次和束的图案。
var _cast := 0
## 样点增加、容量淘汰或退场时才设置。
var _dirty := false
## 动态网格的世界顶点位置。
var _vertices := PackedVector2Array()
## x 为以格宽归一的弧长，y 为包络宽度内的有符号位置。
var _uv := PackedVector2Array()
## 每四值为一顶点的出生秒、宽度倍率、初温和稳定种子。
var _heat := PackedFloat32Array()
## 共享相邻横截面的三角形，式样不按照片段重复分配顶点。
var _indices := PackedInt32Array()
## 已向渲染器提交的新表面数，回收空表面不计一次上传。
var _uploads := 0

## 从 [param cell_span] 和 [param floor_bounds] 建立采样与粗裁边界，单位为世界像素。
func configure(cell_span: float, floor_bounds: Rect2) -> void:
	_cell_span = maxf(1.0, cell_span)
	_clip = floor_bounds.grow(_cell_span * ENVELOPE_CELLS * MITER_LIMIT)

## [param points] 是当前轮的世界柱底，[param now] 是战斗秒。之前的裂隙继续冷却。
func begin(points: PackedVector2Array, now: float) -> void:
	end()
	var beam_count: int = mini(points.size(), BEAM_COUNT) # 仅接入实际有提供坐标的光束。
	while _strokes.size() + beam_count > STROKE_LIMIT:
		_strokes.pop_front()
		_dirty = true
	_cast += 1
	for index: int in range(beam_count): # 世界脚点的顺序决定稳定的各束种子。
		var stroke := Stroke.new(points[index], now, _cell_span, _clip, _cast * BEAM_COUNT + index) # 此轮新路径。
		_strokes.append(stroke)
		_current.append(stroke)

## 用 [param now] 秒时刻的真实 [param points] 延伸当前轨迹。
func sample(points: PackedVector2Array, now: float) -> void:
	for index: int in range(mini(_current.size(), points.size())): # 跟踪顺序与真实光柱索引相同。
		_dirty = _current[index].sample(points[index], now) or _dirty

## 收回柱身时停止喂入轨迹，保留旧网格的独立余热。
func end() -> void:
	_current.clear()

## 根据 [param now] 移除已过期的几何，但保留仍在移动的柱底采样器。
func expire(now: float) -> void:
	var cutoff: float = now - LIFETIME_SECONDS # 所有出生时间早于该值的样点均已熄灭。
	for index: int in range(_strokes.size() - 1, -1, -1): # 倒序回收期间保留其他轨迹的插入顺序。
		var stroke: Stroke = _strokes[index] # 单独回收受影响的年龄区间。
		_dirty = stroke.expire(cutoff) or _dirty
		if stroke.knots.is_empty() and stroke.branches.is_empty() and not _current.has(stroke):
			_strokes.remove_at(index)

## 换关或重启时丢弃所有世界轨迹，下一次提交同步清除表面。
func clear() -> void:
	_strokes.clear()
	_current.clear()
	_cast = 0
	_dirty = true

## 只在新增或回收几何时重建 [param mesh] 的唯一表面；空表面不再触发绘制。
func flush(mesh: ArrayMesh) -> void:
	if not _dirty:
		return
	_dirty = false
	_vertices.clear()
	_uv.clear()
	_heat.clear()
	_indices.clear()
	for stroke: Stroke in _strokes: # 每束单独连接；相邻束和先前施法之间从不接线。
		_build_stroke(stroke)
	var has_geometry: bool = not _indices.is_empty() # 没有可见索引时无需分配新缓冲。
	if mesh.get_surface_count() > 0:
		mesh.clear_surfaces()
	if not has_geometry:
		return
	var arrays: Array = [] # Godot Canvas 二维 ArrayMesh 的顶点属性和索引表。
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_TEX_UV] = _uv
	arrays[Mesh.ARRAY_CUSTOM0] = _heat
	arrays[Mesh.ARRAY_INDEX] = _indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, MESH_FLAGS)
	_uploads += 1

## 返回本批实测几何数量、容量预算及缓冲估算，供本机验收记录。
@warning_ignore("integer_division")
func profile_snapshot() -> Dictionary:
	var samples := 0 # 仍供插值或绘制的主裂纹样点。
	var branches := 0 # 独立存活分叉数。
	for stroke: Stroke in _strokes: # 统计既有余热和当前扫掠。
		samples += stroke.knots.size() - stroke.first
		branches += stroke.branches.size()
	return {
		"active_samples": samples, "active_branches": branches, "strokes": _strokes.size(),
		"triangles": _indices.size() / 3, "vertices": _vertices.size(), "uploads": _uploads,
		"mesh_bytes": _vertices.size() * 32 + _indices.size() * 2,
		"sample_limit": STROKE_LIMIT * Stroke.MAX_KNOTS, "branch_limit": STROKE_LIMIT * Stroke.MAX_BRANCHES,
		"triangle_limit": STROKE_LIMIT * (Stroke.MAX_KNOTS - 1 + Stroke.MAX_BRANCHES * (Stroke.BRANCH_KNOTS - 1)) * 2,
	}

## 把 [param stroke] 的主裂隙及附着支纹写成彼此独立的三角形条带。
func _build_stroke(stroke: Stroke) -> void:
	var seed: float = Stroke.unit_hash(stroke.seed, -6) # 整道主纹用固定材质种子。
	var connected := false # 出界再返入时另起片段，保留裁边的相邻端点。
	for index: int in range(stroke.first + 1, stroke.knots.size()): # 相邻主纹段共享一组横截面。
		if stroke.runs[index - 1] != stroke.runs[index]:
			connected = false
			continue
		var previous: Vector2 = Vector2(stroke.knots[index - 1].x, stroke.knots[index - 1].y) # 本段起点。
		var current: Vector2 = Vector2(stroke.knots[index].x, stroke.knots[index].y) # 本段终点。
		if not _in_board(previous, current):
			connected = false
			continue
		if not connected:
			_main_pair(stroke, index - 1, seed)
		_main_pair(stroke, index, seed)
		_join_pairs()
		connected = true
	for index: int in range(stroke.branches.size()): # 冷却、距离裁剪及跨度同样在 GPU 材质中生效。
		_branch_strip(stroke, index)

## 为 [param stroke] 的第 [param index] 个样点提交横截面，[param seed] 跨节点保持恒定。
func _main_pair(stroke: Stroke, index: int, seed: float) -> void:
	var knot: Vector4 = stroke.knots[index] # 轨迹中心、出生战斗秒和累计弧长。
	var before: Vector4 = knot # 同一连接段的前邻点，断点不计算上一道地表的切线。
	var after: Vector4 = knot # 同一连接段的后邻点，尾端随后退化为前段方向。
	if index > 0 and stroke.runs[index - 1] == stroke.runs[index]:
		before = stroke.knots[index - 1]
	if index + 1 < stroke.knots.size() and stroke.runs[index + 1] == stroke.runs[index]:
		after = stroke.knots[index + 1]
	var along: float = knot.w / _cell_span # 格宽归一的连续弧长。
	var grain: int = roundi(along / Stroke.STEP_IN_CELLS) # 样点的稳定位置索引。
	var width: float = lerpf(0.65, 1.23, Stroke.unit_hash(stroke.seed + 11, grain)) # 主缝构造的细窄变化。
	var strength: float = lerpf(0.70, 1.0, Stroke.unit_hash(stroke.seed + 93, grain)) # 材料不同处的起始热量。
	_pair(Vector2(knot.x, knot.y), Vector2(before.x, before.y), Vector2(after.x, after.y), along, Vector4(knot.z, width, strength, seed))

## 提交 [param stroke] 的第 [param index] 道支裂纹，根部接主缝，尖端逐步收细。
func _branch_strip(stroke: Stroke, index: int) -> void:
	var first: int = index * Stroke.BRANCH_KNOTS # 连续四个点的起始索引。
	var points: PackedVector2Array = stroke.branch_points # 共用固定容量的缓存。
	var shape: Vector4 = stroke.branches[index] # 出生秒、起始弧长、初始宽度和材质种子。
	var along: float = shape.y / _cell_span # 保留主纹根处的弧长相位。
	if not _clip.grow(_cell_span * 0.54).has_point(points[first]):
		return
	for side_index: int in range(Stroke.BRANCH_KNOTS): # 三个笔直小段在折角共享横截面。
		var point: Vector2 = points[first + side_index] # 当前分叉折线的顶点中心。
		var left: Vector2 = points[first + maxi(side_index - 1, 0)] # 同一道分叉的前一个节点。
		var right: Vector2 = points[first + mini(side_index + 1, Stroke.BRANCH_KNOTS - 1)] # 同一道分叉的后一个节点。
		var taper: float = 1.0 - float(side_index) / (Stroke.BRANCH_KNOTS - 1) # 从根部向细尖衰减。
		along += left.distance_to(point) / _cell_span
		_pair(point, left, right, along, Vector4(shape.x, shape.z * lerpf(0.09, 1.0, taper), taper * 0.57, shape.w))
		if side_index > 0:
			_join_pairs()

## [param center]、[param left]、[param right] 确定横截面。写入 [param along] 和 [param attributes]。
func _pair(center: Vector2, left: Vector2, right: Vector2, along: float, attributes: Vector4) -> void:
	var incoming: Vector2 = (center - left).normalized().orthogonal() # 前一段的世界法线。
	var outgoing: Vector2 = (right - center).normalized().orthogonal() # 后一段的世界法线。
	var side: Vector2 = (incoming + outgoing).normalized() # 共享斜接保证两片相邻三角形不露缝。
	if side.is_zero_approx():
		side = outgoing
	var miter: float = 1.0 / maxf(1.0 / MITER_LIMIT, maxf(side.dot(incoming), side.dot(outgoing))) # 截止过锐的斜接。
	var offset: Vector2 = side * (_cell_span * ENVELOPE_CELLS * miter) # 两侧网格的世界偏移。
	_vertices.append(center - offset)
	_vertices.append(center + offset)
	_uv.append(Vector2(along, -1.0))
	_uv.append(Vector2(along, 1.0))
	for _side_index: int in range(2): # 同一横截面左右点使用完全相同的时间和材料参数。
		_heat.append(attributes.x)
		_heat.append(attributes.y)
		_heat.append(attributes.z)
		_heat.append(attributes.w)

## 用最后两个横截面的四个顶点形成共享边的三角形。
func _join_pairs() -> void:
	var base: int = _vertices.size() - 4 # 最近连接的第一个横截面。
	_indices.append(base)
	_indices.append(base + 1)
	_indices.append(base + 2)
	_indices.append(base + 2)
	_indices.append(base + 1)
	_indices.append(base + 3)

## [param a] 至 [param b] 的端点包围盒是否可能经过棋盘，包括两端都在棋盘外的穿越。
func _in_board(a: Vector2, b: Vector2) -> bool:
	return maxf(a.x, b.x) >= _clip.position.x and minf(a.x, b.x) <= _clip.end.x \
		and maxf(a.y, b.y) >= _clip.position.y and minf(a.y, b.y) <= _clip.end.y
