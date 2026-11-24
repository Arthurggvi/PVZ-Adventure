## 常驻风暴单个深度层的无纹理三角形批次。弧带、余烬和放电共用羽边笔画。
extends Node2D

## 单层笔画段上限，容纳三条弧、双段余烬和少量放电。
const CAPACITY := 160
## 单个笔画段两端各有五列顶点，从透明边缘渐变到细线芯。
const SECTION_SIZE := 5
## 五列之间的四个四边形各用两个三角形。
const INDICES_PER_STROKE := 24
## 正常轨道的分段数，穿越前后深度边界的段单独切开。
const ARC_STEPS := 14
## 每列相对中心的法向偏移比例。实体线芯集中在内侧三列。
const WIDTH_OFFSETS: Array[float] = [-1.0, -0.36, 0.0, 0.36, 1.0]
## 每列的独立透明度，外缘渐至全透明。
const ALPHA_WEIGHTS: Array[float] = [0.0, 0.88, 1.0, 0.88, 0.0]

## 固定批次共享的顶点、颜色和索引数组。
var _points := PackedVector2Array()
## 与顶点匹配的局部羽边和线芯颜色。
var _colors := PackedColorArray()
## 针对所有槽预制的三角形拓扑。
var _indices := PackedInt32Array()
## 当前帧已填充的笔画段数量。
var _used := 0
## 上次是否留下绘制命令，清空时仅重绘一次。
var _was_visible := false


## 一次性构建索引并分配两侧共用的笔画容量。
func _ready() -> void:
	_points.resize(CAPACITY * SECTION_SIZE * 2)
	_colors.resize(_points.size())
	_indices.resize(CAPACITY * INDICES_PER_STROKE)
	for stroke: int in CAPACITY: # 每段占连续两排横截面。
		var base: int = stroke * SECTION_SIZE * 2 # 笔画起点的一排。
		for column: int in range(SECTION_SIZE - 1): # 相邻的两列组成羽边条或线芯条。
			var vertex: int = base + column # 同一列在终点排向后偏移 SECTION_SIZE。
			var index: int = stroke * INDICES_PER_STROKE + column * 6 # 单列条的两个三角形。
			_indices[index] = vertex
			_indices[index + 1] = vertex + SECTION_SIZE
			_indices[index + 2] = vertex + 1
			_indices[index + 3] = vertex + 1
			_indices[index + 4] = vertex + SECTION_SIZE
			_indices[index + 5] = vertex + SECTION_SIZE + 1


## 复用各固定槽，本帧只提交更新过的笔画。
func begin_frame() -> void:
	_used = 0


## 提交活跃部分或清理刚消失的绘制。
func end_frame() -> void:
	if _used > 0 or _was_visible:
		queue_redraw()
	_was_visible = _used > 0


## 在 [param center] 绘制半径 [param radii]、倾角 [param tilt] 的一段投影轨迹。
## [param angles] 为起点弧度和长度，[param bend] 为连续扰动相位，[param width] 为局部像素半宽。
## [param rim]、[param core] 包含透明度，[param front] 决定使用虚拟深度的哪一半。
func add_arc(center: Vector2, radii: Vector2, tilt: float, angles: Vector2, bend: float,
		width: float, rim: Color, core: Color, front: bool) -> void:
	var start: float = fposmod(angles.x, TAU) # 归到单圈，避免跨越边界时丢一整段。
	var finish: float = start + angles.y # 弧短于半圈，所以最多穿越一次层边界。
	var first_front: bool = start < PI # 投影深度由 sin(角度) 的符号确定。
	var split: float = PI if first_front else TAU # 与身体所在平面相切的边界角。
	var limits := Vector2(start, minf(finish, split)) if front == first_front else Vector2(split, finish) # 前后两段共用同一个切换顶点。
	if limits.y <= limits.x:
		return
	var steps: int = maxi(1, ceili(ARC_STEPS * (limits.y - limits.x) / angles.y)) # 弧的一部分沿用近似恒定角步长。
	var from: Vector2 = center + _offset(limits.x, radii, bend).rotated(tilt) # 第一段起点。
	var from_fade: float = _arc_fade(limits.x, start, angles.y, bend) # 沿未切分的原弧渐变。
	var from_side: Vector2 = _normal(limits.x, radii, bend, tilt) * width * from_fade # 深度切线不会中断横截面。
	for step: int in range(1, steps + 1): # 顺着弧带从尾部采样到头部。
		var angle: float = lerpf(limits.x, limits.y, float(step) / steps) # 当前连续片段的终点弧度。
		var to: Vector2 = center + _offset(angle, radii, bend).rotated(tilt) # 当前弧段的终点。
		var to_fade: float = _arc_fade(angle, start, angles.y, bend) # 构成不规则断口和方向性渐变。
		var to_side: Vector2 = _normal(angle, radii, bend, tilt) * width * to_fade # 同一个截面与下一段共用值。
		_stroke(from, to, from_side, to_side, rim, core, Vector2(from_fade, to_fade))
		from = to
		from_side = to_side
		from_fade = to_fade


