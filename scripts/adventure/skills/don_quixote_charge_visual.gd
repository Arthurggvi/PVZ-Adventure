## 血马绘制只消费战斗时间轴，实际命中另在最前层产生一击一闪。
extends Node2D

## 用户提供的透明原图，在世界中镜像为朝向刷怪侧。
const HORSE: Texture2D = preload("res://assets/adventure/environment_fx/don_quixote_blood_horse.png")
## 同一原图上的马身、逆光与薄边残像。
const HORSE_SHADER: Shader = preload("res://shaders/adventure/don_quixote_blood_horse.gdshader")
## 用暗酒红压住草地高饱和度。
const INK := Color("#310616")
## 轨迹和回落火花的主色。
const RUBY := Color("#be1641")
## 正在高速移动的枪锋火色。
const FLARE := Color("#fc754c")
## 刚接触时的白金反光。
const CORE := Color("#ffe9bd")
## 一次撞击绘制结束的实际秒。
const IMPACT_LIFE: float = 0.37
## 同时保留的击中视觉数量上限，不限制伤害。
const MAX_IMPACTS: int = 36
## 亮边残像依次使用的回采秒数，从远到近。
const ECHO_TIMES := [0.222, 0.143, 0.074]

## 一行的三张剪影与一张真身。
class Horses:
	## 滞后于真实路线的薄边残像，按由后到前的顺序绘制。
	var echoes: Array[Sprite2D] = []
	## 当前路线上的原图马身。
	var body: Sprite2D

## 一次真实接触的世界坐标及产生时点。
class Impact:
	## 枪锋与受击框刚相交的世界坐标。
	var point: Vector2
	## 时间轴上的出生秒。
	var born: float

## 战斗时间轴提供的全部路线，画马时按行号建立深度。
var _runs: Array
## 与路线同序的马身和剪影。
var _horses: Array[Horses] = []
## 最近提交的实际秒。
var _age: float = 0.0
## 只在最前层绘制实际击中的短闪与碎片。
var _impact_layer: Node2D
## 尚未收束的真实接触点。
var _impacts: Array[Impact] = []

## [param runs] 只读路线副本，按远行到近行组织画面深度。
func _init(runs: Array) -> void:
	_runs = runs.duplicate()
	_runs.sort_custom(func(back, front) -> bool: return back.lane < front.lane)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

## 地面与枪风在根画布，马身排好深度后由最前层绘制碰撞。
func _ready() -> void:
	for _run in _runs: # 一条路线只分配一次绘制实例。
		var horses := Horses.new() # 同行剪影先于真身绘制。
		for _delay: float in ECHO_TIMES: # 保留每个回采时点对应的独立剪影。
			horses.echoes.append(_add_horse(true))
		horses.body = _add_horse(false)
		_horses.append(horses)
	_impact_layer = Node2D.new()
	add_child(_impact_layer)
	_impact_layer.draw.connect(_draw_impacts)

## 创建一张脚点为锚的镜像血马，[param is_echo] 决定边缘及透明策略。
func _add_horse(is_echo: bool) -> Sprite2D:
	var sprite := Sprite2D.new() # 保留原始尖角颜色及透明遮罩。
	sprite.texture = HORSE
	sprite.flip_h = true
	sprite.offset = Vector2(0.0, -HORSE.get_height() * 0.44)
	var shader := ShaderMaterial.new() # 每张剪影有自己踏步相位和边缘高光。
	shader.shader = HORSE_SHADER
	shader.set_shader_parameter(&"echo", is_echo)
	sprite.material = shader
	sprite.hide()
	add_child(sprite)
	return sprite

