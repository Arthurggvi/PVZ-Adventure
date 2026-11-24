## 苍穹公爵远景齐射的解析形状，复用已装弹体和局内少量几何缓冲。
extends RefCounted

## 炮塔实弹的原图，其基准朝向与 CannonTurretMissile.ART_HEADING 一致。
const MISSILE: Texture2D = preload("res://assets/adventure/zombies/cannon_turret/missile.png")
## 截自原实现的精灵鼻向，未旋转纹理中的单位向量。
const ART_HEADING := Vector2(-0.94908, -0.31503)
## 原图中心到推进口的距离，用于把尾流接在弹体后缘。
const ART_TAIL: float = 28.0
## 远处弹身仍可在晴空辨认，尾流共用该缩放保持连接。
const MISSILE_SCALE: float = 0.209
## 标准画质和兼容画质各条尾迹的曲线分段数。
const TRAIL_SEGMENTS: int = 12
## 保留软边的低画质采样下限。
const LOW_SEGMENTS: int = 7
## 主色偏冷，让远处空中轨迹与真实导弹预警的暖色区分。
const VAPOR_COLOR := Color(0.60, 0.80, 0.93)
## 高空的冷白反光。
const WHITE_CORE := Color(0.94, 0.98, 1.0)

## 一发齐射的视觉参数。所有时刻均来自同一战斗时钟，独立记录伪深度。
class Launch:
	## 发射点在视口内的归一化位置。
	var origin_uv := Vector2.ZERO
	## 0 到 1 的虚拟纵深，越大越远。
	var depth: float
	## 点火时的速度，单位为参考视口像素每秒。
	var velocity := Vector2.ZERO
	## 空中解析轨迹的加速度，单位为参考视口像素每平方秒。
	var acceleration := Vector2.ZERO
	## 点火时刻，单位为绝对战斗秒。
	var ignition_at: float
	## 声音到达时刻，单位为绝对战斗秒；INF 表示没有待播声。
	var sound_at: float
	## 由本次号令捕获的阶段，用于保持旧尾迹自身样式。
	var phase_two: bool
	## 该记录所用的兼容画质标记。
	var reduced: bool
	## 置位时保有一发正在排程或衰减的齐射。
	var active: bool

	## 返回可见弹体的连续升空时长，单位为战斗秒。
	func flight_span() -> float:
		return lerpf(0.64, 0.76, depth)

	## 返回尾迹离开弹体后继续受风扩散的时间，单位为战斗秒。
	func vapor_span() -> float:
		return 0.40 if phase_two else 0.32

	## 判断 [param seconds] 战斗秒时弹体及尾流是否已经消散。
	func is_expired(seconds: float) -> bool:
		return seconds >= ignition_at + flight_span() + vapor_span()

	## 解析投影 [param visible_rect] 内发射点的逻辑坐标。
	func on_view(visible_rect: Rect2) -> Vector2:
		return visible_rect.position + origin_uv * visible_rect.size

	## 取点火后 [param age] 战斗秒对应的位移，单位为参考视口像素。
	func path(age: float) -> Vector2:
		return (velocity + acceleration * 0.5 * age) * age

	## 返回点火后 [param age] 战斗秒处的单位切线，用于机头和尾迹朝向。
	func heading(age: float) -> Vector2:
		return (velocity + acceleration * age).normalized()


## 两种尾迹精度的三角形连接方式，创建后保持不变。
var _high_indices := PackedInt32Array()
## 低分段数下使用同样的透明边缘拓扑。
var _low_indices := PackedInt32Array()
## 当前尾迹每个样本的两个边缘和一个中心。
var _points := PackedVector2Array()
## 当前尾迹的逐顶点透明度和色彩。
var _colors := PackedColorArray()
## 一份小型径向衰减，供所有发射光斑和尾喷亮点共享。
var _glow := GradientTexture2D.new()


## 预先构造连接索引和 32×32 共用的软边光斑。
func _init() -> void:
	_high_indices = _make_indices(TRAIL_SEGMENTS)
	_low_indices = _make_indices(LOW_SEGMENTS)
	_points.resize((TRAIL_SEGMENTS + 1) * 3)
	_colors.resize(_points.size())
	var ramp := Gradient.new() # 中心紧凑，扩散边界连续隐去。
	ramp.offsets = PackedFloat32Array([0.0, 0.22, 0.59, 1.0])
	ramp.colors = PackedColorArray([Color.WHITE, Color(1.0, 1.0, 1.0, 0.76),
		Color(1.0, 1.0, 1.0, 0.22), Color(1.0, 1.0, 1.0, 0.0)])
	_glow.width = 32
	_glow.height = 32
	_glow.fill = GradientTexture2D.FILL_RADIAL
	_glow.fill_from = Vector2(0.5, 0.5)
	_glow.fill_to = Vector2(1.0, 0.5)
	_glow.gradient = ramp


