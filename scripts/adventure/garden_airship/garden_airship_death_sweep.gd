## 使用同一 R4 风场推进真实死亡外观。只有活跃锚点占用更新和对象额度。
extends Node2D

## 沿用母图布边、云层和阵风统一指向的船尾方向。风力采样只改变强度。
const Wind := preload("res://scripts/adventure/garden_airship/garden_airship_wind.gd")
## 生成或测量无战斗脚本的实际可见图形。
const Pose := preload("res://scripts/adventure/garden_airship/garden_airship_death_pose.gd")
## 近云和剥离共用 1920 参考画幅的世界速度换算。
const FlowSpace := preload("res://scripts/adventure/garden_airship/garden_airship_flow_space.gd")
## 场均实际生成上限之外的表现余量；特殊机体保有独立的保留名额。
const MAX_SWEEPS: int = 60
## 允许余烬不占用整机和普通死亡的并发余量。
const MAX_FRAGMENTS: int = 16
## 短时间的异常兜底，正常死亡根据画面边缘和实际绘制区域回收。
const MAX_AGE: float = 2.6
## 右缘附加余量，单位为参考视口像素。
const BORDER_MARGIN: float = 62.0
## 外观 [param visual] 在 [param world] 开始向船尾脱离，[param weight] 供局部风声分级。
signal detached(world: Vector2, visual: Node2D, weight: float)

## 一个外观的船尾运动与生命周期。复用统一时钟，自身无处理回调。
class Sweep extends Node2D:
	## 当前世界速度，单位为像素每战斗秒。
	var world_velocity: Vector2
	## 0 到 1，从轻小碎片到重型机壳。
	var weight: float
	## 已经脱离的战斗秒数，暂停后停止累计。
	var age: float = 0.0
	## 开始时的角速度，单位为弧度每秒。
	var spin: float
	## 受驱动的纯表现根，可被该素材自身提前回收。
	var visual: Node2D
	## 原处的位移与画布层均由上面的外壳保存。
	var kind: StringName

## 当局同一个 R4 风场，不独立生成环境噪声。
var _wind: Wind
## 当局所有实际激活的扫离代理。
var _active: Array[Sweep] = []
## 当前活跃的原生装备/肢体小碎片数。
var _fragment_count: int = 0

## [param wind] 是 FlightEnvironment 每帧提交的当局共享风场。
func setup_wind(wind: Wind) -> void:
	_wind = wind


## 将已经独立的 [param visual] 搬到同一画布的风场驱动器，返回它的位移锚点。
## [param weight] 为类别惯性，[param velocity] 是已有运动，[param kind] 识别原生演出。
## [param event_world] 可覆盖反馈起点，供机头先触地但机身锚点在空中的机型使用。
func sweep_visual(visual: Node2D, weight: float, velocity: Vector2, kind: StringName,
		event_world: Vector2 = Vector2.INF) -> Node2D:
	if not is_inside_tree() or not is_instance_valid(visual) or not visual.is_inside_tree() \
			or visual.is_queued_for_deletion():
		return null
	if not _can_start(kind):
		return null
	var previous := visual.get_parent() as CanvasItem # 原相对变换也是部分逐帧轨迹的坐标基准。
	if previous == null or get_canvas() != visual.get_canvas():
		return null
	var start: Vector2 = visual.global_position # 代理首帧与原外观完全重合。
	var sweep: Sweep = _add_sweep(start, weight, velocity, kind, Pose.absolute_z(previous)) # 自身原 Z 继续相对于旧父系的等效层。
	var frame := Node2D.new() # 避免采用旧局部轨迹的动画在重挂后跳回原点。
	frame.modulate = Pose.inherited_tint(visual, get_parent() as CanvasItem)
	frame.material = Pose.inherited_material(previous)
	sweep.add_child(frame)
	frame.global_transform = previous.get_global_transform()
	visual.reparent(frame, false)
	sweep.visual = visual
	if kind == &"fragment":
		_fragment_count += 1
	detached.emit(event_world if event_world.is_finite() else start, sweep, weight)
	return sweep


## [param kind] 为原演出类型，仲裁者首触保有专用额度。
func _can_start(kind: StringName) -> bool:
	var capacity: int = MAX_SWEEPS if kind == &"arbiter" else MAX_SWEEPS - 2 # 避免群击抢掉首触名额。
	return _active.size() < capacity and (kind != &"fragment" or _fragment_count < MAX_FRAGMENTS)


