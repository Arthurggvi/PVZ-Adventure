## 杨桃战斗特效画布。少量短寿命数据代替每次转头、命中和落地生成独立节点。
extends Node2D

## 只限制同一时间的视觉收据，碰撞与伤害无此上限。
const EFFECT_BUDGET: int = 72
## 巨星的有色主面，按六类相邻色形成明显的彩色轮廓。
const PRISM := [Color(1.0, 0.35, 0.26), Color(1, 0.71, 0.19), Color(1, 0.96, 0.41),
	Color(0.32, 0.94, 0.91), Color(0.32, 0.72, 1), Color(0.79, 0.41, 1)]
## 光晕在多种棋盘中保留紫褐暗镶边。
const DARK: Color = Color(0.16, 0.10, 0.30, 0.98)
## 视觉收据的绘制样式。
enum Effect { HIT, TURN, REFRACTION, LAND, EXIT_HIT, EXIT_TERRAIN, EXIT_RANGE }

## 同一帧的一颗正在落下的明星。
class InFlight:
	## 来自可视范围上方的进场锚点。
	var start: Vector2
	## 真实地面落点。
	var foot: Vector2
	## 已经过的归一化飞行进度。
	var t: float

## 一段亮片或冲击圈的短寿命数据。
class Spark:
	## 绘制入口。
	var kind: Effect
	## 画布局部起点。
	var point: Vector2
	## 转向或退场的飞行方向，落星用它存格距。
	var a: Vector2
	## 转向后的朝向，或撞地时的法线。
	var b: Vector2
	## 星弹结束时的星面角度。
	var spin: float
	## 退场头一帧延续的拖尾长度，单位世界像素。
	var trail: float
	## 由弹种决定的颜色。
	var tint: Color
	## 已经过的游戏秒数。
	var age: float = 0.0
	## 效果结束时刻，单位为秒。
	var duration: float

## 同一帧的飞行快照，收尾时由运行时清空。
var _falling: Array[InFlight] = []
## 短效只保留必要的画布数据。
var _sparks: Array[Spark] = []
## 只在闪光或坠落仍可见时刷新画布。
var _had_meteors: bool = false
## 五角星的局部轮廓供所有巨星和地面光纹复用。
var _star := PackedVector2Array()
## 每个巨星复用同一份预分配顶点缓存。
var _transformed := PackedVector2Array()
## 同一星面的三角形绘制缓存。
var _triangle := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
## 同一物理步复用屏幕变换，离镜头较远的星不申请退场收据。
var _view_frame: int = -1
## 世界点到当前画面的变换。
var _world_to_screen: Transform2D
## 带余光安全边距的视口范围。
var _visible_area: Rect2

## [param bullets] 始终只挂载一份杨桃画布。
static func for_bullets(bullets: Node2D) -> Node2D:
	var visual := bullets.get_node_or_null(^"StarFruitVisual") as Node2D # 原生和转职共享同一生命周期。
	if visual == null:
		visual = (load("res://scripts/adventure/research/starfruit_visual.gd") as Script).new()
		visual.name = "StarFruitVisual"
		visual.z_as_relative = false
		visual.z_index = 154
		bullets.add_child(visual)
	return visual

## 初始化静态几何，其他时间只写少量坐标。
func _ready() -> void:
	_star.resize(10)
	_transformed.resize(10)
	for vertex: int in range(10): # 外尖与内凹交替。
		_star[vertex] = Vector2.UP.rotated(TAU * vertex / 10.0) * (1.0 if vertex % 2 == 0 else 0.46)
	set_process(false)

## 清除上一物理步的落星记录。
func begin_meteors() -> void:
	_falling.clear()

## [param start] 至 [param foot] 的飞行，当前已经历 [param progress]。
func add_meteor(start: Vector2, foot: Vector2, progress: float) -> void:
	var pose := InFlight.new() # 巨星稀少，命中收据不走此路径。
	pose.start = to_local(start)
	pose.foot = to_local(foot)
	pose.t = progress
	_falling.append(pose)

## 当前步有巨星，或者需要抹去上一帧的巨星时才更新画布。
func end_meteors() -> void:
	if _had_meteors or not _falling.is_empty():
		queue_redraw()
	_had_meteors = not _falling.is_empty()