## 在 [param canvas] 绘制 [param launch]。[param visible_rect] 定位，[param to_sky] 将视口坐标转为天空局部坐标。
## [param wind] 为视口风速，[param age] 为点火后战斗秒。
func draw_launch(canvas: Node2D, launch: Launch, visible_rect: Rect2, to_sky: Transform2D, wind: Vector2, age: float) -> void:
	var origin := launch.on_view(visible_rect) # 与原空域遮挡共用该帧的视口。
	var view_units := minf(visible_rect.size.x / 1066.0, visible_rect.size.y / 600.0) # 保持宽高变化时的等比尺寸。
	var unit := view_units * lerpf(1.18, 0.63, launch.depth) # 虚拟距离只缩小形状，弹道另有速度层级。
	canvas.draw_set_transform_matrix(to_sky)
	_draw_vapor(canvas, launch, origin, view_units, unit, wind, age)
	if age < 0.27:
		_draw_ignition(canvas, launch, origin, to_sky, unit, wind, age)
	if age < launch.flight_span():
		_draw_missile(canvas, launch, origin, to_sky, view_units, unit, age)


## 构造 [param segments] 段的三列带状网格索引，中心和两侧可独立混色。
func _make_indices(segments: int) -> PackedInt32Array:
	var indices := PackedInt32Array() # 每段的两条软边共四个三角面。
	for section: int in segments: # 相邻采样共用顶点。
		var row := section * 3 # 当前采样的左缘。
		indices.append_array(PackedInt32Array([row, row + 1, row + 3, row + 1, row + 4, row + 3,
			row + 1, row + 2, row + 4, row + 2, row + 5, row + 4]))
	return indices


## 为 [param launch] 在 [param canvas] 上追溯旧尾喷采样点。
## [param origin] 为点火坐标，[param view_units] 缩放航迹，[param unit] 缩放远近粗细。
## [param wind] 推动已离开弹体的烟丝，[param age] 为点火后战斗秒。
func _draw_vapor(canvas: Node2D, launch: Launch, origin: Vector2, view_units: float, unit: float, wind: Vector2, age: float) -> void:
	var end := minf(age, launch.flight_span()) # 弹体退场后只能看到已经产生过的尾迹。
	var span := launch.vapor_span() # 阶段二有更长的凝结尾。
	var begin := maxf(0.0, age - span) # 过期采样离开固定长度的可见烟带。
	if end - begin <= 0.006:
		return
	var segments := LOW_SEGMENTS if launch.reduced else TRAIL_SEGMENTS # 低画质减少顶点，保留同一段尾流。
	if _points.size() != (segments + 1) * 3:
		_points.resize((segments + 1) * 3)
		_colors.resize(_points.size())
	var intensity := lerpf(0.83, 0.45, launch.depth) # 对照亮天空保留冷白层次。
	var silhouette := ART_TAIL * unit * MISSILE_SCALE # 对齐尾喷与共享导弹原图。
	for sample: int in range(segments + 1): # 从最老的气流一路采样到推进口。
		var progress := float(sample) / float(segments) # 在可见烟带中的位置。
		var at := lerpf(begin, end, progress) # 这一截尾喷形成的战斗秒数。
		var lapse := age - at # 烟丝离体后按实际时长受风。
		var fresh := 1.0 - smoothstep(0.0, span, lapse) # 比亮芯更老的凝结烟逐渐收窄。
		var tip := launch.heading(at) # 沿抛物线上升的方向。
		var shift := wind * lapse * lerpf(0.60, 0.28, launch.depth) * (1.0 - fresh) # 已分离的老烟逐步趋向水平风床。
		var center := origin + launch.path(at) * view_units - tip * silhouette + shift # 每点恰接在生成时刻的弹体尾部。
		var taper := smoothstep(0.0, 0.24, progress) # 尾端的宽度和透明度同时收束。
		var half_width := unit * lerpf(1.3, 6.3 if launch.phase_two else 4.1, fresh) * (0.25 + 0.75 * taper) # 三列连续羽化几何。
		var edge := tip.orthogonal() * half_width # 横切面随轨迹弯曲。
		var alpha := intensity * fresh * taper # 随深度、寿命、烟带位置共同退去。
		var tint := VAPOR_COLOR.lerp(WHITE_CORE, fresh * 0.79) # 已受风的尾部偏冷蓝，头部冷白。
		var row := sample * 3 # 这一横切面的三个顶点。
		_points[row] = center - edge
		_points[row + 1] = center
		_points[row + 2] = center + edge
		_colors[row] = Color(tint, 0.0)
		_colors[row + 1] = Color(tint, alpha)
		_colors[row + 2] = Color(tint, 0.0)
	var indices := _low_indices if launch.reduced else _high_indices # 选择预存索引，限制单发烟带顶点预算。
	RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(), indices, _points, _colors)