## 在 [param point] 上游沿 [param direction] 画出 [param length] 像素的尾迹。
## [param radius] 为亮点半宽，[param rim]、[param core] 含粒子当前透明度。
func add_ember(point: Vector2, direction: Vector2, length: float, radius: float, rim: Color, core: Color) -> void:
	if direction.is_zero_approx():
		return
	var side: Vector2 = direction.orthogonal() * radius # 朝速度切向羽化，尾端窄、火星头部宽。
	_stroke(point - direction * length, point, side * 0.09, side, rim, core, Vector2(0.0, 1.0))
	_stroke(point, point + direction * radius * 1.8, side, Vector2.ZERO, rim, core, Vector2(1.0, 0.0))


## 在 [param center] 的肩部或衣摆显示不规则细放电。
## [param seconds] 和 [param phase_offset] 控制不频繁的固定窗口，[param intensity]、[param rim] 决定外缘透明度。
func add_discharge(center: Vector2, seconds: float, phase_offset: float, intensity: float, rim: Color) -> void:
	var time: float = seconds + phase_offset * 0.66 # 不同实例错开短放电。
	var cycle: int = floori(time / 4.7) # 每周期最多出现一次，未经历的窗口直接略过。
	var onset: float = 1.08 + 0.61 * sin(float(cycle) * 3.84 + phase_offset) # 窗口在周期内轻微变化。
	var duration: float = 0.105 + 0.020 * cos(float(cycle) + phase_offset) # 亮点留在 85–125 毫秒范围内。
	var age: float = (fposmod(time, 4.7) - onset) / duration # 放电窗口内的归一年龄。
	if age <= 0.0 or age >= 1.0:
		return
	var energy: float = intensity * smoothstep(0.0, 0.13, age) * (1.0 - smoothstep(0.17, 1.0, age)) # 单峰而且快速消隐。
	var upper: bool = cycle % 2 == 0 # 相邻窗口错开到不同发射区。
	var root: Vector2 = center + (Vector2(30.0, -46.0) if upper else Vector2(-33.0, 60.0)) # 肩部或风衣边缘。
	var axis: Vector2 = Vector2(27.0, 16.0) if upper else Vector2(-32.0, -11.0) # 只在身体轮廓附近出现。
	var edge := Color(rim, energy * 0.68) # 暗红在极细亮芯外。
	var core := Color(1.0, 0.81, 0.66, energy * 0.76) # 暖白只出现在主线与短枝。
	var from: Vector2 = root # 当段放电的起点。
	for step: int in range(1, 6): # 窗口内保持同一条折线，不逐帧重新抽样。
		var ratio: float = float(step) / 5.0 # 末端收细。
		var to: Vector2 = root + axis * ratio + Vector2(2.0, 7.0) * sin(float(step) * 4.88 + float(cycle) * 0.27) # 各转角位置固定。
		var side: Vector2 = (to - from).normalized().orthogonal() * (1.5 - ratio * 0.61) # 单枝半宽小于两个局部像素。
		_stroke(from, to, side, side * 0.82, edge, core, Vector2(1.0 - ratio * 0.43, 1.0 - ratio * 0.78))
		if step == 2 or step == 3:
			var fork: Vector2 = to + Vector2(axis.x * 0.34, -13.0 + float(step) * 1.3) # 两个短分叉尽快消失。
			var fork_side: Vector2 = (fork - to).normalized().orthogonal() * 0.78 # 枝条窄于主线。
			_stroke(to, fork, fork_side, Vector2.ZERO, edge, core, Vector2(0.62, 0.0))
		from = to


