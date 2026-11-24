## 银针和极光薄带的无状态表现。外部施放时钟给出飞行年龄，落点移动时只牵引弧线末端。
extends Node2D

## 同一网格绘制青紫折面、银线和局部针尖薄晕。
const RIBBON_SHADER: Shader = preload("res://shaders/adventure/eve_aurora_ribbon.gdshader")
## 命中后最后一截薄带收向冰核的战斗秒数。
const RETRACT_SECONDS := 0.105
## 完整拖尾的最大长度，单位为一格宽。
const TRAIL_LENGTH_UNITS := 2.16
## 银针外缘、银白芯与横向星芒只在真实尖点之后绘制，坐标以一格为单位。
static var _needle := PackedVector2Array([Vector2.ZERO, Vector2(-0.085, 0.036), Vector2(-0.43, 0.0), Vector2(-0.085, -0.036)])
## 纯银色的细芯。
static var _core := PackedVector2Array([Vector2.ZERO, Vector2(-0.024, 0.014), Vector2(-0.29, 0.0), Vector2(-0.024, -0.014)])
## 让针头在远处仍可辨识的一道横光。
static var _glint := PackedVector2Array([Vector2(-0.018, -0.052), Vector2(-0.006, 0.0), Vector2(-0.018, 0.052), Vector2(-0.029, 0.0)])

## 带状网格在空中层持有，不产生碰撞。
var _ribbon: MeshInstance2D
## 一发一份材质参数，折面种子不参与落点或魅惑抽样。
var _material: ShaderMaterial
## 预采样的局部轨迹点和一一对应的累计弧长。
var _points := PackedVector2Array()
## 每一点从出射锚开始走过的像素距离，数组和 [member _points] 同长。
var _lengths := PackedFloat32Array()
## 演出坐标系下的完整弧长。
var _length := 0.0
## 一格宽的局部像素数，决定针头及尾带尺寸。
var _unit := 1.0
## 起飞到命中的战斗秒数。
var _duration := 1.0
## 当前针尖的局部位置和切线。
var _head := Vector2.ZERO
## 银针沿弧线的当前单位方向。
var _direction := Vector2.DOWN
## 只在起飞后、接触前绘制银针。触地时由冰内主星接替。
var _airborne := false
## 上次上传的目标端位移，用于普通静止棋盘跳过重复提交。
var _landing_offset := Vector2.ZERO

## 以局部 [param from]、[param to] 与格宽 [param unit] 生成固定曲线。
## [param duration] 为飞行秒数，[param visual_seed] 只决定折面相位及轻微侧弯。
func configure(from: Vector2, to: Vector2, unit: float, duration: float, visual_seed: int) -> void:
	_unit = maxf(1.0, unit)
	_duration = maxf(0.001, duration)
	_ribbon = MeshInstance2D.new()
	_ribbon.show_behind_parent = true
	_material = ShaderMaterial.new()
	_material.shader = RIBBON_SHADER
	_ribbon.material = _material
	add_child(_ribbon)
	var random := RandomNumberGenerator.new() # 材质专用随机流。
	random.seed = visual_seed
	_material.set_shader_parameter(&"fold_phase", random.randf_range(-PI, PI))
	_build_strip(from, to, random)
	_material.set_shader_parameter(&"path_units", _length / _unit)
	hide()