## 在 [param origin] 放出 [param tint] 亮片。[param bloom] 为亡语时使用较显眼的扇形碎片。
func add_flash(origin: Vector2, tint: Color, bloom: bool) -> void:
	_spark(Effect.REFRACTION if bloom else Effect.HIT, origin, tint, 0.36 if bloom else 0.16)

## [param origin] 离画面太远时跳过退场，仍在原射程及时回收。
func can_show_exit(origin: Vector2) -> bool:
	if not is_inside_tree() or is_queued_for_deletion():
		return false
	var frame: int = Engine.get_physics_frames() # 批量退场只取一次画面变换。
	if frame != _view_frame:
		var viewport: Viewport = get_viewport() # 适用于原有相机缩放和横移。
		_view_frame = frame
		_world_to_screen = viewport.canvas_transform
		_visible_area = viewport.get_visible_rect().grow(70.0)
	return _visible_area.has_point(_world_to_screen * origin)

## [param origin] 是真实终点。[param heading]、[param normal]、[param spin]、[param tint] 与 [param trail] 只参与余光绘制。
## [param cause] 区分打碎、碰撞回溅和射程耗尽。
func add_projectile_exit(origin: Vector2, heading: Vector2, normal: Vector2, spin: float,
		tint: Color, trail: float, cause: Bullet000NormBase.ExitCause) -> void:
	var style: Effect = Effect.EXIT_HIT # 打碎强调瞬时同色亮心。
	var duration: float = 0.24 # 命中特效短于射程余光。
	match cause:
		Bullet000NormBase.ExitCause.TERRAIN:
			style = Effect.EXIT_TERRAIN
			duration = 0.31
		Bullet000NormBase.ExitCause.RANGE:
			style = Effect.EXIT_RANGE
			duration = 0.25
	var spark: Spark = _spark(style, origin, tint, duration) # 数据加入画布，不延长弹体寿命。
	if spark != null:
		spark.a = heading
		spark.b = normal.normalized() if not normal.is_zero_approx() else -heading
		spark.spin = spin
		spark.trail = trail

## [param origin] 上留下从 [param previous] 到 [param direction] 的短弧提示，颜色为 [param tint]。
func add_turn(origin: Vector2, previous: Vector2, direction: Vector2, tint: Color) -> void:
	if previous.dot(direction) > 0.94 or direction.is_zero_approx():
		return
	var spark: Spark = _spark(Effect.TURN, origin, tint, 0.28) # 短弧保留原方向后自然消失。
	if spark != null:
		spark.a = previous
		spark.b = direction

## 用 [param foot] 和实际格距 [param pitch] 绘制光晕与地面星轮。
func add_meteor_burst(foot: Vector2, pitch: Vector2) -> void:
	var spark: Spark = _spark(Effect.LAND, foot, Color(1.0, 0.32, 0.21), 0.58) # 巨星落地点固定在真实棋格。
	if spark != null:
		spark.a = pitch

## 申请 [param kind] 视觉收据；[param point]、[param tint] 和 [param duration] 不参与伤害计算。
func _spark(kind: Effect, point: Vector2, tint: Color, duration: float) -> Spark:
	if _sparks.size() >= EFFECT_BUDGET:
		if kind != Effect.LAND and kind != Effect.REFRACTION:
			return null
		_sparks.pop_front()
	var spark := Spark.new() # 实际表现只存在于本战场画布，不生成额外节点。
	spark.kind = kind
	spark.point = to_local(point)
	spark.tint = tint
	spark.duration = duration
	_sparks.append(spark)
	set_process(true)
	return spark

## 使用游戏步长 [param delta] 清理到期亮片。
func _process(delta: float) -> void:
	for index: int in range(_sparks.size() - 1, -1, -1): # 倒序删除不会跳过下一条。
		_sparks[index].age += delta
		if _sparks[index].age >= _sparks[index].duration:
			_sparks.remove_at(index)
	queue_redraw()
	set_process(not _sparks.is_empty())

## 先画局部弹道反馈，然后绘制高层明星及冲击中心。
func _draw() -> void:
	for spark: Spark in _sparks: # 列表上限固定。
		match spark.kind:
			Effect.HIT: _draw_hit(spark, false)
			Effect.REFRACTION: _draw_hit(spark, true)
			Effect.TURN: _draw_turn(spark)
			Effect.LAND: _draw_impact(spark)
			Effect.EXIT_HIT, Effect.EXIT_TERRAIN, Effect.EXIT_RANGE: _draw_projectile_exit(spark)
	for meteor: InFlight in _falling: # 多株同帧出手时各自保留落点。
		_draw_falling(meteor)

