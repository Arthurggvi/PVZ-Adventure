## 花园飞艇局内的相对气流。读取现有飞行时间，在船体坐标上提供可复现的风力。
extends RefCounted

## 局内主事件提供同一风压包络和按距离延迟的采样。
const Atmosphere := preload("res://scripts/adventure/garden_airship/garden_airship_atmosphere.gd")

## 母图的布料自由边指向右侧，风和空气层均沿这一方向运动。
const DIRECTION := Vector2.RIGHT
## 阵风沿船身传播的世界像素每秒，与花田的视差速度各自独立。
const PROPAGATION_SPEED: float = 398.0
## 船体中段的取样基准，单位为战场 X 像素。
const REFERENCE_X: float = 700.0
## 两次阵风之间的实际飞行秒数。
const GUST_PERIOD: float = 22.0
## 匀速档沿虚拟世界的航速。此标尺不与战斗速度或屏幕像素直接比较。
const CRUISE_SPEED: float = 720.0
## 入场开始即有航速。环境时钟约四秒内达到巡航档。
const ENTRY_RATIO: float = 0.78
## 推力变化的时间常数，单位为有效飞行秒。
const SPEED_INERTIA: float = 0.86

## 由现有 FlightEnvironment 提交，暂停时无推进。
var seconds: float = 0.0
## 当前虚拟地速的大小，单位为虚拟世界单位每自然秒。
var ship_speed: float = CRUISE_SPEED * ENTRY_RATIO
## 成对方向。舰首向左，船体坐标中的基础气流和视差向右。
var ship_velocity_virtual: Vector2:
	get:
		return -DIRECTION * ship_speed
## 沿船尾方向的虚拟航迹积分，渲染层在各自有效轨道上回绕。
var travel_distance: float = 0.0
## 基础相对空速除以巡航空速。局部阵风另取事件包络。
var airspeed_ratio: float = 0.32 + 0.68 * ENTRY_RATIO
## 0 到 1 的稳定受力近似，按基础空速平方变化。
var cruise_load: float:
	get:
		return minf(0.64 * airspeed_ratio * airspeed_ratio, 1.0)

## 当前局内事件，不使用全局风场。
var _atmosphere: Atmosphere
## 当前近场飞越的横向中心、强度及自然起始秒数。
var _near_gust := Vector3(0.0, 0.0, -100.0)
## 短爆压只从一个近期强源传到附近布与薄云。X 为世界位置、Y 为强度、Z 为自然秒。
var _blast_pulse := Vector3(0.0, 0.0, -100.0)
## 最近取得的有界目标地速，亦用于预测云隙峰值时的自然云位。
var _target_speed: float = CRUISE_SPEED * ENTRY_RATIO

## [param elapsed] 由原飞行时钟提供。[param atmosphere] 保留原事件，还给档位少量瞬时阻力。
func advance(elapsed: float, atmosphere: Atmosphere) -> void:
	var step: float = maxf(0.0, elapsed - seconds) # 不积累暂停或战斗倍速额外时间。
	seconds = elapsed
	_atmosphere = atmosphere
	var entry: float = lerpf(ENTRY_RATIO, 1.0, smoothstep(0.0, 3.8, seconds)) # 入场时一直向前航行。
	var drift: float = 0.056 * sin(seconds * 0.21) + 0.024 * sin(seconds * 0.48 + 0.15) # 同一时钟下缓慢变化，不改变事件调度。
	_target_speed = CRUISE_SPEED * entry * (1.0 + drift - 0.041 * atmosphere.pressure)
	var prior_speed: float = ship_speed # 解析积分用该步首末速度差，避免两次计算同一个指数。
	ship_speed = _target_speed + (ship_speed - _target_speed) * exp(-step / SPEED_INERTIA)
	travel_distance += _target_speed * step + (prior_speed - ship_speed) * SPEED_INERTIA
	airspeed_ratio = 0.32 + 0.68 * ship_speed / CRUISE_SPEED

## 使用当前目标地速与惯性，预测未来 [param ahead_seconds] 额外产生的虚拟航迹。
## 与真实积分共用解析解，预测不改动状态，也不预写未来事件。
func predict_travel(ahead_seconds: float) -> float:
	var span: float = maxf(0.0, ahead_seconds) # 调用者可在云隙峰值之后查询零位移。
	return _target_speed * span + (ship_speed - _target_speed) * SPEED_INERTIA * (1.0 - exp(-span / SPEED_INERTIA))

