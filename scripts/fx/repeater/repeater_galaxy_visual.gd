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

## 带有极短能量压缩、穿透放射、成臂残响和最终反向坍缩的四阶段绘制。
func _draw() -> void:
	var remaining: float = _duration - _age # 所有装饰在寿命内结束。
	var fade: float = RepeaterVisualPalette.smooth(remaining / 0.26)
	var quality: int = RepeaterVisualBudget.quality() # 高负载跳过非碰撞星点。
	var splash: float = 1.0 - RepeaterVisualPalette.smooth((_age - 0.035) / 0.24)
	if splash > 0.0:
		_draw_burst(splash)
	var points: PackedVector2Array = positions_at(_age) # 真正伤害和实际可见星星共享几何。
	var stride: int = 1 if quality == RepeaterVisualBudget.FULL else (2 if quality == RepeaterVisualBudget.MEDIUM else 4)
	for i: int in range(0, points.size(), stride):
		var core: Vector4 = _cores[i] # 不同核心半径与闪烁相位固定，不会随机跳点。
		var peak: float = pow(maxf(sin(_age * (6.4 + core.w * 3.2) + core.z), 0.0), 8.0)
		var hue: Color = COLORS[(i * 5 + i / 3) % COLORS.size()]
		var intensity: float = fade * (0.65 + 0.35 * peak)
		var size: float = 1.35 + core.w * 1.5
		draw_circle(points[i], size, Color(hue, intensity))
		draw_circle(points[i], size * 0.40, Color(1.0, 0.97, 1.0, intensity))
		if i % 4 == 0 and peak > 0.10:
			var ray: float = (3.0 + peak * 6.0) * core.w # 瞬时星芒只在少数核出现。
			draw_line(points[i] - Vector2(ray, 0), points[i] + Vector2(ray, 0), Color(hue, peak * fade * 0.70), 0.9, true)
			draw_line(points[i] - Vector2(0, ray), points[i] + Vector2(0, ray), Color(hue, peak * fade * 0.85), 0.9, true)
	_draw_dust(quality, fade)

## 强压缩亮核与定向冲击环让银河先像攻击而不是星云贴图入场。
func _draw_burst(alpha: float) -> void:
	var impulse: float = RepeaterVisualPalette.out_cubic(_age / 0.22) # 爆发圈迅速张开且柔和收尾。
	var radius: float = 6.0 + impulse * 42.0
	draw_circle(Vector2.ZERO, 7.0 * (1.0 - impulse) + 1.0, Color(0.94, 0.97, 1.0, alpha))
	draw_arc(Vector2.ZERO, radius, -PI * 0.43, PI * 0.43, 24, Color(0.76, 0.87, 1.0, alpha * 0.93), 2.3, true)
	draw_arc(Vector2.ZERO, radius * 0.76, PI * 0.59, PI * 1.48, 17, Color(0.60, 0.27, 1.0, alpha * 0.70), 1.6, true)
	for i: int in range(6): # 向前偏转的高速星束，不使用粒子节点。
		var angle: float = (float(i) - 2.5) * 0.38
		var direction: Vector2 = Vector2.from_angle(angle)
		var tip: Vector2 = direction * (12.0 + impulse * (25.0 + float(i % 3) * 7.0))
		draw_line(tip - direction * (10.0 + 15.0 * impulse), tip,
			Color(COLORS[i], alpha * 0.89), 1.4, true)

## 细尘按三种颜色批量绘制，最多108枚并随预算减少到27枚。
func _draw_dust(quality: int, fade: float) -> void:
	var stride: int = 1 if quality == RepeaterVisualBudget.FULL else (2 if quality == RepeaterVisualBudget.MEDIUM else 4)
	for group: int in range(3): # 三次多线段指令取代旧版每粒一次draw_circle。
		var segments := PackedVector2Array()
		for i: int in range(group, DUST_COUNT, 3 * stride):
			var mote: Vector4 = _dust[i] # 这颗星的一次局部解析采样。
			var point: Vector2 = _position(mote, i % 3, _age)
			var blink: float = pow(maxf(sin(_age * (5.0 + mote.w * 4.0) + mote.z), 0.0), 5.0)
			var length: float = 0.45 + mote.w * (0.8 + 1.4 * blink)
			segments.append(point - Vector2(length, 0))
			segments.append(point + Vector2(length, 0))
		if segments.size() >= 2:
			draw_multiline(segments, Color(COLORS[group * 2 + 1], fade * 0.58), 1.0, true)