## [param spark] 的弹身先继承飞行姿态，尾巴在真实终点收拢，碰撞碎片才在短程内分散。
func _draw_projectile_exit(spark: Spark) -> void:
	var t: float = spark.age / spark.duration # 归一化寿命。
	var fade: float = 1.0 - t # 亮片渐熄，尾端更早透明。
	var ease: float = 1.0 - fade * fade # 碎片先快后慢。
	var point: Vector2 = spark.point # 命中点不附着在随后还会行走的目标身上。
	var ray: Vector2 = spark.a # 世界弹道。
	var wall: bool = spark.kind == Effect.EXIT_TERRAIN # 只有撞地的光沿表面向外回弹。
	var expires: bool = spark.kind == Effect.EXIT_RANGE # 自然失速时星身更完整。
	var drift: Vector2 = spark.b * (3.5 + 21.0 * ease) if wall else ray * (13.0 * ease if expires else 0.0) # 余光的位移远短于弹道。
	var center: Vector2 = point + drift # 碎开前的星身中心。
	var tail_back: Vector2 = point - ray * (spark.trail * fade * fade) # 沿原弹道收紧。
	draw_line(tail_back, center, Color(spark.tint, 0.31 * fade), 4.5 * fade, true)
	draw_line(tail_back.lerp(center, 0.43), center, Color(spark.tint.lerp(Color.WHITE, 0.42), 0.78 * fade), 2.0 * fade, true)
	var core: float = fade * (1.0 if expires else fade * fade) # 着弹时星身迅速压碎。
	_draw_exit_core(center, spark.spin + ease * (1.25 if expires else 0.47), core, spark.tint)
	var shatter: Vector2 = spark.b if wall else ray # 墙面法线保证扇形碎片不会穿进表面。
	var spread: float = 1.27 if wall or not expires else 0.91 # 自然消散只有细小余光。
	var count: int = 3 if expires else 7 # 碰撞有清晰的多层碎片。
	var span: float = 16.0 if expires else (46.0 if wall else 36.0) # 各退场的视觉尺度。
	for index: int in range(count): # 固定少量几何，无独立粒子对象。
		var slot: float = float(index) / float(count - 1) # 均匀展开扇形。
		var fragment: Vector2 = shatter.rotated(lerpf(-spread, spread, slot)) # 朝外施放。
		var travel: float = span * ease * (0.62 + float(index % 3) * 0.19) # 冷暖亮片错落。
		var tip: Vector2 = center + fragment * (5.0 + travel) # 亮端沿碎片自己的方向伸展开。
		draw_line(tip - fragment * minf(travel + 2.0, (10.0 + 4.0 * slot) * fade), tip,
			Color(spark.tint.lerp(Color.WHITE, 0.22 + 0.16 * float(index % 3)), fade * 0.9), (2.4 + 1.4 * slot) * fade, true)
	if not expires:
		draw_circle(point, 6.0 + 15.0 * ease, Color(spark.tint, 0.42 * fade), false, 1.8 * fade, true)

## 在 [param center] 绘制延续 [param rotation] 朝向、随 [param energy] 收缩的 [param tint] 星身。
func _draw_exit_core(center: Vector2, rotation: float, energy: float, tint: Color) -> void:
	if energy <= 0.04:
		return
	var radius: float = 10.6 * energy # 与飞行时的星形主体同尺度。
	draw_circle(center, radius * 1.81, Color(tint, 0.27 * energy), true, -1, true)
	for index: int in range(_star.size()): # 复用落星画布的十顶点缓存。
		_transformed[index] = center + _star[index].rotated(rotation) * radius
	draw_colored_polygon(_transformed, Color(tint.lerp(Color.WHITE, 0.59), 0.9 * energy))