## 在 [param world_x] 取基准空速倍率，经 [param inertia_seconds] 避让阵风前沿。
## [param gust_gain] 是该表现的局部风响应；已自行分档的残骸可取零以维持原峰值。
func sample_flow_ratio(world_x: float, inertia_seconds: float = 0.0, gust_gain: float = 0.25) -> float:
	return airspeed_ratio * (1.0 + gust_gain * gust_at(world_x, inertia_seconds)
		+ 0.12 * blast_pressure(world_x, inertia_seconds))

## 根据 [param world_x] 处的船身位置，以及物体 [param inertia_seconds] 的响应迟滞，
## 返回 0 到 1 的连续风力。较靠右的位置稍后遇到同一阵风。
func strength_at(world_x: float, inertia_seconds: float = 0.0) -> float:
	var age: float = seconds - (world_x - REFERENCE_X) / PROPAGATION_SPEED - inertia_seconds # 阵风在当前位置的有效时间。
	var phase: float = fposmod(age + 2.0, GUST_PERIOD) # 初相用于错开入场，重开稳定。
	var gust: float = smoothstep(0.0, 1.7, phase) * (1.0 - smoothstep(2.8, 6.1, phase)) # 平滑增强后逐步退回微风。
	var breeze: float = 0.43 + 0.06 * sin(age * 0.56) # 常态低频变化，风向保持稳定。
	var event_pressure: float = _weather_pressure_at(world_x, inertia_seconds) # 复用近云、烟迹和残骸的局部事件相位。
	return clampf(breeze + 0.18 * gust + 0.63 * event_pressure + 0.24 * near_pressure(world_x)
		+ 0.39 * blast_pressure(world_x, inertia_seconds), 0.0, 1.0)

## 取 [param world_x] 处足以显著改变可见拖曳的阵风。带 [param inertia_seconds] 的物体稍晚响应。
func gust_at(world_x: float, inertia_seconds: float = 0.0) -> float:
	var pressure: float = maxf(_weather_pressure_at(world_x, inertia_seconds), near_pressure(world_x, inertia_seconds)) # 同时到达时取较强来源。
	return smoothstep(0.32, 0.86, pressure)

## 取 [param world_x] 的大气事件压力。[param inertia_seconds] 延后表现响应，单位为自然秒。
func _weather_pressure_at(world_x: float, inertia_seconds: float) -> float:
	var delay: float = maxf(0.0, (world_x - 280.0) / PROPAGATION_SPEED + inertia_seconds) # 风从上游向船尾传播。
	return _atmosphere.pressure_at(delay) if _atmosphere != null else 0.0

## 接收真实近身飞越的 [param world_x] 和有界 [param strength]。相邻的弱扰动不重启强包络。
func disturb(world_x: float, strength: float) -> void:
	if strength < near_pressure(world_x) * 0.8:
		return
	_near_gust = Vector3(world_x, clampf(strength, 0.0, 1.0), seconds)

## 在 [param world_x] 登记强度 [param strength] 的局部爆压。近同时爆炸共享短冷却。
func disturb_blast(world_x: float, strength: float) -> void:
	if seconds - _blast_pulse.z >= 0.20:
		_blast_pulse = Vector3(world_x, clampf(strength, 0.0, 0.55), seconds)


## 返回 [param world_x] 周围的局部爆压，按 [param inertia_seconds] 适当延迟。
## 该脉冲只影响布和相对气流采样，庭园航迹与整机死亡拖离仍沿用原曲线。
func blast_pressure(world_x: float, inertia_seconds: float = 0.0) -> float:
	var distance: float = absf(world_x - _blast_pulse.x) # 只到主爆附近的船体和空气。
	var delay: float = distance / 3400.0 + minf(0.06, inertia_seconds * 0.20) # 自然秒内短距离传递。
	var age: float = seconds - _blast_pulse.z - delay # 以飞行时钟计算，不影响战斗时间。
	return _blast_pulse.y * (1.0 - smoothstep(40.0, 246.0, distance)) \
		* smoothstep(0.0, 0.035, age) * (1.0 - smoothstep(0.06, 0.29, age))


## 取 [param world_x] 处的飞越风压。[param inertia_seconds] 为响应迟滞，省略坐标时返回风床包络。
func near_pressure(world_x: float = INF, inertia_seconds: float = 0.0) -> float:
	var age: float = seconds - _near_gust.z - inertia_seconds # 0.08 秒起风、短峰后连续落回。
	var location: float = 1.0 if is_inf(world_x) else 1.0 - smoothstep(60.0, 310.0, absf(world_x - _near_gust.x)) # 扰动范围以可见机位为中心。
	return _near_gust.y * location * smoothstep(0.0, 0.08, age) * (1.0 - smoothstep(0.20, 0.76, age))