## 更新马身与三张剪影到 [param elapsed]，绘制器不另起时钟。
func paint(elapsed: float) -> void:
	_age = elapsed
	while not _impacts.is_empty() and _age - _impacts[0].born >= IMPACT_LIFE:
		_impacts.pop_front()
	for index: int in range(_runs.size()): # 每行的起跑时间和地形路线从同一对象读取。
		var run = _runs[index] # 当前画布行的路径组件。
		var horses: Horses = _horses[index] # 同一路线全部纹理层。
		var age: float = _age - run.arrival # 该匹马登场后经过的秒数。
		var presence: float = smoothstep(0.03, run.launch * 0.72, age) * (1.0 - smoothstep(run.finish - 0.04, run.finish + 0.17, age)) # 闪出轮廓后保持实体，越过盘面才离场。
		var takeoff: float = maxf(0.0, 1.0 - absf(age - run.launch) / 0.16) # 蹄落时迅速增亮后回落。
		var heat: float = takeoff * 0.82 # 马身的边缘也会被近处刚发生的碰撞照亮。
		if presence > 0.009 and age > run.launch:
			var lance: Vector2 = run.lance_at(age) # 只接收这匹马此刻枪锋附近的短闪。
			for hit: Impact in _impacts: # 火花已有统一的寿命和数量上限。
				var proximity: float = 1.0 - smoothstep(0.0, run.pitch * 0.8, lance.distance_to(hit.point)) # 远处和邻行的光不会拖亮整个马身。
				heat = maxf(heat, proximity * (1.0 - smoothstep(0.0, 0.13, _age - hit.born)))
		_pose(horses.body, run, age, presence, heat)
		for echo: int in range(ECHO_TIMES.size()): # 采同一运动曲线，距离会随冲锋加速自动拉开。
			var old: float = age - ECHO_TIMES[echo] # 这一影保留的真实姿态时刻。
			var alpha: float = (0.19 + 0.12 * echo) * smoothstep(run.launch, run.launch + 0.16, old) \
				* (1.0 - smoothstep(run.finish, run.finish + 0.36, age)) # 出场没有复制影，越靠前越利落清楚。
			_pose(horses.echoes[echo], run, old, alpha, 0.0)
	queue_redraw()
	_impact_layer.queue_redraw()

## 将一张 [param sprite] 贴到 [param run] 在 [param age] 的脚点。
## [param alpha] 控制显隐，[param heat] 是起跑一瞬的边光热度。
func _pose(sprite: Sprite2D, run, age: float, alpha: float, heat: float) -> void:
	sprite.visible = alpha > 0.009
	if not sprite.visible:
		return
	var surge: float = smoothstep(run.launch - 0.046, run.launch + 0.15, age) # 从后坐蓄势切到向前压低。
	var gait: float = sin((age - run.launch) * TAU * 4.8) * surge # 蹄步集中在下缘，不晃动枪锋。
	var entry: float = smoothstep(0.02, run.launch * 0.63, age) # 成形从脚下迅速站起。
	var size: float = run.pitch * 2.27 / HORSE.get_width() # 行高单位转换后的纹理缩放。
	sprite.position = run.feet_at(age) + Vector2(0.0, -absf(gait) * 4.8)
	sprite.rotation = lerpf(-0.105, 0.12, surge) + 0.017 * gait
	sprite.scale = Vector2(lerpf(0.89, 1.15, surge), lerpf(0.62, 1.02, entry) - surge * 0.05) * size
	sprite.self_modulate = Color(1.0, 1.0, 1.0, alpha)
	var shader: ShaderMaterial = sprite.material as ShaderMaterial # 残像也复现采样时刻的蹄步。
	shader.set_shader_parameter(&"stride", gait)
	shader.set_shader_parameter(&"heat", heat)

## 收到 [param point] 在 [param elapsed] 的一次真实撞击，限制极密目标下的同时绘制数量。
func impact(point: Vector2, elapsed: float) -> void:
	if _impacts.size() >= MAX_IMPACTS:
		_impacts.pop_front()
	var hit := Impact.new() # 各碰撞有独立寿命及碎片方向。
	hit.point = point
	hit.born = elapsed
	_impacts.append(hit)

## 地面裂光、蹄印和流线使用相同的脚点路线和速度。
func _draw() -> void:
	for run in _runs: # 绘制顺序保持每行由远到近。
		var age: float = _age - run.arrival # 局部时钟解算这一行当前阶段。
		if age < 0.0 or age >= run.finish + 0.46:
			continue
		_draw_entry(run, age)
		if age > run.launch:
			_draw_wake(run, age)
			_draw_pressure(run, age)
			_draw_hoof_marks(run, age)

