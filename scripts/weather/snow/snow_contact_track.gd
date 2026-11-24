## 单个战斗僵尸的接触状态；只保存有界坐标、轮流落脚节拍与本步原生事件。
extends RefCounted
class_name SnowContactTrack

## 同一段接触的模式。行走和滚动互斥；拖行只由移动组件告知。
enum Mode { INACTIVE, WALK, ROLL, SLIDE }
## 真实步段渲染与相邻坡点采样。
const Path = preload("res://scripts/weather/snow/snow_contact_path.gd")
## 植物与僵尸共用的环境色和抖雪记录。
const ActorCover = preload("res://scripts/weather/snow/snow_actor_cover.gd")
## 当前场景的批绘脚边雪。
const Footing = preload("res://scripts/weather/snow/snow_footing.gd")
## 最大可连接位移，单位世界像素；大跳变视为传送或无效补帧。
const MAX_GAP: float = 56.0
## 换行到达新行前允许的最大脚点高度误差，单位世界像素。
const LANE_TOLERANCE: float = 5.0

## 接触配置：X 为地面步距，Y 和 Z 为足缘和载具雪槽的尺寸，均为世界像素。
var _gait: Vector3
## 交替步距供步行扬雪与足缘脉冲使用。
var _path: Path
## 原登记器持有的角色环境色和抖雪。
var cover: ActorCover
## 最近一次消耗预算的脚步、落地或滚动响应位置。
var _touch: Vector2 = Vector2.INF
## 接触响应余量，从 1 以约 0.2 游戏秒衰减。
var _pulse: float = 0.0
## 退场时要解除的原生事件及绑定回调。
var _subscriptions: Dictionary[Signal, Callable] = {}
## 上次观测到的地面 X；历史重置时由 _mode 与 _lane 禁用连线。
var _x: float = 0.0
## 上次观测的攻击行；无有效接触为 -1。
var _lane: int = -1
## 上次观测是位移、停车还是空中。
var _mode: Mode = Mode.INACTIVE
## 最新落地坐标，只待一个天气步。
var _landing: Vector2 = Vector2.INF
## 原落地行，防止队列中的旧接触跨到新行。
var _landing_lane: int = -1
## 接触时上一跳杆落点；原地反复蓄跳只留首次。
var _last_pogo: Vector2 = Vector2.INF
## 待消费的强推扫掠，X/Y 为起末 X，Z 为攻击行，INF 表示无。
var _slide: Vector3 = Vector3.INF

## 取 [param zombie] 物种和尺寸，只构造视觉脚型。
func _init(zombie: Zombie000Base) -> void:
	var scale: float = clampf(zombie.global_transform.x.length(), 0.35, 2.0) # 世界缩放只影响视觉尺寸。
	var base: Vector3 = Vector3(13.0, 15.0, 9.0) # 普僵、旗手、路障与铁桶共用人形步幅。
	match zombie.zombie_type:
		CharacterRegistry.ZombieType.Z004PoleVaulter: base = Vector3(17.0, 17.0, 9.0)
		CharacterRegistry.ZombieType.Z008Football, CharacterRegistry.ZombieType.Z026AllStar:
			base = Vector3(20.0, 19.0, 11.0)
		CharacterRegistry.ZombieType.Z024Gargantuar: base = Vector3(28.0, 27.0, 15.0)
		CharacterRegistry.ZombieType.Z025Imp: base = Vector3(10.0, 10.0, 6.5)
		CharacterRegistry.ZombieType.Z029LargeFusion: base = Vector3(24.0, 31.0, 23.0)
	_gait = base * scale
	_path = Path.new(_gait.x, _gait.z)
	cover = ActorCover.new(zombie)

## 丢弃连接历史；停车、离开战斗、跨道和跳变后等待新的有效位移。
func reset_path() -> void:
	_mode = Mode.INACTIVE
	_lane = -1
	_path.reset()

## 清除尚未提交的原生事件，防止选卡恢复后补写。
func clear_events() -> void:
	_landing = Vector2.INF
	_slide = Vector3.INF

## 暂停跨阶段的历史和响应，同时还原已应用的场景颜色。
func suspend() -> void:
	reset_path()
	clear_events()
	_pulse = 0.0
	cover.suspend()

