## 只在交战时推进的局内大气事件。姿态只供外界投影，棋盘、船体和摄像机不取这个变换。
extends RefCounted

## 同时只有一种主事件，索具、布料、云、地表与音响共用它的强度。
enum Event { CRUISE, CLOUD_GAP, DOWNDRAFT, CLOUD_EDGE }

## 下降的先兆和风切沿同一有效时钟取样，供风场传播及当前音画强调。
const DROP_LIFT := Vector4(0.0, 0.085, 0.111, 0.23)
## 风切最强时外景正在加速下沉，两端的变化速度连续。
const DROP_SHEAR := Vector4(0.105, 0.16, 0.23, 0.36)
## 约 1.8 秒的稳定俯视窗口，随后一次回正。
const DROP_HOLD := Vector4(0.108, 0.255, 0.535, 0.92)
## 独立头顶云底的浓度，阴影继承其实际位置。
const CEILING_PASS := Vector4(0.025, 0.28, 0.71, 0.98)
## 介绍云隙完整展开后留出的观察时间。
const GAP_REVEAL := Vector4(0.025, 0.29, 0.64, 0.985)

## 当前主事件类型。间隔外保持巡航。
var event_kind: int = Event.CRUISE
## 当前事件内的归一化时间，首末为 0 和 1。
var phase: float = 0.0
## 本次姿态的总秒数，船下云用它估计开口峰值的自然漂移。
var duration_seconds: float:
	get:
		return _duration
## 俯仰弧度、横滚弧度、下沉造成的世界像素位移。俯仰向下为正。
var pose := Vector3.ZERO
## 0 到 1 的共同风压，端点平滑归零。
var pressure: float = 0.0
## 船下真实云缘分开的程度，峰顶留出可观察的地面窗口。
var gap: float = 0.0
## 头顶近云通过时的浓度，云影仍从该云的实际位置投影。
var cloud_pass: float = 0.0
## 虚拟环境镜头额外的垂直视场角，单位为度。
var fov_boost: float = 0.0
## 失重前的抬升压力和开始俯冲时的一小段风切，独立于持续背景风声。
var anticipation: float = 0.0
## 0 到 1 的风切包络，随俯视加速段抬升。
var shear: float = 0.0
## 局部近云在擦过轨道中的位置，0～1；轨道两端外无近身事件云。
var sweep_phase: float = -1.0
## 降低动效时趋近 0，停留画面保留投影和层次。
var motion_amount: float = 1.0

## 每局独占随机源，和敌人生成、战斗随机数无关。
var _random := RandomNumberGenerator.new()
## 下一事件的实际交战秒数。入场/选卡时间不计入。
var _next_start: float
## 保证一轮内先看到云隙，再经历下降和云缘。方向、间隔及强度在允许范围内改变。
var _next_kind: int = Event.CLOUD_GAP
## 最近一次事件的类型，在停止后保留以便从时间直接判相位。
var _current_kind: int = Event.CRUISE
## 最近事件起点，单位为交战秒。
var _started_at: float = 0.0
## 最近事件总时长，单位为秒。
var _duration: float = 1.0
## 横滚偏向，云和飘带的基础气流方向保持一致。
var _bank_sign: float = 1.0
## 每次事件的有界强度变化。
var _strength: float = 1.0
## 本帧交战时刻，可按船身位置延迟采样同一形状。
var _battle_time: float = 0.0

## 每局独立确定第一阵气流的时间，不消耗玩法随机数。
func _init() -> void:
	_random.randomize()
	_next_start = _random.randf_range(6.2, 8.8)

## [param battle_seconds] 为已交战的真实秒数。[param flight_seconds] 还包含准备时间，保持巡航连续。
## [param motion] 为当前显示选项的平滑权重。[param can_begin] 为 false 时只允许现有事件回正。
## 所有曲线首尾速度为零，掉帧直接按有效时刻采样。
func advance(battle_seconds: float, flight_seconds: float, motion: float, can_begin: bool = true) -> void:
	while can_begin and battle_seconds >= _next_start:
		_begin_event()
	_battle_time = battle_seconds
	var age: float = battle_seconds - _started_at # 有效秒数，不受战斗倍速影响。
	event_kind = _current_kind if age < _duration else Event.CRUISE
	phase = clampf(age / _duration, 0.0, 1.0) if event_kind != Event.CRUISE else 0.0
	motion_amount = clampf(motion, 0.0, 1.0)
	_apply_pose(flight_seconds)

