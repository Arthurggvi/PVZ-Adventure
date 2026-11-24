## 根据不同机型从真实爆点发射世界空间产物，火团还可按路径距离卷出有限烟丝。
extends RefCounted

## 固定槽的物质分类和各自寿命。
const Particle := preload("res://scripts/adventure/garden_airship/garden_airship_blast_particle.gd")
## 取样已有气流，在补发烟丝时补上本步已经走过的时间。
const Wind := preload("res://scripts/adventure/garden_airship/garden_airship_wind.gd")
## 各机型的火团、烟、火星和非结构细屑数。运输舰真实十二片在自身模块负责。
const COUNTS: Dictionary[StringName, Vector4i] = {
	&"fighter": Vector4i(7, 7, 13, 2), &"arbiter": Vector4i(8, 9, 16, 4),
	&"transport": Vector4i(10, 10, 18, 2), &"turret": Vector4i(7, 8, 15, 5),
	&"rocket": Vector4i(0, 2, 5, 0), &"contact": Vector4i(0, 3, 9, 0),
}
## 依次给出机型火团全宽比例、竖直喷射偏置和细金属重量比例。
const TUNING: Dictionary[StringName, Vector3] = {
	&"fighter": Vector3(1.0, -0.10, 0.84), &"arbiter": Vector3(1.08, -0.16, 1.04),
	&"transport": Vector3(1.16, -0.08, 1.02), &"turret": Vector3(0.90, 0.23, 1.21),
	&"rocket": Vector3(0.62, 0.10, 0.70), &"contact": Vector3(0.55, -0.12, 1.0),
}

## 从批次取得空闲槽。仅主爆热核可使用保留容量。
var _claim: Callable
## 每次真实事件从给定种子开始的局部随机序列，不改变战斗随机。
var _rng := RandomNumberGenerator.new()

## [param claim] 接收是否为必要主热核，返回固定池中的槽位或 null。
func _init(claim: Callable) -> void:
	_claim = claim

## 辐射起点为 [param origin]，叠入 [param inherited] 世界速度的一部分。
## [param scale] 为机体视觉倍率，[param profile] 为机型类别，[param seed] 只影响该次外观。
## [param primary] 保留首个热核的预算，[param full] 和 [param reduced] 分别为重型预算与兼容档。
## [param factor] 仅用于参考像素速度和加速度的单位换算。
func burst(origin: Vector2, inherited: Vector2, scale: float, profile: StringName, seed: int,
		primary: bool, full: bool, reduced: bool, factor: float) -> void:
	_rng.seed = seed
	var tuning: Vector3 = TUNING.get(profile, TUNING[&"fighter"]) # 现有机体倍率再按机匣特征调整。
	var size: float = clampf(186.0 * scale, 20.0, 230.0) * tuning.x # 基础火团全宽，单位为世界像素。
	var counts: Vector4i = COUNTS.get(profile, COUNTS[&"fighter"]) # 廉价档和次爆引用同一机型密度。
	var density: float = (1.0 if primary else 0.59) * (0.55 if reduced else 1.0) # 主要保留正确爆点和形变。
	if profile != &"rocket":
		_spawn(Particle.Kind.CORE, profile, origin, inherited * 0.59, Vector4(size, 0.123, 0.068, -65.0 * factor), -0.11, _rng.randf(), primary)
		_spawn(Particle.Kind.RAYS, profile, origin, Vector2.ZERO, Vector4(size * 1.53, 0.088, 0.0, 0.0), _rng.randf_range(-0.52, 0.52), _rng.randf())
		if primary:
			_spawn(Particle.Kind.PRESSURE, profile, origin, Vector2.ZERO, Vector4(size * 1.31, 0.133, 0.0, 0.0), 0.69, _rng.randf())
		if primary and full and not reduced:
			_spawn(Particle.Kind.GLOW, profile, origin, Vector2.ZERO, Vector4(size * 2.52, 0.137, 0.0, 0.0), 0.0, _rng.randf())
	var flame_count: int = roundi(counts.x * density) if full else mini(counts.x, 2) # 预算拒绝仍有短热核和分离火舌。
	var smoke_count: int = roundi(counts.y * density) if full else mini(counts.y, 1) # 烟带可以先降低密度。
	var spark_count: int = roundi(counts.z * density) if full else mini(counts.z, 3) # 让廉价爆炸也有清晰瞬态。
	_spray(Particle.Kind.FLAME, flame_count, profile, origin, inherited, size, factor, tuning, primary and full and not reduced)
	_spray(Particle.Kind.SMOKE, smoke_count, profile, origin, inherited, size, factor, tuning)
	_spray(Particle.Kind.SPARK, spark_count, profile, origin, inherited, size, factor, tuning)
	_spray(Particle.Kind.METAL, roundi(counts.w * density) if full else 0, profile, origin, inherited, size, factor, tuning)