## [param run] 在 [param age] 的起跑裂光。先压出蹄印，再从同一点向两侧迸开。
func _draw_entry(run, age: float) -> void:
	if age > run.launch + 0.38:
		return
	var feet: Vector2 = run.feet_at(0.0) # 裂口留在原地，血马离开后余亮仍贴住地面。
	var spread: float = smoothstep(0.03, run.launch + 0.32, age) # 起步后迅速向外碎开。
	var flash: float = pow(maxf(0.0, 1.0 - absf(age - run.launch) / 0.14), 2.2) # 主亮核只压在前蹄发力的短拍。
	var fade: float = smoothstep(0.02, 0.16, age) * (1.0 - smoothstep(run.launch - 0.02, run.launch + 0.38, age)) # 余烬先弱后消失。
	var radius: float = run.pitch * lerpf(0.10, 1.17, spread) # 沿地面展开，纵向受透视压缩。
	draw_set_transform(feet, 0.0, Vector2(1.0, 0.22))
	draw_circle(Vector2.ZERO, radius * 0.78, Color(INK, fade * 0.55), true, -1.0, true)
	draw_arc(Vector2.ZERO, radius, 0.12, 2.96, 27, Color(RUBY, fade * 0.84), 3.3, true)
	draw_arc(Vector2.ZERO, radius * 0.74, 3.27, TAU - 0.31, 23, Color(FLARE, fade * 0.70), 1.8, true)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	for index: int in range(7): # 不等距的冲压裂片，向后飞出的碎片更多。
		var angle: float = 1.98 + 0.52 * index # 发力时抛出斜向的擦地碎片。
		var axis: Vector2 = Vector2.from_angle(angle) * Vector2(1.07, 0.39) # 地面投影方向。
		var start: Vector2 = feet + axis * radius * (0.36 + (index % 3) * 0.14) # 从裂口内侧发出。
		var end: Vector2 = feet + axis * radius * (1.20 + (index % 2) * 0.56) + Vector2(-9.0, -12.0) * spread # 中段拖长，末端逐渐稀疏。
		_draw_shard(self, start, end, 2.3 + flash * 3.8, Color(FLARE, fade * 0.76))
	if flash > 0.006:
		_draw_shard(self, feet + Vector2(-37.0, 15.0), feet + Vector2(31.0, -47.0), 5.5,
			Color(CORE, flash * 0.87))

## [param run] 在 [param age] 的路径后方有三层弧线，以宽度、曲率和透明度区分地面和风压。
func _draw_wake(run, age: float) -> void:
	var head_age: float = minf(age, run.finish) # 越出棋盘后余势从最后一个轨迹点衰减。
	var tail_age: float = maxf(run.launch, head_age - 0.40) # 尾端回采整段实际加速路径。
	var fade: float = smoothstep(run.launch + 0.012, run.launch + 0.18, age) \
		* (1.0 - smoothstep(run.finish - 0.025, run.finish + 0.43, age)) # 起步几帧轨迹才完全形成。
	if fade <= 0.009:
		return
	var pitch: float = run.pitch # 同行的着地轨迹和近身轨迹保持比例。
	_ribbon(run, tail_age, head_age, pitch, 0.045, 0.13, 0.145, Color(INK, fade * 0.67))
	_ribbon(run, tail_age, head_age, pitch, 0.025, 0.11, 0.025, Color(RUBY, fade * 0.63))
	_ribbon(run, tail_age, head_age, pitch, 0.41, 0.38, 0.105, Color(RUBY, fade * 0.68))
	_ribbon(run, tail_age + (head_age - tail_age) * 0.19, head_age, pitch, 0.52, 0.23, 0.025, Color(FLARE, fade * 0.87))
	_ribbon(run, tail_age + (head_age - tail_age) * 0.47, head_age, pitch, 0.56, 0.11, 0.013, Color(CORE, fade * 0.87))
	for index: int in range(7): # 侧风细线疏密错开，并落在回采时点而非笔直贴图上。
		var shift: float = fposmod((age - run.launch) * 5.2 + index * 0.233, 1.0) # 沿每条流线走过的距离比例。
		var a: float = lerpf(tail_age, head_age, shift * 0.88) # 由真实弯曲和移动距离提供空间位置。
		var b: float = minf(a + 0.045 + (index % 3) * 0.020, head_age) # 每一笔留出不同断口。
		var height: float = pitch * (0.16 + (index % 5) * 0.128) # 风压线沿身体高度分布。
		var start: Vector2 = run.feet_at(a) + Vector2(-0.42 * pitch, -height + 14.0 * (1.0 - shift)) # 弧线在尾端更贴近地面。
		var end: Vector2 = run.feet_at(b) + Vector2(-0.27 * pitch, -height - 5.0) # 越近枪锋线越贴紧。
		_draw_shard(self, start, end, 1.2 + (index % 2) * 0.96, Color(FLARE, fade * sin(shift * PI) * 0.72))

