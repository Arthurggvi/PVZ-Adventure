## 辉夜真实星核与星云爆裂的统一轨迹；绘制LOD不改变24枚命中星核或持续秒数。
extends Node2D
class_name RepeaterGalaxyVisual

## 单张共享UV画布，省去旧版每颗星的额外光晕绘制。
const CLOUD_SHADER: Shader = preload("res://shaders/repeater/repeater_galaxy_cloud.gdshader")
## 三旋臂共拥有24枚实际可触碰星核。
const CORE_COUNT: int = 24
## 装饰尘星无碰撞，密度随全场视觉预算自动调整。
const DUST_COUNT: int = 108
## 真实接触半径不会随LOD降级改变。
const TOUCH_RADIUS: float = 5.0
## 银河限定的冷白、冰蓝、靛紫、品红和暖金点缀。
const COLORS: Array[Color] = [
	Color("#f4faff"), Color("#83ccff"), Color("#7598ff"),
	Color("#a586ff"), Color("#e68ccf"), Color("#8df0ef"),
	Color("#ffe9c9"), Color("#c5dfff")
]

## 星核参数依次为半径、旋臂偏角、闪烁相位、尺寸档。
var _cores: Array[Vector4] = []
## 尘星随机轨道参数，不进入实际触碰接口。
var _dust: Array[Vector4] = []
## 当前地形的二维格距，支持非标棋盘。
var _pitch: Vector2
## 全部阶段在三秒内完成，父场控制寿命。
var _duration: float = 3.0
## 可暂停视觉时间，由持续场提供而不是全局TIME。
var _age: float = 0.0
## 共享银河贴片的私有材质，低负载才逐帧更新。
var _cloud: Sprite2D
## 单份材质，内部只做有限的解析极坐标着色。
var _cloud_ink: ShaderMaterial

## 视觉不拥有自己的_process，参数和随机轨道只在出生时创建。
func configure(seed: int, pitch: Vector2, duration: float) -> void:
	_pitch = Vector2(maxf(1.0, absf(pitch.x)), maxf(1.0, absf(pitch.y)))
	_duration = maxf(0.01, duration)
	var rng := RandomNumberGenerator.new() # 视觉抽样与伤害概率完全独立。
	rng.seed = seed
	_cores.clear()
	_dust.clear()
	for i: int in range(CORE_COUNT): # 每条旋臂八核，径向分层且互不重合。
		var ring: float = float(i / 3) / 8.0 # 越往外越稀疏。
		_cores.append(Vector4(0.13 + ring * 0.78 + rng.randf_range(0.0, 0.07),
			rng.randf_range(-0.20, 0.20), rng.randf() * TAU, rng.randf_range(0.55, 1.0)))
	for i: int in range(DUST_COUNT): # 同源旋臂，装饰只存紧凑四浮点。
		_dust.append(Vector4(rng.randf_range(0.06, 0.96), rng.randf_range(-0.41, 0.41),
			rng.randf() * TAU, rng.randf_range(0.35, 1.0)))
	_cloud = Sprite2D.new() # 只有一层GPU云雾，不再为星核逐一画圆形光斑。
	_cloud.texture = RepeaterVisualPalette.halo_texture()
	_cloud.scale = _pitch * 2.0 / _cloud.texture.get_size()
	_cloud.z_index = -1
	_cloud_ink = ShaderMaterial.new()
	_cloud_ink.shader = CLOUD_SHADER
	_cloud.material = _cloud_ink
	add_child(_cloud)
	_cloud_ink.set_shader_parameter(&"lifetime", _duration)
	set_age(0.0)

## [param seconds] 由唯一视觉调度器调用；不自行产生计时回调。
func set_age(seconds: float) -> void:
	_age = clampf(seconds, 0.0, _duration)
	visible = _age < _duration
	_cloud_ink.set_shader_parameter(&"age", _age)
	_cloud_ink.set_shader_parameter(&"quality", RepeaterVisualBudget.quality())
	queue_redraw()

