## 公爵周身的常驻剪切风、余烬和细放电，由花园飞艇的表现时钟推进。
extends Node2D

## 单个深度层的定容三角形批次，前后各建立一个。
const Batch = preload("res://scripts/adventure/garden_airship/sky_duke/sky_duke_storm_batch.gd")
## 原精灵中心在 Boss 根节点中的像素偏移，强度变化不改动角色锚点。
const BODY_CENTER := Vector2(0.0, -105.0)
## 发梢、肩部和两侧衣摆的发射位置，相对于精灵中心。
const EMBER_ORIGINS: Array[Vector2] = [Vector2(36.0, -69.0), Vector2(37.0, -34.0),
	Vector2(51.0, 52.0), Vector2(-32.0, 50.0)]
## 三条气流轨的横半径、纵半径和垂直偏移，使用 Boss 局部像素。
const ORBITS: Array[Vector3] = [Vector3(99.0, 25.0, -49.0), Vector3(118.0, 34.0, -3.0),
	Vector3(93.0, 23.0, 48.0)]
## 以弧度倾斜气流轨，避免轮廓形成同心圆。
const TILTS: Array[float] = [-0.31, 0.17, -0.28]
## 低强度冷色外缘和线芯。
const BLUE_RIM := Color(0.20, 0.48, 0.68)
## 冷色线芯使用接近云面的亮度。
const BLUE_CORE := Color(0.71, 0.90, 1.0)
## 暖色外缘保留暗红，让明亮天空也能呈现细线的轮廓。
const RED_RIM := Color(0.74, 0.065, 0.15)
## 暖色线芯只在狭窄横截面达到峰值。
const RED_CORE := Color(1.0, 0.66, 0.60)
## 不同阶段沿用同一个池；兼容档绘制其中 40 个暖色槽。
const EMBER_COUNT := 54

## 一个余烬槽的稳定参数，出生与消散按外部时钟循环采样。
class Ember:
	## 每轮从同一轮廓邻域放出的 Boss 局部坐标。
	var origin: Vector2
	## 寿命与初始年龄偏移，单位为战斗秒。
	var lifetime: Vector2
	## 横风跟随倍率与局部浮升速度，后者单位为像素每秒。
	var motion: Vector2
	## 粒子大小和亮度的共享比例。
	var weight: float

## 相对于角色画面位于 -1 的轨迹及余烬批次。
var _rear: Batch
## 相对于角色画面位于 +1 的批次，低于本体血条。
var _front: Batch
## 固定余烬槽，仅配置本场局部种子时建立。
var _embers: Array[Ember] = []
## 轨迹和放电的稳定初始相位，无关战斗 RNG。
var _variation := 0.0
## 上次有效战斗秒，负值表示尚未接到首帧。
var _last_seconds := -1.0
## 收拢量、向右的横向推力和抬升量，均用约 -1 到 1 的归一化权重。
var _response := Vector3.ZERO
## 凝聚焦点在技能切换时连续迁移，单位为局部像素。
var _focus := BODY_CENTER
## 只调节密度和线条强度的热度包络，0 为蓝阶段，1 为红阶段。
var _heat := 0.0


## 固定前后批次的实际 Z，让角色精灵遮挡背面弧段。
func _ready() -> void:
	_rear = Batch.new()
	_rear.z_index = -1
	add_child(_rear)
	_front = Batch.new()
	_front.z_index = 1
	add_child(_front)
	if _embers.is_empty():
		configure(0)


## 用 [param seed_value] 生成局部表现槽的参数，可在入树前配置。
func configure(seed_value: int) -> void:
	var random := RandomNumberGenerator.new() # 实例专用序列，和技能抽取相互独立。
	random.seed = seed_value
	_variation = random.randf_range(0.0, TAU)
	_embers.clear()
	for index: int in EMBER_COUNT: # 各发射区域交替分配，减少紧邻槽同相。
		var ember := Ember.new() # 预先分配，绘制时只采样参数。
		var origin: Vector2 = EMBER_ORIGINS[index % EMBER_ORIGINS.size()] # 对应一处轮廓发射点。
		ember.origin = BODY_CENTER + origin + Vector2(random.randf_range(-18.0, 18.0), random.randf_range(-11.0, 11.0))
		ember.lifetime.x = random.randf_range(0.40, 1.0)
		ember.lifetime.y = random.randf() * ember.lifetime.x
		ember.motion = Vector2(random.randf_range(0.65, 1.22), random.randf_range(-27.0, 12.0))
		ember.weight = random.randf_range(0.58, 1.21)
		_embers.append(ember)