## 按 [param zombie] 落地时的位置使用 [param surface] 取地面；越界或横穿行间时丢弃。
func capture_landing(zombie: Zombie000Base, surface: SnowSurface) -> void:
	var point: Vector2 = surface.ground_point(zombie.global_position.x, zombie.lane) # 原事件瞬间的地面投影。
	if not _on_lane(zombie, point) or not surface.allows_contact(point):
		return
	if zombie is Zombie019Pogo:
		if _last_pogo.is_finite() and _last_pogo.distance_squared_to(point) < 16.0:
			return
		_last_pogo = point
	_landing = point
	_landing_lane = zombie.lane

## 接收 [param zombie] 在 [param surface] 上从 [param from_x] 到 [param to_x] 的真实水平推移。
func capture_slide(zombie: Zombie000Base, surface: SnowSurface, from_x: float, to_x: float) -> void:
	var distance: float = absf(to_x - from_x) # 过滤瞬移和零位移，低速仍可跨物理子步合并。
	if distance <= 0.001 or distance > MAX_GAP or not _can_touch(zombie) or zombie.move_component.curr_speed_product <= 0.0:
		return
	if not _on_lane(zombie, surface.ground_point(to_x, zombie.lane)):
		return
	# 仅合并没有中断且同方向的推移。
	var same_route: bool = _slide.is_finite() and int(_slide.z) == zombie.lane \
		and is_equal_approx(_slide.y, from_x) and signf(_slide.y - _slide.x) == signf(to_x - from_x)
	if same_route and absf(to_x - _slide.x) <= MAX_GAP:
		_slide.y = to_x
	else:
		_slide = Vector3(from_x, to_x, float(zombie.lane))

## 从 [param zombie] 的世界脚点读取当前步段。[param surface] 接收连续雪槽，[param puffs] 接收步行、落地与滚动雪晶。
## [param budget] 为本帧余量，[param delta] 为游戏秒，[param point] 为本帧共用的坡面脚点。[br]
## 超额也更新历史，返回已消费的输入次数。
func sample(zombie: Zombie000Base, surface: SnowSurface, puffs: SnowContactPuffs, budget: int, delta: float,
		point: Vector2) -> int:
	_pulse = move_toward(_pulse, 0.0, delta * 5.2)
	var lane: int = zombie.lane # 行号确定唯一坡面脚点。
	var x: float = zombie.global_position.x # 根节点横坐标不混入动画抬脚和镜像偏移。
	var used: int = 0 # 本次已提交的地面接触。
	if _landing.is_finite():
		if budget > 0 and lane == _landing_lane:
			puffs.burst(_landing, true)
			_touch = _landing
			_pulse = 1.0
			used += 1
		reset_path()
	var mode: Mode = _contact_mode(zombie, point) # 有效的动作态与实际位移必须同时存在。
	if _slide.is_finite() and lane == int(_slide.z) and not _landing.is_finite():
		used += Path.sweep(surface, _slide.x, _slide.y, lane, _gait.z * 1.32, 0.45, budget - used)
		mode = Mode.SLIDE
	clear_events()
	var change: float = x - _x # 只累加真实横向前进，不累加逐帧身体姿态。
	if mode == _mode and lane == _lane and absf(change) > 0.001 and absf(change) <= MAX_GAP:
		if mode == Mode.ROLL:
			var segments: int = Path.sweep(surface, _x, x, lane, _gait.z * 1.68, 0.88, budget - used) # 原连续雪槽预算。
			used += segments
			if segments > 0 and _pulse <= 0.0:
				_touch = point
				_pulse = 0.82
				var normal: Vector2 = surface.ground_tangent(x, lane).orthogonal() # 雪槽两侧各少量粉雪。
				puffs.burst(point + normal * _gait.z * 0.65, false, true)
				puffs.burst(point - normal * _gait.z * 0.65, false, true)
		elif mode == Mode.WALK:
			used += _path.walk(surface, puffs, surface.ground_point(_x, lane), point, lane, _shadow_offset(zombie), budget - used)
			if _path.latest_step.is_finite():
				_touch = _path.latest_step
				_pulse = 0.63
	elif mode != _mode or lane != _lane or absf(change) > MAX_GAP:
		reset_path()
	_mode = mode
	_lane = lane
	_x = x
	return used

