## 玉米粒弹幕、空袭和玉米炮共用一张短效果画布。
extends Node2D

## 飞行种类供战斗和画布共用。
enum Kind { KERNEL, BUTTER, RAID, COB }
## 原生贴图只在实际玉米投手的战斗加载，帽子是独立美术。
const KERNEL := preload("res://assets/reanim/Cornpult_kernal.png")
## 落到僵尸脸上的黄油也使用原有贴图。
const BUTTER := preload("res://assets/reanim/Cornpult_butter.png")
## 转基因使用原生玉米加农炮的旋转造型。
const COB := preload("res://assets/reanim/CobCannon_cob.png")
## 高密度时有限画面对象，任何逻辑投掷仍照常到期。
const FLIGHT_LIMIT: int = 96
## 局部落点只短暂占用有限显示容量。
const BURST_LIMIT: int = 44
## 空袭各雨点的画面间隔与伤害节拍一致。
const RAIN_STEP: float = 0.105
## 共享地面圆弧精度。
const CIRCLE_STEPS: int = 36

## 只给可见飞行创建的短记录。
class Flight:
	## 图形类型。
	var kind: Kind
	## 起手时世界弹口。
	var start: Vector2
	## 原瞄准点，目标离场后落向此处。
	var aim: Vector2
	## 锁定场地，首雨之前允许跟随有效敌人。
	var cell: PlantCell
	## 真目标用来跟随弧线，不保存伤害状态。
	var target: Character000Base
	## 地面预警锚点。
	var foot: Vector2
	## 含同轮出手间隔的游戏时钟，负数等待发射。
	var age: float
	## 首次落点时间。
	var duration: float
	## 不消耗玩法随机数的轨迹构型。
	var serial: int
	## 攻击真正落到格子后固定位置，保持六次雨点的中心一致。
	var landed: bool = false

## 短暂的入地、溅油、碎粒和炮弹爆破。
class Burst:
	## 表现种类。
	var kind: Kind
	## 跟随真实碰撞或地面。
	var point: Vector2
	## 格子半径投影。
	var pitch: Vector2
	## 范围模式比单发更宽。
	var wide: bool
	## 落雨序号控制碎粒方向。
	var phase: int
	## 谢谢惠顾命中反馈使用紫色碎片。
	var poison: bool
	## 游戏秒。
	var age: float = 0.0
	## 结束秒数。
	var duration: float

## 只遍历活动且受显示预算限制的飞行。
var _flights: Array[Flight] = []
## 已落点短效。
var _bursts: Array[Burst] = []
## 预计算的单位圆。
var _unit_circle := PackedVector2Array()
## 单个圆的工作数组，可安全反复提交到画布。
var _ellipse := PackedVector2Array()

## 初始化共用几何后进入休眠。
func _ready() -> void:
	for index: int in range(CIRCLE_STEPS + 1): # 闭合线段留重复端点。
		_unit_circle.append(Vector2.RIGHT.rotated(TAU * float(index) / CIRCLE_STEPS))
	_ellipse.resize(_unit_circle.size())
	set_process(false)

## [param kind] 从 [param origin] 飞往 [param aim]，用 [param cell] 与 [param foot] 标定预警。
## [param target] 支持落雨前跟随。[param delay]、[param duration] 与 [param serial] 同步于投掷。
func flight(kind: Kind, origin: Vector2, aim: Vector2, cell: PlantCell, foot: Vector2,
		target: Character000Base, delay: float, duration: float, serial: int) -> Flight:
	if _flights.size() >= FLIGHT_LIMIT:
		if kind != Kind.COB:
			return null
		_flights.pop_front()
	var item := Flight.new() # 只有优先的可视飞行才产生记录。
	item.kind = kind
	item.start = origin
	item.aim = aim
	item.cell = cell
	item.target = target
	item.foot = foot
	item.age = -delay
	item.duration = duration
	item.serial = serial
	_flights.append(item)
	set_process(true)
	return item

## [param kind] 在 [param floor] 或 [param hit] 附近落地；[param pitch] 来自实际格距。
## [param wide]、[param phase] 与 [param poison] 区分同一阵落雨或负面命中。
func impact(kind: Kind, floor: Vector2, hit: Vector2, pitch: Vector2,
		wide: bool, phase: int, poison: bool) -> void:
	if _bursts.size() >= BURST_LIMIT:
		if kind != Kind.COB:
			return
		_bursts.pop_front()
	var burst := Burst.new() # 真实命中决定唯一的视觉落点。
	burst.kind = kind
	burst.point = to_local(floor if wide else hit)
	burst.pitch = pitch
	burst.wide = wide
	burst.phase = phase
	burst.poison = poison
	burst.duration = 0.59 if kind == Kind.COB else (0.36 if kind == Kind.BUTTER else 0.22)
	_bursts.append(burst)
	set_process(true)