## 开启一个事件并预定下一独立间隔。间隔从本次结尾开始计。
func _begin_event() -> void:
	_current_kind = _next_kind
	_started_at = _next_start
	_bank_sign = -1.0 if _random.randf() < 0.5 else 1.0
	_strength = _random.randf_range(0.88, 1.06)
	match _current_kind:
		Event.CLOUD_GAP:
			_duration = _random.randf_range(8.7, 9.6)
			_next_kind = Event.DOWNDRAFT
		Event.DOWNDRAFT:
			_duration = _random.randf_range(6.15, 6.65)
			_next_kind = Event.CLOUD_EDGE
		_:
			_duration = _random.randf_range(8.0, 9.1)
			_next_kind = Event.CLOUD_GAP
	_next_start = _started_at + _duration + _random.randf_range(12.8, 18.4)

## [param seconds] 只影响巡航的低频共同基波。事件使用有平台的平滑包络和稍有延迟的侧向响应。
func _apply_pose(seconds: float) -> void:
	var drift: float = seconds * 0.26 # 巡航时自然而缓慢的风压变化。
	var pitch: float = 1.2 * sin(drift) # 这里保留角度方便美术核对，输出前换算弧度。
	var roll: float = 0.65 * sin(drift - 0.98) # 船身固定，外界地平线沿这个方向倾转。
	var heave: float = 4.3 * sin(drift + 0.6) # 正值模拟下降，云层在画面中向上移动。
	var scale: float = lerpf(0.12, 1.0, motion_amount) # 兼容开关保留轻微视差与静态投影。
	pressure = pressure_at(0.0)
	gap = 0.0
	cloud_pass = 0.0
	fov_boost = 0.0
	anticipation = 0.0
	shear = 0.0
	sweep_phase = -1.0
	match event_kind:
		Event.CLOUD_GAP:
			gap = _shape(phase, GAP_REVEAL)
			pitch += 5.15 * gap * _strength
			roll += _bank_sign * 1.8 * _shape(phase, Vector4(0.10, 0.42, 0.66, 0.98))
			heave += 13.5 * gap
		Event.DOWNDRAFT:
			anticipation = _shape(phase, DROP_LIFT)
			shear = _shape(phase, DROP_SHEAR)
			var drop: float = _shape(phase, DROP_HOLD) # 失重后停留在俯视姿态，再减速回正。
			var rebound: float = _shape(phase, Vector4(0.83, 0.93, 0.95, 1.0)) # 回正末尾只超调一次。
			gap = _shape(phase, Vector4(0.12, 0.262, 0.57, 0.96))
			pitch += (12.95 * drop - 1.50 * anticipation - 0.64 * rebound) * _strength
			roll += _bank_sign * 4.7 * _strength * _shape(phase, Vector4(0.142, 0.294, 0.55, 0.96))
			heave += (48.0 * drop - 7.3 * anticipation - 3.3 * rebound) * _strength
			fov_boost = 5.6 * drop * scale
			sweep_phase = (phase - 0.11) / 0.59
		Event.CLOUD_EDGE:
			cloud_pass = _shape(phase, CEILING_PASS)
			pitch += 2.85 * cloud_pass * _strength
			roll += _bank_sign * 3.4 * _shape(phase, Vector4(0.13, 0.43, 0.64, 0.99))
			heave += 16.0 * cloud_pass
			sweep_phase = (phase - 0.24) / 0.46
	pose = Vector3(deg_to_rad(pitch), deg_to_rad(roll), heave) * scale

## [param delay] 为风压传播和相应物体惯性所需的秒数。所有订阅者在同一事件的曲线上取样。
func pressure_at(delay: float) -> float:
	var time: float = clampf((_battle_time - _started_at - delay) / _duration, 0.0, 1.0) # 保留上一事件收尾的延迟响应。
	match _current_kind:
		Event.CLOUD_GAP:
			return 0.39 * _shape(time, GAP_REVEAL)
		Event.DOWNDRAFT:
			var drive: float = 0.87 * _shape(time, Vector4(0.075, 0.267, 0.59, 0.99)) # 主风压略迟于先兆，回正时留有余风。
			return minf(1.0, _strength * (drive + 0.24 * _shape(time, DROP_LIFT) + 0.31 * _shape(time, DROP_SHEAR)))
		Event.CLOUD_EDGE:
			return 0.89 * _strength * _shape(time, CEILING_PASS)
	return 0.0

## [param at] 为归一化事件时间。[param window] 依次为起始、达到峰值、开始释放与归零的相位。
func _shape(at: float, window: Vector4) -> float:
	return smoothstep(window.x, window.y, at) * (1.0 - smoothstep(window.z, window.w, at))

## [param delay] 是仍可见物体的最大风压迟滞。交战结束时允许这段余风衰减完。
func is_settling(delay: float) -> bool:
	return _current_kind != Event.CRUISE and _battle_time < _started_at + _duration + delay