## 绘制 [param spark] 的一次着弹，亡语 [param bloom] 通过更多金色棱片区分。
func _draw_hit(spark: Spark, bloom: bool) -> void:
	var t: float = spark.age / spark.duration # 渐隐进度。
	var spread: float = lerpf(7.0, 59.0 if bloom else 22.0, 1.0 - pow(1.0 - t, 2.0)) # 金色亡语范围更明显。
	var radius: float = 1.0 - t # 亮片渐灭。
	var count: int = 10 if bloom else 4 # 一般命中保持每次产生的几何很少。
	for shard: int in range(count): # 每片位于径向拉长的轨迹。
		var ray: Vector2 = Vector2.UP.rotated(TAU * shard / count + 0.22) # 避免四个正轴上出现机械对齐。
		draw_line(spark.point + ray * (spread * 0.53), spark.point + ray * spread, Color(spark.tint, radius), 2.1, true)
	draw_circle(spark.point, 5.0 + spread * 0.47, Color(spark.tint, radius * 0.22), true, -1, true)
	if bloom:
		_ellipse(spark.point, Vector2(spread * 1.18, spread * 0.76), Color(spark.tint, radius * 0.65), 1.8)

## 绘制 [param spark] 处一小段与真实换向一致的弧尾。
func _draw_turn(spark: Spark) -> void:
	var fade: float = 1.0 - spark.age / spark.duration # 最初清晰，随后留给移动中的星弹。
	var before: Vector2 = spark.point - spark.a * 33.0 # 背向入射，铺开轮廓。
	var after: Vector2 = spark.point + spark.b * 29.0 # 出射短线与锁定方向一致。
	var previous: Vector2 = before # 二次曲线逐段连线以避免分配数组。
	for index: int in range(1, 7): # 六小段足够平滑。
		var t: float = float(index) / 6.0 # 曲线采样。
		var next: Vector2 = before.lerp(spark.point, t).lerp(spark.point.lerp(after, t), t) # 通过真实转向点附近。
		draw_line(previous, next, Color(spark.tint, fade * 0.58), 2.3, true)
		previous = next
	draw_circle(spark.point, 4.0, Color(spark.tint.lerp(Color.WHITE, 0.68), fade * 0.84), true, -1, true)

## [param meteor] 的星身加速落下，彩色彗尾沿同一条轨迹逐渐变窄。
func _draw_falling(meteor: InFlight) -> void:
	var t: float = meteor.t # 预警从离开天空以前开始。
	var foot: Vector2 = meteor.foot # 脚点保留原板格位置。
	var slope: Vector2 = _fall_point(meteor, t) # 当前星身中心。
	var aura: float = 0.48 + t * 0.44 # 越接近越亮。
	var timing: float = 0.82 + 0.13 * sin(t * 31.0) # 地面预警在坑心压缩。
	_ellipse(foot, Vector2(70, 35) * timing, Color(1.0, 0.83, 0.46, aura), 2.9)
	_ellipse(foot, Vector2(50, 23), Color(1.0, 0.46, 0.46, aura * 0.67), 1.7)
	draw_line(foot + Vector2(-15, 0), foot + Vector2(15, 0), Color(1, 0.94, 0.63, aura), 1.4, true)
	draw_line(foot + Vector2(0, -8), foot + Vector2(0, 8), Color(1, 0.94, 0.63, aura), 1.4, true)
	var axis: Vector2 = (slope - _fall_point(meteor, maxf(0.0, t - 0.045))).normalized() # 姿态指向加速下落的方向。
	var side: Vector2 = axis.orthogonal() # 三束主要尾流并排穿过画面。
	for lane: int in range(-2, 3): # 同一条运动曲线使用各自的彩色宽度轮廓。
		var previous: Vector2 = slope + side * lane * 13.0 # 拖尾根部宽于顶端。
		var hue: Color = PRISM[lane + 2] # 色谱错开。
		for step: int in range(1, 9): # 时间长度自适应加速，显示真实曾经过的轨迹。
			var fade: float = float(step) / 9.0 # 越远越窄。
			var past: float = maxf(0.0, t - fade * 0.52) # 保留最多半程的采样。
			var point: Vector2 = _fall_point(meteor, past) + side * (lane * (13.0 + fade * 13.0)) # 扩散的彩带。
			draw_line(previous, point, Color(hue, 0.55 * (1.0 - fade)), (1.0 - fade) * 18.0 + 1.0, true)
			if step % 2 == 0:
				draw_circle(point + side * sin(step * 7.8 + lane) * 12.0, 2.1 + fade * 1.5, Color(hue, 0.86 - fade * 0.54), true, -1, true)
			previous = point
	draw_circle(slope, 83.0, Color(0.93, 0.53, 1.0, 0.11), true, -1, true)
	draw_circle(slope, 64.0, Color(1, 0.70, 0.38, 0.25), true, -1, true)
	_draw_prism(slope, 48.0 + t * 17.0, -0.6 + t * 2.6)