## [param run] 在 [param age] 的枪前压缩锋面，前缘包住冲锋方向，后侧裂成两道速度刃。
func _draw_pressure(run, age: float) -> void:
	var speed: float = smoothstep(run.launch + 0.05, run.launch + 0.64, age) \
		* (1.0 - smoothstep(run.finish - 0.10, run.finish + 0.08, age)) # 由前半段提速托起，到出屏时收干净。
	if speed <= 0.006:
		return
	var pitch: float = run.pitch # 弧面和马身保持统一的相对比例。
	var front: Vector2 = run.lance_at(age) + Vector2(0.14, -0.10) * pitch # 弧面中心压在马颈前方。
	var sweep := Transform2D(0.10, Vector2(1.0, 0.66), 0.0, front) # 以椭圆在真实前进方向给出切面。
	draw_set_transform_matrix(sweep)
	draw_arc(Vector2.ZERO, pitch * 0.61, -1.53, -0.50, 17, Color(INK, speed * 0.66), 5.6, true)
	draw_arc(Vector2.ZERO, pitch * 0.57, -1.33, -0.38, 13, Color(FLARE, speed * 0.88), 2.0, true)
	draw_arc(Vector2.ZERO, pitch * 0.51, -0.18, 1.17, 17, Color(RUBY, speed * 0.73), 3.5, true)
	draw_arc(Vector2.ZERO, pitch * 0.56, 0.11, 0.72, 9, Color(CORE, speed * 0.69), 1.6, true)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	_draw_shard(self, front + Vector2(-1.03, -0.33) * pitch, front + Vector2(0.51, -0.41) * pitch,
		2.1, Color(FLARE, speed * 0.68))
	_draw_shard(self, front + Vector2(-0.56, 0.37) * pitch, front + Vector2(0.72, 0.14) * pitch,
		1.45, Color(CORE, speed * 0.55))

## 沿 [param run] 的 [param from_age] 到 [param to_age] 绘制渐隐风带。
## [param pitch] 是行高，[param height]、[param curl] 和 [param width] 以行高归一化，[param ink] 控制颜色。
func _ribbon(run, from_age: float, to_age: float, pitch: float, height: float, curl: float,
		width: float, ink: Color) -> void:
	var top := PackedVector2Array() # 曲线的上边界按行进方向采样。
	var bottom := PackedVector2Array() # 下边界反序组织成简单多边形。
	var top_colors := PackedColorArray() # 顶点渐隐避免硬截断的贴图感。
	var bottom_colors := PackedColorArray() # 下层边缘更柔，弱化带状物的厚度感。
	for step: int in range(11): # 真实路线只有斜坡转折和少量弧度，固定采样即可。
		var t: float = float(step) * 0.1 # 0 表示最远的尾端，1 表示靠近枪锋。
		var point: Vector2 = run.feet_at(lerpf(from_age, to_age, t)) # X 始终单调，兼容屋顶坡面。
		var spread: float = pitch * width * (0.10 + 0.90 * sin(t * PI * 0.83)) # 尾端细、近处厚，最后向枪尖压窄。
		var bow: float = pitch * (height + curl * sin(t * PI * 0.92) - (1.0 - t) * curl * 0.68) # 轨迹尾端贴地，近处向上卷出。
		point += Vector2(lerpf(-0.65, 0.58, t) * pitch, -bow)
		top.append(point - Vector2(0.0, spread * 0.55))
		bottom.append(point + Vector2(0.0, spread))
		var alpha: float = ink.a * smoothstep(0.0, 0.35, t) * (1.0 - 0.69 * smoothstep(0.89, 1.0, t)) # 两头收细，中段仍可见。
		top_colors.append(Color(ink, alpha))
		bottom_colors.append(Color(ink, alpha * 0.45))
	bottom.reverse()
	bottom_colors.reverse()
	top.append_array(bottom)
	top_colors.append_array(bottom_colors)
	draw_polygon(top, top_colors)