## 在 [param canvas] 的 [param origin] 绘制 [param launch] 的软光与两段不闭合气压弧。
## [param to_sky] 定位椭圆，[param unit] 表示可见尺度，[param wind] 推动扩张，[param age] 为点火后战斗秒。
func _draw_ignition(canvas: Node2D, launch: Launch, origin: Vector2, to_sky: Transform2D, unit: float, wind: Vector2, age: float) -> void:
	var branch := Color(1.0, 0.67, 0.57) if launch.phase_two else Color(0.65, 0.88, 1.0) # 阶段二只在短点火带留暖色。
	var flash := (1.0 - smoothstep(0.0, 0.135, age)) * lerpf(0.83, 0.44, launch.depth) # 相距较远的光斑自然柔和。
	if flash > 0.0:
		var glare := Vector2(31.0, 49.0) * unit * (1.19 if launch.phase_two else 0.88) # 纵向点火柱仅留短促软边。
		canvas.draw_texture_rect(_glow, Rect2(origin - glare * Vector2(0.5, 0.65), glare), false, Color(branch, flash))
		canvas.draw_circle(origin, maxf(0.65, unit * 1.8), Color(WHITE_CORE, flash), true, -1.0, true)
	var pulse := smoothstep(0.0, 0.27, age) # 余压寿命独立于发射核心。
	var radius := unit * lerpf(6.0, 42.0 if launch.phase_two else 31.0, pulse) # 按深度缩放局部压力波。
	var ring_center := origin + wind * age * 0.22 # 余压随环境风移动。
	canvas.draw_set_transform_matrix(to_sky * Transform2D(0.0, Vector2(1.0, 0.36), 0.0, ring_center))
	var opacity := (1.0 - pulse) * lerpf(0.49, 0.20, launch.depth) # 用断弧显出冲击而不形成固定圆圈。
	canvas.draw_arc(Vector2.ZERO, radius, 3.42, 5.90, 13, Color(WHITE_CORE, opacity), maxf(0.7, unit * 1.45), true)
	if launch.phase_two and not launch.reduced:
		canvas.draw_arc(Vector2.ZERO, radius * 0.82, 0.28, 2.10, 9, Color(branch, opacity * 0.55), maxf(0.7, unit), true)
	canvas.draw_set_transform_matrix(to_sky)


## 将 [param launch] 的现有弹体图绘在 [param canvas] 上，机头跟随解析切线。
## [param origin] 和 [param to_sky] 锚定画面，[param view_units] 与 [param unit] 调整航迹和形状，[param age] 为点火后战斗秒。
func _draw_missile(canvas: Node2D, launch: Launch, origin: Vector2, to_sky: Transform2D, view_units: float, unit: float, age: float) -> void:
	var center := origin + launch.path(age) * view_units # 弹体中心，从敌舰方向向视野上缘飞行。
	var tip := launch.heading(age) # 精灵鼻向与实际的速度切线对齐。
	var size := unit * MISSILE_SCALE # 只用原图尺寸的一小部分表达远景纵深。
	var alpha := lerpf(0.92, 0.58, launch.depth) * (1.0 - smoothstep(launch.flight_span() * 0.84, launch.flight_span(), age)) # 在顶端退入天空。
	var exhaust := center - tip * (ART_TAIL * size) # 短喷亮点对准烟带起点。
	var shine := Vector2(12.0, 17.0) * unit # 推力亮点不超过相邻的远景弹身。
	canvas.draw_texture_rect(_glow, Rect2(exhaust - shine * 0.5, shine), false, Color(WHITE_CORE, alpha * 0.72))
	canvas.draw_set_transform_matrix(to_sky * Transform2D(tip.angle() - ART_HEADING.angle(), center))
	var body := MISSILE.get_size() * size # 保持炮塔导弹原始纹理的透明边缘。
	canvas.draw_texture_rect(MISSILE, Rect2(-body * 0.5, body), false, Color(0.78, 0.88, 0.99, alpha))
	canvas.draw_set_transform_matrix(to_sky)