## 在真实触地点 [param origin] 发射 [param scale] 倍擦地反馈，初速部分来自 [param inherited]。
## [param seed] 复现散粒，[param factor] 换算速度，[param reduced] 缩减火星数量。不会点燃机体热核。
func contact(origin: Vector2, inherited: Vector2, scale: float, seed: int,
		factor: float, reduced: bool) -> void:
	_rng.seed = seed
	var size: float = clampf(116.0 * scale, 17.0, 105.0) # 地面擦光比同尺寸机体起火更窄。
	_spawn(Particle.Kind.PRESSURE, &"contact", origin, Vector2.ZERO, Vector4(size, 0.094, 0.0, 0.0), 0.25, _rng.randf())
	_spray(Particle.Kind.SMOKE, 2 if reduced else COUNTS[&"contact"].y, &"contact", origin, inherited, size, factor, TUNING[&"contact"])
	_spray(Particle.Kind.SPARK, 5 if reduced else COUNTS[&"contact"].z, &"contact", origin, inherited, size, factor, TUNING[&"contact"])

## 在真实舰壳 [param origin] 用其 [param inherited] 世界速度播出短燃烧尾迹。
## [param scale] 和 [param seed] 控制外形，[param factor] 换算轻微脱落冲量，不另发空爆。
func ember_wake(origin: Vector2, inherited: Vector2, scale: float, seed: int, factor: float) -> void:
	_rng.seed = seed
	var width: float = clampf(scale * 65.0, 13.0, 49.0) # 仅覆盖一块受热碎片附近。
	var smoke_speed: Vector2 = inherited * 0.82 + Vector2(0.0, -89.0 * factor) # 烟从碎片速度平顺释放。
	_spawn(Particle.Kind.SMOKE, &"transport", origin, smoke_speed,
			Vector4(width, 0.48, 0.089, -118.0 * factor), -0.18, _rng.randf())
	for index: int in 2: # 短促的熔渣不会复刻结构爆裂。
		var kick: Vector2 = Vector2(_rng.randf_range(-155.0, 105.0), -62.0 - 73.0 * index) * factor # 以已有飘移为主。
		_spawn(Particle.Kind.SPARK, &"transport", origin, inherited * 0.79 + kick,
				Vector4(width * 0.057, 0.23 + 0.056 * index, 0.049, 250.0 * factor), 0.0, _rng.randf())

## 沿 [param source] 从 [param previous] 到本步末的真实位移插值发烟。
## [param wind] 和 [param factor] 与原火团共用，[param step] 为战斗秒；每步最多补发两团。
func wake(source: Particle, previous: Vector2, wind: Wind, factor: float, step: float) -> void:
	if source.trail_left <= 0 or source.age > 0.26:
		return
	var distance: float = previous.distance_to(source.position) # 同向位移不依赖帧率或名义船速。
	var spacing: float = clampf(source.size * 0.55, 22.0 * factor, 45.0 * factor) # 保持邻团在画面上少量相交。
	var offset: float = spacing - source.trail_carry # 本段第一个应发射的位置。
	var limit: int = mini(source.trail_left, 2) # 卡顿不会一次填满整段烟幕。
	for puff_index: int in limit: # 由路径起点沿实际走过的线段发出，预算不足仍消耗间距。
		if offset > distance or distance <= 0.0:
			break
		var along: float = offset / distance # 本步已经过的路径比例。
		var phase: float = fposmod(source.phase + source.trail_left * 0.376, 1.0) # 不受其他机体触发顺序影响。
		var emission: Vector4 = Vector4(source.size * 0.76, 0.49 + 0.27 * phase, 0.086, -95.0 * factor) # 较窄的局部热尾。
		var smoke: Particle = _spawn(Particle.Kind.SMOKE, source.profile, previous.lerp(source.position, along),
				source.velocity * 0.82, emission, source.angle, phase) # 出生后脱离原火团。
		if smoke != null:
			smoke.advance(wind, factor, step * (1.0 - along))
		source.trail_left -= 1
		offset += spacing
	source.trail_carry = fposmod(source.trail_carry + distance, spacing)