## [param delta] 推进显示时钟，普通飞行结束后只留共用落点表现。
func _process(delta: float) -> void:
	for index: int in range(_flights.size() - 1, -1, -1): # 部分超载飞行交给逻辑结算，不进入这里。
		var item: Flight = _flights[index] # 初次落雨冻结中心，后续覆盖固定的3×3。
		item.age += delta
		if item.age >= item.duration + (RAIN_STEP * 5 + 0.03 if item.kind == Kind.RAID else 0.0):
			_flights.remove_at(index)
		elif not item.landed and item.age < item.duration and is_instance_valid(item.target) \
				and is_instance_valid(item.target.hurt_box_component) and not item.target.is_death and not item.target.is_hypno:
			var current: Vector2 = item.target.hurt_box_component.global_position # 只更新正在显示的有限弹幕。
			if item.kind == Kind.RAID and item.target is Zombie000Base:
				item.foot = item.target.global_position
			elif item.kind == Kind.COB and absf(item.aim.x - current.x) <= 200.0 and item.target is Zombie000Base:
				item.foot = item.target.global_position
	for index: int in range(_bursts.size() - 1, -1, -1): # 爆炸碎片不会成为独立节点。
		_bursts[index].age += delta
		if _bursts[index].age >= _bursts[index].duration:
			_bursts.remove_at(index)
	queue_redraw()
	set_process(not _flights.is_empty() or not _bursts.is_empty())

## 先画落点与地面环，再画彩色弹道，表现层与伤害上限独立。
func _draw() -> void:
	for burst: Burst in _bursts: # 所有短效共享坐标计算。
		_draw_burst(burst)
	var sky: float = (get_viewport().canvas_transform.affine_inverse() * Vector2(0, -82)).y # 世界天空边缘。
	for item: Flight in _flights: # 数量始终受显示预算约束。
		if item.age < 0.0:
			continue
		match item.kind:
			Kind.RAID: _draw_raid(item, sky)
			Kind.COB: _draw_cob(item, sky)
			_: _draw_arc_flight(item)

## [param item] 沿投手原生风格的高弧线运动，向地面自然加速。
func _draw_arc_flight(item: Flight) -> void:
	var t: float = clampf(item.age / item.duration, 0.0, 1.0) # 实际出手至着地的相位。
	var start: Vector2 = to_local(item.start) # 表现附在战场坐标上。
	var aim: Vector2 = item.aim # 原生射界内才跟着仍可命中的受击点移动。
	if is_instance_valid(item.target) and is_instance_valid(item.target.hurt_box_component) \
			and not item.target.is_death and not item.target.is_hypno:
		var current: Vector2 = item.target.hurt_box_component.global_position # 不累计追踪上限的误差。
		if absf(item.aim.x - current.x) <= 200.0:
			aim = current
	var end: Vector2 = to_local(aim + Vector2(0, -18)) # 真实受击锚点。
	var high: float = 142.0 if item.kind == Kind.BUTTER else 161.0 # 黄油较沉、粒弹更轻。
	var point: Vector2 = start.lerp(end, t) + Vector2(0, -sin(PI * t) * high) # 高抛后落到目标。
	var trail_t: float = maxf(0.0, t - 0.08) # 短尾遵循同一真实弧线。
	var trail: Vector2 = start.lerp(end, trail_t) + Vector2(0, -sin(PI * trail_t) * high) # 弹尾不跑出轨迹。
	draw_line(trail, point, Color(1.0, 0.75, 0.28, 0.41), 3.4, true)
	_sprite(BUTTER if item.kind == Kind.BUTTER else KERNEL, point, item.age * 7.1,
		0.68 if item.kind == Kind.BUTTER else 0.94, Color.WHITE)