## 建立 [param start] 处的独立纯表现锚点，使用 [param depth] 的实际画布层。
## [param weight]、[param velocity] 和 [param kind] 分别指定惯性、继承速度和类别。
func _add_sweep(start: Vector2, weight: float, velocity: Vector2, kind: StringName, depth: int) -> Sweep:
	var sweep := Sweep.new() # 只在死亡事件分配，活角色没有逐帧开销。
	sweep.name = &"DeathSweep"
	sweep.weight = weight
	sweep.kind = kind
	sweep.z_as_relative = false
	sweep.z_index = clampi(depth, RenderingServer.CANVAS_ITEM_Z_MIN, RenderingServer.CANVAS_ITEM_Z_MAX)
	sweep.set_meta(&"death_kind", kind)
	sweep.add_to_group(&"garden_airship_death_proxy")
	add_child(sweep)
	sweep.global_position = start
	var scale_factor: float = FlowSpace.reference_to_world(get_viewport_rect().size.x, get_canvas_transform(), Wind.DIRECTION) # 真实可见宽度换算。
	var aft: float = lerpf(600.0, 405.0, weight) * scale_factor # 先看见脱离支撑的滑移，再被气流带快。
	var inherited: float = clampf(velocity.dot(Wind.DIRECTION) * 0.24, -aft * 0.15, aft * 0.2) # 生前逆风移动不能抹去船尾速度。
	var lift: float = lerpf(-86.0, -33.0, weight) * scale_factor # 轻微抬离地面，重片的惯性更明显。
	sweep.world_velocity = Wind.DIRECTION * (aft + inherited) + Vector2(0.0, lift + clampf(velocity.y * 0.22, -45.0, 68.0) * scale_factor)
	var roll: float = lerpf(156.0, 50.0, weight) # 让整具身体先倾倒，小碎片可以快速打转。
	if kind == &"fragment" or kind == &"ashes":
		roll = lerpf(400.0, 120.0, weight)
	if kind == &"arbiter":
		roll = 38.0
	sweep.spin = deg_to_rad(roll)
	_active.append(sweep)
	set_process(true)
	return sweep


## [param delta] 是战斗经过的秒数，随同现有暂停和倍速规则。
func _process(delta: float) -> void:
	var viewport_rect: Rect2 = get_viewport_rect() # 使用相机画布的实际可见区域。
	var canvas: Transform2D = get_canvas_transform() # 同帧所有外观共用相机变换。
	var factor: float = FlowSpace.reference_to_world(viewport_rect.size.x, canvas, Wind.DIRECTION) # 窄窗口保持相同离场体感。
	var edge: float = viewport_rect.end.x + BORDER_MARGIN * viewport_rect.size.x / FlowSpace.REFERENCE_WIDTH # 整块素材离开后回收。
	for index: int in range(_active.size() - 1, -1, -1): # 从末尾清理，避免为遍历分配副本。
		var sweep: Sweep = _active[index] # 只推进实际存在的死亡外观。
		if not is_instance_valid(sweep.visual) or sweep.visual.is_queued_for_deletion():
			_recycle(index)
			continue
		_advance(sweep, factor, delta)
		if (canvas * sweep.global_position).x >= edge:
			var bounds: Rect2 = Pose.canvas_bounds(sweep.visual) # 允许机身、旋转中的部件和尾部全部通过。
			if not bounds.has_area() or bounds.position.x >= edge:
				_recycle(index)
				continue
		if sweep.age > MAX_AGE:
			sweep.modulate.a = 1.0 - smoothstep(MAX_AGE, MAX_AGE + 0.22, sweep.age)
			if sweep.modulate.a <= 0.0:
				_recycle(index)
	if _active.is_empty():
		set_process(false)


## 用 [param factor] 换算世界速度，加速 [param sweep] 一个 [param delta] 战斗时间步。
func _advance(sweep: Sweep, factor: float, delta: float) -> void:
	var gust: float = _wind.gust_at(sweep.global_position.x, 0.18 + 0.09 * sweep.weight) if _wind != null else 0.0 # 烟和布先显出风，残骸按惯性稍后跟上。
	gust *= smoothstep(0.025, 0.22, sweep.age + delta * 0.5)
	var cruise_tau: float = lerpf(0.19, 0.27, sweep.weight) # 常态给予约 0.2 秒的起势。
	var tau: float = lerpf(cruise_tau, lerpf(0.10, 0.17, sweep.weight), gust) # 强风缩短后段跟风的时间常数。
	var cruise_speed: float = lerpf(1900.0, 1680.0, sweep.weight) # 巡航参考速度，按重量减速。
	if _wind != null:
		cruise_speed *= lerpf(1.0, _wind.airspeed_ratio, 0.16) # 只共享小幅巡航漂移，标定档及强风目标保持原速。
	var speed: float = lerpf(cruise_speed, lerpf(3190.0, 2800.0, sweep.weight), gust) # 高速拖离只在真实强气流的局部成立。
	var vertical: float = lerpf(-33.0, 90.0, sweep.weight) - gust * 85.0 # 巡航以轻微下沉为主，强风才明显向上托。
	var target: Vector2 = (Wind.DIRECTION * speed + Vector2(0.0, vertical)) * factor # 不采样横风符号。
	var decay: float = exp(-delta / tau) # 30、60、120 FPS 使用同一解析解。
	var relative: Vector2 = sweep.world_velocity - target # 在该步内衰减的初始速度差。
	sweep.global_position += target * delta + relative * tau * (1.0 - decay)
	sweep.world_velocity = target + relative * decay
	sweep.global_rotation += sweep.spin * (1.0 + 0.26 * gust) * delta
	sweep.age += delta


## [param index] 处的外观和挂点同时释放，短音源再也不能引用已退场的实例。
func _recycle(index: int) -> void:
	var sweep: Sweep = _active[index] # 本节点或素材生命周期已到达回收条件。
	if sweep.kind == &"fragment":
		_fragment_count -= 1
	_active.remove_at(index)
	sweep.queue_free()