## 单枚星核轨迹：先沿弹道右侧猛烈飞散，再被卷入旋臂，最后向中心坍缩。
func _position(entry: Vector4, arm: int, seconds: float) -> Vector2:
	var radius: float = entry.x # 星核自出生就固定的径向阶。
	var burst: float = RepeaterVisualPalette.out_cubic(seconds / 0.24) # 命中瞬间高初速。
	var burst_angle: float = float(arm) * TAU / 3.0 + entry.y * 0.7 + radius * 0.57
	var ballistic: Vector2 = Vector2.from_angle(burst_angle) * radius * burst * _pitch * 0.96
	ballistic += Vector2(_pitch.x * 0.23 * burst, 0.0) # 主要动势沿豌豆来向向右撕开。
	var wind: float = 0.30 * maxf(0.0, seconds - 0.07)
	var angle: float = float(arm) * TAU / 3.0 + radius * 3.35 + entry.y + wind
	var galaxy: Vector2 = Vector2(cos(angle) * _pitch.x * 0.95, sin(angle) * _pitch.y * 0.78) * radius
	var winding: float = RepeaterVisualPalette.smooth((seconds - 0.14) / 0.52) # 射流向旋臂的连续转向。
	var point: Vector2 = ballistic.lerp(galaxy, winding)
	var collapse: float = RepeaterVisualPalette.smooth((seconds - (_duration - 0.42)) / 0.42)
	return point * (1.0 - collapse) # 退场不是逐渐透明的静态旋转贴图。

## [param seconds] 独立返回全部24枚真正接触核，LOD只会减少可见装饰。
func positions_at(seconds: float) -> PackedVector2Array:
	var result := PackedVector2Array() # 每个60Hz物理步获得独立只读快照。
	if seconds < 0.0 or seconds >= _duration:
		return result
	result.resize(CORE_COUNT)
	for i: int in range(CORE_COUNT):
		result[i] = _position(_cores[i], i % 3, seconds)
	return result

## 银白星核始终绘制全部24枚，预算只影响闪芒、装饰细丝与尘星。
func _draw() -> void:
	var remaining: float = _duration - _age # 所有装饰在战斗寿命内结束。
	var fade: float = RepeaterVisualPalette.smooth(remaining / 0.26) # 尾声柔和收光。
	var quality: int = RepeaterVisualBudget.quality() # 只减少非碰撞装饰。
	var splash: float = 1.0 - RepeaterVisualPalette.smooth(_age / 0.21) # 初始闪光保持紧凑，避免与命中效果叠亮。
	if splash > 0.0:
		_draw_burst(splash)
	if quality != RepeaterVisualBudget.CHEAP:
		_draw_filaments(fade, quality)
	var points: PackedVector2Array = positions_at(_age) # 实际可见星核与真实伤害位置完全一致。
	var sparkle_stride: int = 3 if quality == RepeaterVisualBudget.FULL else 6 # 只减少星芒，星核永不抽样隐藏。
	for i: int in range(points.size()): # 全部24枚核心的冷色晶芒。
		var core: Vector4 = _cores[i] # 出生时固定的轨道与闪烁参数。
		var peak: float = pow(maxf(sin(_age * (4.4 + core.w * 2.4) + core.z), 0.0), 6.0) # 短促闪烁，保留安静间隔。
		var hue: Color = COLORS[(i * 5 + i / 3) % COLORS.size()] # 同一颗星保持稳定色相。
		var intensity: float = fade * (0.76 + peak * 0.24) # 主核始终可辨识。
		var size: float = 1.6 + core.w * 1.25 # 真实半径五像素内的晶体亮心。
		var crystal := PackedVector2Array([points[i] + Vector2(0.0, -size * 1.45), points[i] + Vector2(size, 0.0), points[i] + Vector2(0.0, size * 1.45), points[i] + Vector2(-size, 0.0)]) # 窄菱形比彩色圆点更像恒星。
		draw_colored_polygon(crystal, Color(hue, intensity))
		draw_circle(points[i], 0.75 + core.w * 0.35, Color(0.96, 0.99, 1.0, intensity))
		if i % sparkle_stride == 0:
			var ray: float = (3.6 + peak * 5.5) * core.w # 错相恒星衍射芒。
			draw_line(points[i] - Vector2(ray * 0.72, 0.0), points[i] + Vector2(ray * 0.72, 0.0), Color(hue, fade * (0.20 + peak * 0.50)), 0.8, true)
			draw_line(points[i] - Vector2(0.0, ray), points[i] + Vector2(0.0, ray), Color(hue, fade * (0.30 + peak * 0.56)), 0.8, true)
	_draw_dust(quality, fade)