## [param item] 朝 [param sky] 起射，之后六粒轮番落到标记附近。
func _draw_raid(item: Flight, sky: float) -> void:
	if item.age < 0.38:
		_draw_rise(item, sky, false)
	if not is_instance_valid(item.cell) or item.age < 0.17:
		return
	var center: Vector2 = to_local(item.foot) # 在首雨时从动态脚点转换为固定锁定方向。
	if item.landed and is_instance_valid(item.cell):
		center = to_local(item.cell.get_spawn_global_position())
	var color := Color(1.0, 0.78, 0.25) # 粒弹金黄和炮弹橙红容易辨别。
	var ramp: float = clampf((item.age - 0.17) / 0.16, 0.0, 1.0) # 先显露预警，再连续响六次。
	_marker(center, Vector2(40, 18), color, ramp * 0.77, item.age)
	for index: int in range(6): # 每个有效雨点有清楚的天空轨迹。
		var due: float = item.duration + index * RAIN_STEP # 每组效果和结算使用相同节拍。
		var time: float = (item.age - due + 0.245) / 0.245 # 只有下落窗口的粒子可见。
		if time < 0.0 or time > 1.0:
			continue
		var offset: Vector2 = Vector2(sin(float(item.serial % 53) * 3.0 + index * 2.4) * 62.0,
			cos(index * 3.88) * 25.0) # 在同一格圈内给六次雨点微小错位。
		var stop: Vector2 = center + offset - Vector2(0, 10) # 清楚落到预警脚点。
		var top: Vector2 = Vector2(stop.x - 79.0, maxf(to_local(Vector2(0, sky)).y, stop.y - 410.0)) # 斜向成束但不贴地。
		var point: Vector2 = top.lerp(stop, time * time) # 重力加速。
		var tail: Vector2 = top.lerp(stop, pow(maxf(0.0, time - 0.18), 2.0)) # 同弹闪亮尾迹。
		draw_line(tail, point, Color(color, 0.23), 13.0, true)
		draw_line(tail.lerp(point, 0.34), point, Color(1, 0.95, 0.65, 0.92), 3.6, true)
		_sprite(KERNEL, point, 1.28, 0.97, Color(1.34, 1.2, 0.78))

## [param item] 的玉米炮先向 [param sky] 飞出，再以大弹体、高亮尾流和地面警戒圈落下。
func _draw_cob(item: Flight, sky: float) -> void:
	if item.age < 0.38:
		_draw_rise(item, sky, true)
	var foot: Vector2 = to_local(item.foot) # 爆心取发射时的进攻行脚点。
	_marker(foot, Vector2(70, 34), Color(1.0, 0.38, 0.20), smoothstep(0.19, 0.44, item.age), item.age)
	if item.age < 0.49:
		return
	var t: float = clampf((item.age - 0.49) / (item.duration - 0.49), 0.0, 1.0) # 引擎先悬停，尾段急坠。
	var top: Vector2 = Vector2(foot.x - 178, minf(foot.y - 420, to_local(Vector2(0, sky)).y)) # 从实景可视边缘之外出现。
	var end: Vector2 = foot - Vector2(0, 20) # 弹头先接触地面。
	var point: Vector2 = top.lerp(end, t * t) # 下落位移按二次加速。
	var tail: Vector2 = top.lerp(end, pow(maxf(0.0, t - 0.32), 2.0)) # 粗尾迹在冲击前显露。
	draw_line(tail, point, Color(1, 0.42, 0.12, 0.32), 33.0, true)
	draw_line(tail.lerp(point, 0.29), point, Color(1, 0.73, 0.22, 0.73), 16.0, true)
	draw_line(tail.lerp(point, 0.47), point, Color(1, 0.95, 0.64, 0.94), 5.5, true)
	draw_circle(point, 48.0, Color(1, 0.60, 0.18, 0.18), true, -1, true)
	_sprite(COB, point, (end - top).angle(), 0.90 + 0.32 * t, Color(1.13, 1.0, 0.78))

## 从 [param item] 的真弹口发射升空段，[param heavy] 控制引擎光的尺度，[param sky] 是上边缘。
func _draw_rise(item: Flight, sky: float, heavy: bool) -> void:
	var t: float = clampf(item.age / 0.38, 0.0, 1.0) # 出射后迅速提高垂直速度。
	var start: Vector2 = to_local(item.start) # 弹口相对甲板位置保持真实。
	var end: Vector2 = Vector2(start.x + 29 + (item.serial % 7) * 12, minf(start.y - 330, to_local(Vector2(0, sky)).y)) # 错开的上行通道。
	var point: Vector2 = start.lerp(end, t * t) # 头部朝天空。
	var tail: Vector2 = start.lerp(end, pow(maxf(0.0, t - 0.21), 2.0)) # 从弹口拉出一小段贯通的亮线。
	draw_line(tail, point, Color(1.0, 0.61, 0.20, 0.53), 17.0 if heavy else 8.0, true)
	draw_line(tail.lerp(point, 0.43), point, Color(1.0, 0.93, 0.59, 0.84), 5.0 if heavy else 2.4, true)
	_sprite(COB if heavy else KERNEL, point, (end - start).angle(), 0.68 if heavy else 0.97, Color.WHITE)

## 位于 [param center] 的地面预警。[param radii]、[param tint]、[param alpha] 和 [param time] 给出节奏。
func _marker(center: Vector2, radii: Vector2, tint: Color, alpha: float, time: float) -> void:
	_draw_ellipse(center, radii * (0.92 + 0.08 * sin(time * 22.0)), Color(tint, alpha), 2.5)
	_draw_ellipse(center, radii * 0.65, Color(tint, alpha * 0.49), 1.5)
	draw_line(center - Vector2(9, 0), center + Vector2(9, 0), Color(tint, alpha), 1.8, true)
	draw_line(center - Vector2(0, 5), center + Vector2(0, 5), Color(tint, alpha), 1.8, true)