## [param meteor] 的 [param t] 归一化时刻，最后几十像素明显加速。
static func _fall_point(meteor: InFlight, t: float) -> Vector2:
	var end: Vector2 = meteor.foot + Vector2(0, -34) # 星尖先接地，红星从星身附近爆开。
	return Vector2(lerpf(meteor.start.x, end.x, t * (2.0 - t)), lerpf(meteor.start.y, end.y, t * t * (1.26 - 0.26 * t)))

## 为 [param center] 处、大小为 [param radius] 的星星绘制 [param angle] 朝向的六色切面。
func _draw_prism(center: Vector2, radius: float, angle: float) -> void:
	for index: int in range(10): # 外侧暗镶边作为巨星整体剪影。
		_transformed[index] = center + _star[index].rotated(angle) * (radius + 5.5)
	draw_colored_polygon(_transformed, DARK)
	for index: int in range(10): # 同一星的三角面轮换颜色与亮度。
		_triangle[0] = center - Vector2(1, 4)
		_triangle[1] = center + _star[index].rotated(angle) * radius
		_triangle[2] = center + _star[(index + 1) % 10].rotated(angle) * radius
		var color: Color = PRISM[(index / 2 + 1) % PRISM.size()] # 每个尖角两侧一明一暗。
		draw_colored_polygon(_triangle, color.lerp(Color.WHITE, 0.29 if index % 2 == 0 else 0.04))
		draw_line(_triangle[1], _triangle[2], Color(1, 0.96, 0.75, 0.92), 2.0, true)
	draw_circle(center - Vector2(1, 4), radius * 0.11, Color(1, 0.98, 0.86, 0.95), true, -1, true)

## 绘制 [param spark] 的短闪、两道扩张冲击波和地面的余辉。
func _draw_impact(spark: Spark) -> void:
	var t: float = spark.age / spark.duration # 只在开头几帧显示最强闪光。
	var power: float = 1.0 - t # 余波渐消。
	var point: Vector2 = spark.point # 真实格内的脚点。
	var reach: float = 0.44 + 1.18 * (1.0 - pow(power, 2.5)) # 最后的余辉越出落点，伤害仍按格结算。
	var pitch: Vector2 = spark.a # 地面冲击纹与真实格宽、行高相关。
	_ellipse(point, Vector2(pitch.x * 0.78, pitch.y * 0.46) * reach, Color(1.0, 0.37, 0.23, power * 0.89), 6.0 * power + 1.0)
	_ellipse(point, Vector2(pitch.x * 0.58, pitch.y * 0.21) * reach, Color(1.0, 0.89, 0.50, power), 2.6)
	draw_circle(point - Vector2(0, 15), 25.0 + 77.0 * t, Color(1.0, 0.6, 0.21, power * 0.24), true, -1, true)
	if t < 0.23:
		var flash: float = 1.0 - t / 0.23 # 短促亮心与瞬时冲击。
		draw_circle(point - Vector2(0, 23), 61.0 * flash + 8.0, Color(1.0, 0.92, 0.73, flash * 0.93), true, -1, true)
		draw_line(point - Vector2(0, 91 + 218 * flash), point, Color(1.0, 0.78, 0.51, flash * 0.47), 13.0 * flash + 2.0, true)
	for shard: int in range(16): # 比径向红星更短的光屑衬托由内到外的冲击。
		var angle: float = TAU * shard / 16.0 # 各片在地面平面上发散。
		var ray: Vector2 = Vector2(cos(angle), sin(angle) * 0.45) # 椭圆透视。
		var end: Vector2 = point + ray * ((48.0 + (shard % 4) * 11.5) * reach) - Vector2(0, sin(t * PI) * 36.0) # 获得小段上抛弧线。
		draw_line(end - ray * (15.0 + power * 20.0), end, Color(PRISM[shard % PRISM.size()], power), 1.2 + power * 3.3, true)

## 绘制 [param center]、[param radii] 的地面椭圆，使用 [param tint] 和 [param width]。
func _ellipse(center: Vector2, radii: Vector2, tint: Color, width: float) -> void:
	var points := PackedVector2Array() # 只有少量巨星和亡语需要椭圆界线。
	for sample: int in range(33): # 闭合冲击波。
		points.append(center + Vector2.RIGHT.rotated(TAU * sample / 32.0) * radii)
	draw_polyline(points, tint, width, true)