## [param run] 在 [param age] 的离散踏痕与后甩碎屑；落点留在真实地面，不追随马身滑动。
func _draw_hoof_marks(run, age: float) -> void:
	var cadence: float = 10.7 # 每秒留下的前后蹄印总量。
	var last: int = floori((minf(age, run.finish) - run.launch) * cadence) # 只保留沿途最近的落蹄。
	for index: int in range(maxi(0, last - 5), last + 1): # 每个落蹄独立淡出。
		var stamp: float = run.launch + float(index) / cadence # 第一次落蹄位于登场裂口。
		var t: float = clampf((age - stamp) / 0.41, 0.0, 1.0) # 余火的归一化寿命。
		var point: Vector2 = run.feet_at(stamp) + Vector2(-13.0, 4.0 if index % 2 == 0 else -1.0) # 前后脚垫略错开。
		var alpha: float = (1.0 - t) * (1.0 - t) # 发力帧暖白，几帧后剩地面暗痕。
		_draw_shard(self, point + Vector2(-26.0 - t * 16.0, 2.0), point + Vector2(13.0, -4.0), 2.1,
			Color(RUBY, alpha * 0.82))
		for chip: int in range(3): # 土屑被蹄尖踢向后方。
			var drift := Vector2(-16.0 - t * (38.0 + chip * 28.0), -t * (45.0 + chip * 21.0) + t * t * 36.0) # 先向上抛，再受重力落下。
			_draw_shard(self, point + drift - Vector2(6.0, -3.0), point + drift + Vector2(4.0, -1.0), 1.4,
				Color(FLARE if chip > 0 else CORE, alpha))

## 把每次实际碰撞画成短闪、向外撕开的锋面和一层外散残渣。
func _draw_impacts() -> void:
	for hit: Impact in _impacts: # 只有战斗时间轴确认过的位置才会给出反馈。
		var t: float = clampf((_age - hit.born) / IMPACT_LIFE, 0.0, 1.0) # 每次碰撞独立归一化。
		var life: float = pow(1.0 - t, 2.5) # 前缘亮、衰减快，拖到下一次碰撞时画面仍清楚。
		var distance: float = 13.0 + sqrt(t) * 59.0 # 边缘受冲量迅速张开。
		var layer: Node2D = _impact_layer # 压在血马与轨迹的绘制之上。
		layer.draw_arc(hit.point + Vector2(5.0, 0.0), distance, -1.30, 1.23, 19, Color(RUBY, life * 0.88), 4.2 - t * 3.0, true)
		layer.draw_arc(hit.point + Vector2(11.0, -2.0), distance * 0.79, -1.02, 0.80, 16,
			Color(FLARE, life * 0.92), 2.4, true)
		if t < 0.30:
			_draw_shard(layer, hit.point + Vector2(-49.0, 13.0), hit.point + Vector2(54.0, -15.0), 8.0 * life,
				Color(CORE, life))
			_draw_shard(layer, hit.point + Vector2(-12.0, 24.0), hit.point + Vector2(25.0, -47.0), 5.0 * life,
				Color(FLARE, life))
		for index: int in range(11): # 长短交替，主要甩向奔跑方向。
			var angle: float = -1.63 + index * 0.311 + sin(hit.point.x * 0.11 + index * 2.2) * 0.23 # 每次落点带小幅固定变化。
			var axis: Vector2 = Vector2.from_angle(angle) # 当前碎片偏转方向。
			var point: Vector2 = hit.point + axis * distance * (0.50 + (index % 3) * 0.29) \
				+ Vector2(38.0 * t, t * t * 25.0) # 命中后仍沿冲势移动并下坠。
			_draw_shard(layer, point - axis * (21.0 - 13.0 * t), point,
				1.2 + (index % 3) * 0.83, Color(CORE if index % 3 == 0 else FLARE, life))

## 在 [param canvas] 由 [param start] 到 [param end] 画一条两端利落的锋屑。
## [param width] 是中段宽度的世界像素数，[param ink] 是颜色与透明度。
func _draw_shard(canvas: Node2D, start: Vector2, end: Vector2, width: float, ink: Color) -> void:
	var axis: Vector2 = end - start # 为尖角建立独立法线。
	var normal: Vector2 = axis.orthogonal().normalized() * width # 横向很薄，能清晰指示速度。
	var belly: Vector2 = start.lerp(end, 0.68) # 把重心推到尖端，尾部更细。
	canvas.draw_colored_polygon(PackedVector2Array([start, belly - normal * 0.62, end, belly + normal * 0.38]), ink)