## [param burst] 以真实落点画冲击圈、金色黄油或紫色中毒碎粒，所有余波只绘制有限棱片。
func _draw_burst(burst: Burst) -> void:
	var t: float = burst.age / burst.duration # 归一化寿命。
	var fade: float = 1.0 - t # 亮度衰减。
	var spread: float = 1.0 - fade * fade # 前期碎片更快。
	var center: Vector2 = burst.point # 实际格或实际直击。
	var heavy: bool = burst.kind == Kind.COB # 炮弹爆炸的余波明显重于粒弹。
	var tint: Color = Color(0.91, 0.49, 1.0) if burst.poison else Color(1.0, 0.80, 0.28) # 紫毒、常规粒弹与黄油共享短效。
	if heavy:
		tint = Color(1.0, 0.49, 0.14)
		var flare: float = maxf(0.0, 1.0 - 4.2 * t) # 白热先爆开，随后用橙色余焰承接。
		var core: Vector2 = center - Vector2(0, 42) # 高出地面光环，爆心贴合下降的弹头。
		draw_circle(core, 42.0 + 68.0 * flare, Color(1.0, 0.67, 0.17, flare * 0.58), true, -1, true)
		draw_circle(core, 28.0 + 52.0 * flare, Color(1.0, 0.95, 0.71, flare * 0.95), true, -1, true)
		for index: int in range(7): # 放射的暖色烟团带来芒粒膨爆感。
			var angle: float = PI * float(index) / 6.0 # 前缘向上掀起。
			var direction := Vector2(cos(angle), -sin(angle)) # 程序烟团不另外占节点。
			var plume: Vector2 = center - Vector2(0, 14) + direction * Vector2(111.0, 65.0) * spread # 先向外翻起，随后消散。
			draw_circle(plume, 12.0 + 24.0 * spread, Color(0.51, 0.22, 0.09, fade * 0.34), true, -1, true)
			draw_circle(plume - Vector2(0, 8), (12.0 + 18.0 * spread) * fade,
				Color(1.0, 0.73, 0.28, fade * 0.49), true, -1, true)
		_draw_ellipse(center, Vector2(0.72, 0.46) * burst.pitch * (0.53 + 0.92 * spread), Color(1.0, 0.44, 0.16, fade), 2.5 + fade * 6.0)
	if burst.wide:
		_draw_ellipse(center, Vector2(0.51, 0.22) * burst.pitch * (0.4 + spread * (1.60 if heavy else 0.85)),
			Color(tint, fade * 0.82), 1.8 + fade * 2.5)
	if burst.kind == Kind.BUTTER and burst.wide:
		draw_circle(center, 16.0 + 22 * spread, Color(1.0, 0.72, 0.13, 0.22 * fade), true, -1, true)
	var count: int = 16 if heavy else (7 if burst.wide else 4) # 只生成少量批绘碎粒。
	for index: int in range(count): # 使用确定性相位，视觉不扰动技能概率。
		var ray: Vector2 = Vector2.RIGHT.rotated(TAU * index / count + burst.phase * 0.53) # 六次落雨的飞散角错开。
		var reach: float = (116.0 if heavy else (46.0 if burst.wide else 20.0)) * (0.34 + 0.71 * spread) # 爆破更开阔。
		var a: Vector2 = center + ray * Vector2(reach, reach * 0.44) - Vector2(0, sin(PI * t) * (49.0 if heavy else 17.0)) # 上抛后落回真实地面。
		draw_line(a - ray * (12.0 if heavy else 6.0) * fade, a,
			Color(tint.lerp(Color.WHITE, index % 3 * 0.26), fade * 0.9), 1.4 + fade * (3.8 if heavy else 1.7), true)

## [param center] [param radii] 椭圆以 [param color] 和 [param width] 复用固定采样。
func _draw_ellipse(center: Vector2, radii: Vector2, color: Color, width: float) -> void:
	for index: int in range(_unit_circle.size()): # 无三角网格或临时绘制节点。
		_ellipse[index] = center + _unit_circle[index] * radii
	draw_polyline(_ellipse, color, width, true)

## [param texture] 以实际 [param point]、[param angle]、[param size] 和 [param tint] 加入画布。
func _sprite(texture: Texture2D, point: Vector2, angle: float, size: float, tint: Color) -> void:
	draw_set_transform(point, angle, Vector2.ONE * size)
	draw_texture(texture, -texture.get_size() * 0.5, tint)
	draw_set_transform(Vector2.ZERO)