## [param fade] 控制尾声透明度，[param quality] 决定旋臂细丝的固定采样数。
func _draw_filaments(fade: float, quality: int) -> void:
	var forming: float = RepeaterVisualPalette.smooth((_age - 0.12) / 0.45) # 成形后才出现微弱旋臂脊线。
	var count: int = 26 if quality == RepeaterVisualBudget.FULL else 16 # 单臂固定预算。
	for arm: int in range(3): # 每条曲线直接采样同一轨道公式，保证与碰撞核同臂。
		var segments := PackedVector2Array() # 外臂断续细丝，避免几何完整圆环。
		for index: int in range(count): # 少量短线段模仿电离星云中的纤维。
			var radius: float = lerpf(0.18, 0.82, float(index) / float(count)) # 气体旋臂内外半径。
			if index % 5 == 3:
				continue
			segments.append(_position(Vector4(radius, -0.09, 0.0, 0.0), arm, _age))
			segments.append(_position(Vector4(radius + 0.018, -0.09, 0.0, 0.0), arm, _age))
		if segments.size() >= 2:
			draw_multiline(segments, Color(0.33, 0.69, 0.98, fade * forming * 0.30), 0.8, true)

## [param alpha] 是命中第一拍的剩余亮度；紧凑六向晶芒与正式命中爆发分工。
func _draw_burst(alpha: float) -> void:
	var impulse: float = RepeaterVisualPalette.out_cubic(_age / 0.18) # 短促放射，不画另一层冲击圆。
	var radius: float = lerpf(5.0, 26.0, impulse) # 晶芒限制在半格以内。
	for index: int in range(6): # 六枚细长尖瓣形成星核裂开。
		var heading: Vector2 = Vector2.from_angle(float(index) * TAU / 6.0 + 0.16) # 固定爆发方向。
		var normal: Vector2 = heading.orthogonal() # 细瓣的横向宽度。
		var petal := PackedVector2Array([heading * 2.0, heading * radius * 0.42 + normal * 1.5 * alpha, heading * radius, heading * radius * 0.42 - normal * 1.5 * alpha]) # 尖瓣自然收束。
		draw_colored_polygon(petal, Color(0.57, 0.78, 1.0, alpha * 0.72))
	draw_circle(Vector2.ZERO, lerpf(4.0, 1.0, impulse), Color(0.96, 0.98, 1.0, alpha))

## [param quality] 控制装饰数量，[param fade] 保证尘星与场寿命同步，三批线段保持成本有界。
func _draw_dust(quality: int, fade: float) -> void:
	var stride: int = 1 if quality == RepeaterVisualBudget.FULL else (2 if quality == RepeaterVisualBudget.MEDIUM else 4) # 只抽样无碰撞尘星。
	for group: int in range(3): # 蓝、紫、青三种星尘错开闪烁。
		var segments := PackedVector2Array() # 本色的一次批量提交。
		for i: int in range(group, DUST_COUNT, 3 * stride): # 参数序列与旧版完全相同。
			var mote: Vector4 = _dust[i] # 出生时固定的装饰轨道。
			var point: Vector2 = _position(mote, i % 3, _age) # 尘星沿真实旋臂同向运动。
			var blink: float = pow(maxf(sin(_age * (4.0 + mote.w * 3.0) + mote.z), 0.0), 5.0) # 局部闪亮并非全体呼吸。
			var extent: float = 0.30 + mote.w * (0.35 + blink * 0.70) # 微尘比实际星核细小。
			var direction: Vector2 = Vector2.from_angle(mote.z) # 微尘不再齐整地沿水平排布。
			segments.append(point - direction * extent)
			segments.append(point + direction * extent)
		if segments.size() >= 2:
			draw_multiline(segments, Color(COLORS[group * 2 + 1], fade * 0.66), 1.0, true)