## [param zombie] 必须具备陆地接触资格，排除原生飞行、共用抛飞、水面和攀爬。
func _can_touch(zombie: Zombie000Base) -> bool:
	return zombie.curr_be_attack_status == Zombie000Base.E_BeAttackStatusZombie.IsNorm \
		and not zombie.is_body_up_from_ground and not zombie.is_swimming and not zombie.is_native_airborne() \
		and not zombie.move_component.is_forced_airborne() \
		and zombie.move_component.ladder_state == MoveComponent.E_LadderState.None

## [param zombie] 的空间脚点与 [param point] 足够接近；换行途中跳过接触表现。
func _on_lane(zombie: Zombie000Base, point: Vector2) -> bool:
	return point.is_finite() and absf(zombie.global_position.y - point.y) <= LANE_TOLERANCE

## 从 [param zombie] 和 [param point] 判定接触来源；抛飞、空转和冻结不推进步行或滚动接触。
func _contact_mode(zombie: Zombie000Base, point: Vector2) -> Mode:
	if not _can_touch(zombie) or not _on_lane(zombie, point) or zombie.move_component.curr_speed_product <= 0.0:
		return Mode.INACTIVE
	if zombie.move_component.is_forced_moving():
		return Mode.SLIDE
	if not zombie.move_component.is_move or (zombie is Zombie019Pogo and (zombie as Zombie019Pogo).is_pogo):
		return Mode.INACTIVE
	if zombie is Zombie029LargeFusion and (zombie as Zombie029LargeFusion).rolling_attack.is_rolling_on_ground():
		return Mode.ROLL
	return Mode.ROLL if zombie.is_vehicle() else Mode.WALK

## 用 [param zombie] 的实际接地状态和 [param surface] 向 [param footing] 提交接触。
## [param root] 为本帧共用的坡面脚点，停步和冻结仍保留接触表现。
func add_footing(zombie: Zombie000Base, surface: SnowSurface, footing: Footing, root: Vector2) -> void:
	if not _can_touch(zombie) or not _on_lane(zombie, root) or not zombie.body.is_visible_in_tree() \
			or zombie.body.material is ShaderMaterial:
		_pulse = 0.0
		return
	var width: float = maxf(_gait.y * 1.75, _gait.z * 2.3) # 近地形状沿用物种视觉脚型。
	var x: float = root.x + _shadow_offset(zombie) # 原影子横向对齐，不写入原影子。
	var point: Vector2 = surface.ground_point(x, zombie.lane) # 与足影顶点共用的坡面中心。
	var pulse: float = _pulse * (1.0 - smoothstep(3.0, width, point.distance_to(_touch))) if _touch.is_finite() else 0.0 # 只强化仍在鞋边的最近接触。
	var rolling: bool = _mode == Mode.ROLL # 原滚动判定，选择带状接触。
	footing.add_contact(point, zombie.lane, width * (1.35 if rolling else 1.0),
		zombie.modulate.a * zombie.body.modulate.a * lerpf(0.82, 1.0, pulse), pulse, rolling, x == point.x)

## 只读 [param zombie] 的原影子横向对齐量，以世界像素返回。
func _shadow_offset(zombie: Zombie000Base) -> float:
	return clampf(zombie.shadow.global_position.x - zombie.global_position.x, -9.0, 9.0) if is_instance_valid(zombie.shadow) else 0.0

## 监听一个原生 [param trigger]，将 [param callback] 和 [param flags] 保留至退场。
func observe(trigger: Signal, callback: Callable, flags: int = 0) -> void:
	trigger.connect(callback, flags)
	_subscriptions[trigger] = callback

## 同一次退场恢复环境色并断开全部原生信号，抖雪随天气节点回收。
func release() -> void:
	for trigger: Signal in _subscriptions: # 若角色已失效，其原生信号已由引擎清理。
		var callback: Callable = _subscriptions[trigger] # 当前登记绑定的事件回调。
		if is_instance_valid(trigger.get_object()) and trigger.is_connected(callback):
			trigger.disconnect(callback)
	_subscriptions.clear()
	cover.release()