## [param seconds] 为连续战斗秒，[param phase] 为真实阶段，[param wind_local] 为本地像素每秒。[br]
## [param action] 为动作名，[param action_age] 为动作经过秒数。[param strength] 控制淡入淡出，
## [param reduced] 使用兼容预算。不推进战斗状态，暂停时可重复提交同一时间。
func update_frame(seconds: float, phase: int, wind_local: Vector2, action: StringName,
		action_age: float, strength: float, reduced: bool) -> void:
	if _rear == null:
		return
	var warm: bool = phase >= 2 # 事件到来即选择当前阶段的色相。
	var target_heat: float = 1.0 if warm else 0.0 # 补入更多气流和余烬从当前轨道相位开始。
	var blend: float = 1.0 if _last_seconds < 0.0 else 1.0 - exp(-17.0 * maxf(0.0, seconds - _last_seconds)) # 按战斗时间吸收流场变化。
	_last_seconds = seconds
	_heat = lerpf(_heat, target_heat, blend)
	_response = _response.lerp(_action_flow(action, action_age), blend)
	var target: Vector2 = BODY_CENTER # 传送和环境气爆向躯干中心收拢。
	if action == &"command":
		target += Vector2(-48.0, -15.0)
	elif action == &"sky_order":
		target += Vector2(-29.0, -68.0)
	_focus = _focus.lerp(target, blend)
	_rear.begin_frame()
	_front.begin_frame()
	var amount: float = clampf(strength, 0.0, 1.0) # 由调度器给出的 Boss 可见包络。
	if amount > 0.005:
		var rim: Color = RED_RIM if warm else BLUE_RIM # 当前阶段的暗色羽边。
		var core: Color = RED_CORE if warm else BLUE_CORE # 当前阶段的细亮线芯。
		_submit_orbits(seconds, amount, reduced, rim, core)
		_submit_embers(seconds, wind_local, amount, reduced, rim, core)
		if warm and not reduced and action == &"idle":
			_front.add_discharge(BODY_CENTER, seconds, _variation, amount * _heat, rim)
	_rear.end_frame()
	_front.end_frame()


## 在 [param seconds] 采样前后轨迹。[param amount] 控制透明度，[param reduced] 限制条数，
## [param rim] 和 [param core] 分别用于窄边和细芯。
func _submit_orbits(seconds: float, amount: float, reduced: bool, rim: Color, core: Color) -> void:
	var count: int = 2 if reduced or _heat < 0.01 else 3 # 冷阶段仅保留两条淡线。
	for index: int in count: # 轨道采用不同高度、弧长、相位与旋转速度。
		var orbit: Vector3 = ORBITS[index] # 横纵半径和纵向锚点。
		var wobble: float = seconds * 2.1 + float(index) * 2.3 + _variation # 扭曲相位随有效时间连续演进。
		var angle: float = seconds * TAU * (1.04 + float(index) * 0.13) + sin(wobble) * 0.25 + _variation + float(index) * 2.6 # 各轨错峰旋转。
		var span: float = lerpf(1.06, 1.44, _heat) + 0.22 * sin(wobble * 0.79) # 不闭合的短弧角域。
		var radii := Vector2(orbit.x * (1.0 - 0.57 * _response.x + 0.21 * absf(_response.y) - 0.30 * _response.z),
			orbit.y * (1.0 - 0.34 * _response.x + 1.03 * _response.z)) # 横扫伸展横轴，指天时抬高气流。
		var center: Vector2 = BODY_CENTER + Vector2(17.0 * _response.y, orbit.z - 24.0 * _response.z) # 收拢前每条轨道的独立锚点。
		center = center.lerp(_focus, _response.x * 0.60)
		var tilt: float = TILTS[index] - 0.53 * _response.z # 向上号令带走原有水平轴。
		var intensity: float = amount * lerpf(0.23, 0.90, _heat) * (1.0 if index < 2 else _heat * 0.83) # 晴日天空前仍读得到赤色外缘。
		var width: float = lerpf(1.18, 3.15, _heat) * (1.0 - 0.25 * _response.x) # 羽边和细芯在实际镜头缩放下独立成形。
		var range_angles := Vector2(angle, span) # 起始角和角域供前后层共用。
		_rear.add_arc(center, radii, tilt, range_angles, wobble, width, Color(rim, intensity * 0.85), Color(core, intensity), false)
		_front.add_arc(center, radii, tilt, range_angles, wobble, width, Color(rim, intensity * 0.89), Color(core, intensity), true)