## 在 [param from] 和 [param to] 间采样一次弧长，使用 [param random] 给斜雨加入幅度很小的侧弯。
func _build_strip(from: Vector2, to: Vector2, random: RandomNumberGenerator) -> void:
	var span: Vector2 = to - from # 斜落方向，弯折沿它的法线展开。
	var chord: float = span.length() # 端点重合时不生成零长度网格。
	_points.append(from)
	_lengths.append(0.0)
	if chord <= 0.001:
		return
	var lean: float = -1.0 if random.randf() < 0.5 else 1.0 # 每发保持自身偏转方向。
	var bow: float = minf(chord * 0.055, _unit * 0.29) # 轻微风偏，不把下坠折成抛物线齐射。
	var bend: Vector2 = span.normalized().orthogonal() * lean * bow # 曲线中点偏离弦的像素。
	var segments: int = clampi(ceili(chord / (_unit * 0.16)), 12, 96) # 兼顾短程轮廓及单次施放开销。
	for index: int in range(1, segments + 1): # 末点直接写入地表锚，避免累加误差。
		var t: float = float(index) / float(segments) # 固定曲线参数。
		var point: Vector2 = to if index == segments else from.lerp(to, t) + 4.0 * t * (1.0 - t) * bend # 本次采样点。
		_length += _points[-1].distance_to(point)
		_points.append(point)
		_lengths.append(_length)

	var vertices := PackedVector2Array() # 每个采样点沿法线展开左右两个顶点。
	var uvs := PackedVector2Array() # X 为原始归一弧长，Y 为薄带横向坐标。
	var indices := PackedInt32Array() # 一段带由两个索引三角形组成。
	for index: int in range(_points.size()): # 两端用单边切线，中间跨两个采样点。
		var prev: Vector2 = _points[maxi(index - 1, 0)] # 法线的前一采样点。
		var next: Vector2 = _points[mini(index + 1, segments)] # 法线的后一采样点。
		var half_span: Vector2 = (next - prev).normalized().orthogonal() * (_unit * 0.115) # 仅为实际着色预留窄条范围。
		var arc: float = _lengths[index] / _length # 收尾时保持此坐标及折纹稳定。
		vertices.append(_points[index] - half_span)
		vertices.append(_points[index] + half_span)
		uvs.append(Vector2(arc, 0.0))
		uvs.append(Vector2(arc, 1.0))
		if index < segments:
			var base: int = 2 * index # 当前窄条段的首顶点。
			indices.append_array(PackedInt32Array([base, base + 1, base + 2, base + 2, base + 1, base + 3]))
	var arrays: Array = [] # 只上传二维顶点、纹理坐标和索引。
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var strip := ArrayMesh.new() # 每个投射物一张固定窄网格。
	strip.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_ribbon.mesh = strip

## 取样 [param seconds] 战斗秒时的针头和拖尾；[param landing_offset] 为平台移动后的末端局部位移。
func set_age(seconds: float, landing_offset: Vector2) -> void:
	if seconds < 0.0 or seconds >= _duration + RETRACT_SECONDS or _length <= 0.0:
		hide()
		return
	show()
	if landing_offset != _landing_offset:
		_landing_offset = landing_offset
		_material.set_shader_parameter(&"landing_offset", landing_offset)
	var fraction: float = clampf(seconds / _duration, 0.0, 1.0) # 起飞即有速度，接近地表时继续加速。
	var head: float = _length * fraction * (0.53 + 0.47 * fraction) # 入场后加速下坠，针尖与拖尾共用弧长。
	var retract: float = clampf((seconds - _duration) / RETRACT_SECONDS, 0.0, 1.0) # 命中后向同一个点收。
	var tail: float = lerpf(maxf(0.0, head - _unit * TRAIL_LENGTH_UNITS), head,
		smoothstep(0.0, 1.0, retract)) # 收拢保留折纹相位并在锚点减速停住。
	_material.set_shader_parameter(&"head_u", head / _length)
	_material.set_shader_parameter(&"tail_u", tail / _length)
	_material.set_shader_parameter(&"flow", minf(seconds, _duration) * 2.0)
	_material.set_shader_parameter(&"collapse", retract)
	if seconds < _duration:
		_airborne = true
		_sample_head(head)
		queue_redraw()
	elif _airborne:
		_airborne = false
		queue_redraw()

## 沿累计弧长 [param distance] 二分找到针尖，位置与方向同步包含平台运动。
func _sample_head(distance: float) -> void:
	var index: int = clampi(_lengths.bsearch(distance), 1, _lengths.size() - 1) # 当前落在的采样段。
	var span: float = maxf(0.000001, _lengths[index] - _lengths[index - 1]) # 短段仍能稳定插值。
	var amount: float = clampf((distance - _lengths[index - 1]) / span, 0.0, 1.0) # 本段内的局部比例。
	_head = _points[index - 1].lerp(_points[index], amount) + _landing_offset * (distance / _length)
	_direction = (_points[index] - _points[index - 1] + _landing_offset * (span / _length)).normalized()

## 返回最后一段的入射方向，将 [param landing_offset] 的末端牵引一并计入。
func impact_tangent(landing_offset: Vector2) -> Vector2:
	if _points.size() < 2:
		return Vector2.DOWN
	var span: float = (_length - _lengths[-2]) / _length # 平台位移在最后一个采样段中的份额。
	var direction: Vector2 = _points[-1] - _points[-2] + landing_offset * span # 末段的实际屏幕方向。
	return direction.normalized() if not direction.is_zero_approx() else Vector2.DOWN

## 绘制银针，所有顶点都位于当前尖点或其后方。
func _draw() -> void:
	if not _airborne:
		return
	draw_set_transform(_head, _direction.angle(), Vector2.ONE * _unit)
	draw_colored_polygon(_needle, Color(0.57, 0.95, 0.98))
	draw_colored_polygon(_core, Color(0.94, 1.0, 0.99))
	draw_colored_polygon(_glint, Color(0.85, 1.0, 0.99, 0.78))