## 从 [param origin] 向不同方向播出 [param count] 个 [param kind] 产物。
## [param inherited] 为锚点初速，[param size] 为爆点全宽，[param factor] 为参考单位换算。
## [param tuning] 和 [param profile] 决定散射形状，[param trails] 只给少数火团短烟预算。
func _spray(kind: Particle.Kind, count: int, profile: StringName, origin: Vector2,
		inherited: Vector2, size: float, factor: float, tuning: Vector3, trails: bool = false) -> void:
	var duration: float = 0.63 if profile == &"rocket" else (0.78 if profile == &"contact" else 1.0) # 擦地余尘和断推短尾较快散尽。
	for index: int in count: # 分散径向方向，避免纯随机恰好全炸向同一侧。
		var angle: float = (index + _rng.randf()) * TAU / count # 以真实爆心为角度原点。
		if profile == &"contact":
			angle = _rng.randf_range(-0.83, 0.13)
		var phase: float = _rng.randf() # 不同相位分别进入捕获和冷却。
		var direction: Vector2 = Vector2.from_angle(angle) + Vector2(0.0, tuning.y) # 舱底、低轮火星与喷烟不具有同一高度。
		var start: Vector2 = origin + direction * (_rng.randf_range(0.014, 0.14) * size) # 团块最初紧邻爆心。
		match kind:
			Particle.Kind.FLAME:
				var width: float = size * lerpf(0.36, 0.79, phase) # 单个热团全宽，单位为世界像素。
				if profile == &"fighter":
					var tier: float = float(index % 3) / 2.0 # 轮流喷出薄火舌和更亮的厚火团。
					width = size * lerpf(0.40, 0.85, tier) * lerpf(0.83, 1.10, phase)
					start = origin + direction * (size * lerpf(0.115, 0.33, phase))
				var velocity: Vector2 = inherited * 0.52 + direction * (_rng.randf_range(410.0, 870.0) * factor) # 先见径向初势。
				var flame: Particle = _spawn(kind, profile, start, velocity, Vector4(width, 0.172 + 0.205 * phase,
						_rng.randf_range(0.025, 0.061), -152.0 * factor), angle, phase) # 不同寿命分离为多个火团。
				if flame != null and trails and index < 2 and count >= 4:
					flame.trail_left = 3
			Particle.Kind.SMOKE:
				var velocity: Vector2 = inherited * 0.47 + direction * (_rng.randf_range(135.0, 450.0) * factor) # 远小于火焰的初始冲量。
				_spawn(kind, profile, start, velocity, Vector4(size * lerpf(0.43, 0.86, phase), (0.56 + 0.58 * phase) * duration,
						_rng.randf_range(0.058, 0.120), -175.0 * factor), angle, phase)
			Particle.Kind.SPARK:
				var velocity: Vector2 = inherited * 0.64 + direction * (_rng.randf_range(470.0, 980.0) * factor) # 爆开后细火星较快捕风。
				_spawn(kind, profile, start, velocity, Vector4(clampf(size * lerpf(0.024, 0.054, phase), 2.0, 8.0),
						(0.25 + 0.35 * phase) * duration, _rng.randf_range(0.030, 0.089), 355.0 * factor), angle, phase)
			Particle.Kind.METAL:
				var velocity: Vector2 = inherited * 0.76 + direction * (_rng.randf_range(320.0, 810.0) * factor) # 工业细片短时保留原方向。
				_spawn(kind, profile, start, velocity, Vector4(clampf(size * lerpf(0.05, 0.12, phase), 4.0, 13.0),
						0.51 + 0.54 * phase, lerpf(0.082, 0.135, phase) * tuning.z, 535.0 * factor), angle, phase)

## 重用一个固定槽。保存 [param kind]、[param profile]、[param start]、[param velocity] 和随机形态。
## [param settings] 依次为世界尺寸、战斗寿命、响应秒数和竖直加速度。
## [param angle] 为初始弧度，压力波例外使用扁率；[param phase] 为随机初相，[param critical] 保留必要反馈。
func _spawn(kind: Particle.Kind, profile: StringName, start: Vector2, velocity: Vector2,
		settings: Vector4, angle: float, phase: float, critical: bool = false) -> Particle:
	var particle: Particle = _claim.call(critical) # 超出预算只省略该产物。
	if particle == null:
		return null
	particle.kind = kind
	particle.profile = profile
	particle.position = start
	particle.velocity = velocity
	particle.age = 0.0
	particle.size = settings.x
	particle.life = settings.y
	particle.tau = settings.z
	particle.gravity = settings.w
	particle.angle = angle
	particle.phase = phase
	particle.born_frame = Engine.get_process_frames()
	particle.trail_left = 0
	particle.trail_carry = 0.0
	return particle