## [param from]、[param to] 是笔画两端，[param from_side]、[param to_side] 为全羽化的法线半宽。
## 每端各写五个顶点，使用 [param rim] 和 [param core] 颜色以及 [param fades] 的两个透明度。
func _stroke(from: Vector2, to: Vector2, from_side: Vector2, to_side: Vector2,
		rim: Color, core: Color, fades: Vector2) -> void:
	if _used >= CAPACITY:
		return
	var base: int = _used * SECTION_SIZE * 2 # 预制索引对应的两排顶点。
	for column: int in SECTION_SIZE: # 透明外缘、暗边和中心线芯按列交替。
		var color: Color = core if column == 2 else rim # 最亮区域只占中间一列。
		var weight: float = ALPHA_WEIGHTS[column] * color.a # 每端沿弧长再额外衰减。
		var offset: float = WIDTH_OFFSETS[column] # 当前列在法向的有符号偏移。
		_points[base + column] = from + from_side * offset
		_points[base + SECTION_SIZE + column] = to + to_side * offset
		_colors[base + column] = Color(color, weight * fades.x)
		_colors[base + SECTION_SIZE + column] = Color(color, weight * fades.y)
	_used += 1


## 返回 [param angle] 在 [param radii] 和连续 [param bend] 扰动下的未旋转椭圆坐标。
static func _offset(angle: float, radii: Vector2, bend: float) -> Vector2:
	return radii * Vector2(cos(angle) + 0.072 * sin(2.0 * angle + bend),
		sin(angle) + 0.14 * sin(3.0 * angle - bend))


## 返回 [param angle] 的轨道单位法向，和 [param radii]、[param bend]、[param tilt] 形成的切线正交。
static func _normal(angle: float, radii: Vector2, bend: float, tilt: float) -> Vector2:
	var tangent: Vector2 = radii * Vector2(-sin(angle) + 0.144 * cos(2.0 * angle + bend),
		cos(angle) + 0.42 * cos(3.0 * angle - bend)) # 对椭圆及同频扰动解析求导。
	return tangent.normalized().orthogonal().rotated(tilt)


## 返回角度 [param angle] 的羽化权重。原弧 [param start]、[param span] 保证切面前后连续。
## [param bend] 使短断口沿轨道微移。
static func _arc_fade(angle: float, start: float, span: float, bend: float) -> float:
	var ratio: float = clampf((angle - start) / span, 0.0, 1.0) # 原弧首尾相对于完整长度。
	var gap: float = smoothstep(0.018, 0.108, absf(ratio - 0.28 - 0.053 * sin(bend))) # 局部间断的柔边。
	var depth: float = 0.79 + 0.21 * sin(angle) # 背面更薄，越过平面时连续。
	return pow(maxf(0.0, sin(PI * ratio)), 0.72) * (0.10 + 0.90 * gap) * depth


## 只把写入部分提交到当前画布，兼容渲染使用同一条三角形阵列命令。
func _draw() -> void:
	if _used == 0:
		return
	var vertices: int = _used * SECTION_SIZE * 2 # 本批实际绘制的连续顶点数。
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _indices.slice(0, _used * INDICES_PER_STROKE),
		_points.slice(0, vertices), _colors.slice(0, vertices))