## 用 [param wind_local] 推进 [param seconds] 的全部可见槽。
## [param amount] 乘到透明度，[param reduced] 限制总数，[param rim]、[param core] 是当前阶段色。
func _submit_embers(seconds: float, wind_local: Vector2, amount: float, reduced: bool,
		rim: Color, core: Color) -> void:
	var cold_count: int = 5 if reduced else 8 # 冷阶段以少量风切呈现。
	var warm_count: int = 40 if reduced else EMBER_COUNT # 兼容档仍有完整下风带。
	var count: int = cold_count if _heat < 0.01 else warm_count # 同一个槽的年龄不会因阶段变化重置。
	var air: Vector2 = wind_local.limit_length(220.0) * lerpf(0.68, 1.06, _heat) + Vector2(_response.y * 235.0, -_response.z * 218.0) # 赤色下风带能飞出衣摆轮廓。
	for index: int in count: # 沿发梢、肩部和下摆交错采样。
		var ember: Ember = _embers[index] # 同一个槽在两个色相下共用起点与速度。
		var age: float = fposmod(seconds + ember.lifetime.y, ember.lifetime.x) # 卡顿可跳过已过期粒子。
		var life: float = age / ember.lifetime.x # 出生为 0，消失为 1。
		var fade: float = smoothstep(0.0, 0.12, life) * (1.0 - smoothstep(0.52, 1.0, life)) # 槽位回绕时两端透明。
		var energy: float = fade * amount * lerpf(0.28, 0.92, _heat) * (1.0 if index < cold_count else _heat) # 平滑建立暖色密度。
		if energy < 0.014:
			continue
		var gust: Vector2 = air * ember.motion.x # 槽位惯性不同，稳定风中也有速度差。
		var rise := Vector2(0.0, ember.motion.y + 11.0 * sin(seconds * 9.1 + float(index))) # 细小竖向扰动，当前为像素每秒。
		var point: Vector2 = ember.origin + age * (gust * (0.26 + 0.64 * life) + rise) # 年龄越大受风路程增长越快。
		var eddy: Vector2 = Vector2.from_angle(seconds * 8.7 + float(index) * 2.4) * Vector2(21.0, 12.0) # 收束时仍有绕焦点的短回旋。
		var inward: Vector2 = _focus + eddy - point # 沿真实聚点反推方向，而非翻转拖尾贴图。
		var velocity: Vector2 = (gust * (0.26 + 1.28 * life) + rise).lerp(inward * 2.9, _response.x * 0.84) # 拖尾沿当前切向延伸。
		point += inward * _response.x * (0.46 + 0.50 * life)
		var length: float = clampf(3.0 + velocity.length() * (0.029 + 0.043 * life), 3.0, 26.0) # 下风加速后更长。
		var radius: float = lerpf(lerpf(1.45, 2.05, _heat), 0.54, life) * ember.weight # 羽化半宽随年龄收细。
		var layer: Batch = _front if index % 5 < 2 else _rear # 大部分余烬从风衣后方脱离。
		layer.add_ember(point, velocity.normalized(), length, radius, Color(rim, energy), Color(core, energy * ember.weight))


## 把 [param action] 的 [param age] 映射到收束量、横向推力、抬升量。
static func _action_flow(action: StringName, age: float) -> Vector3:
	match action:
		&"command":
			return Vector3(0.70 * _window(age, 0.02, 0.35, 0.40, 0.64),
				-0.98 * _window(age, 0.35, 0.44, 0.56, 1.29), 0.0)
		&"sky_order":
			return Vector3(0.46 * _window(age, 0.12, 0.47, 0.55, 0.92), 0.0,
				0.99 * _window(age, 0.16, 0.50, 0.62, 1.51))
		&"teleport_out":
			return Vector3(0.96 * _window(age, 0.16, 1.64, 1.66, 1.97),
				0.53 * _window(age, 1.64, 1.78, 1.85, 2.28), 0.0)
		&"pressure":
			return Vector3(0.88 * _window(age, 0.0, 0.19, 0.22, 0.43),
				0.72 * _window(age, 0.20, 0.28, 0.38, 0.70), 0.0)
		_:
			return Vector3.ZERO


## 在 [param age] 采样从 [param rise] 至 [param peak] 上升、从 [param fall] 到 [param end] 衰减的权重。
static func _window(age: float, rise: float, peak: float, fall: float, end: float) -> float:
	return smoothstep(rise, peak, age) * (1.0 - smoothstep(fall, end, age))
