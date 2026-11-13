## 辉夜星系的可视星核、螺旋轨迹和装饰星尘；战斗层仅读取二十四个星核坐标。
extends Node2D
class_name RepeaterGalaxyVisual

## 与实体旋臂共享局部UV的近场星云气体；渲染器只需要一张程序化贴片。
const CLOUD_SHADER: Shader = preload("res://shaders/repeater/repeater_galaxy_cloud.gdshader")
## 三条非对称螺旋臂，二十四个真正可触碰星核。
const ARM_COUNT: int = 3
const PRIMARY_COUNT: int = 24
## 装饰细星无碰撞，不改变60Hz伤害和星核数量。
const DUST_COUNT: int = 168
## 星核物理接触半径和美术光晕半径分离。
const TOUCH_RADIUS: float = 5.0
## 同一银河的白蓝、丁香紫、冰青和一点暖金。
const STAR_HUES: Array[Color] = [
	Color("#eef8ff"), Color("#a1d9ff"), Color("#88a6ff"),
	Color("#b392ff"), Color("#efabf4"), Color("#8eeefa"),
	Color("#ffd4e7"), Color("#d5f2ff")
]

## 主星布局：径向位置、微偏角、闪烁相位、视觉比例。
var _primary: Array[Vector4] = []
## 细星布局：径向位置、偏角、闪烁相位、深度。
var _dust: Array[Vector4] = []
## 当次格距来自真实战场，星臂始终在邻近3×3范围内。
var _pitch: Vector2 = Vector2(80.0, 100.0)
## 随伤害场一起计时和回收的可见寿命。
var _lifetime: float = 3.0
## 外部战斗时钟给出的可见年龄。
var _age: float = 0.0
## 一张局部云雾画布，在星核和星尘后面绘制实际的空间深度。
var _cloud: Sprite2D
## 云雾拥有私有时间和色彩，不读取Shader全局TIME。
var _cloud_ink: ShaderMaterial
## 单独加色层承载旋臂及星晕，不修改物理碰撞。
var _light: Node2D

## 以局部随机种子生成一次静态轨道；不同星场视觉布局独立，不消耗战斗随机数。
func configure(seed: int, pitch: Vector2, lifetime: float) -> void:
	_pitch = Vector2(maxf(absf(pitch.x), 1.0), maxf(absf(pitch.y), 1.0))
	_lifetime = maxf(lifetime, 0.01)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	_primary.clear()
	_dust.clear()
	for index: int in range(PRIMARY_COUNT):
		var rank: int = int(float(index) / float(ARM_COUNT))
		var radial: float = 0.12 + (float(rank) + rng.randf_range(0.10, 0.94)) * 0.105
		_primary.append(Vector4(radial, rng.randf_range(-0.19, 0.19), rng.randf() * TAU, rng.randf_range(0.72, 1.18)))
	for index: int in range(DUST_COUNT):
		var radial: float = 0.07 + pow(rng.randf(), 0.74) * 0.92
		_dust.append(Vector4(radial, rng.randf_range(-0.42, 0.42), rng.randf() * TAU, rng.randf_range(0.45, 1.0)))
	if _cloud == null:
		_cloud = Sprite2D.new() # 使用共享梯度纹理作为矩形UV载体，不生成新的复杂图片。
		_cloud.texture = RepeaterVisualPalette.halo_texture()
		_cloud.z_index = -2
		_cloud_ink = ShaderMaterial.new()
		_cloud_ink.shader = CLOUD_SHADER
		_cloud.material = _cloud_ink
		add_child(_cloud)
	_cloud.scale = _pitch * 2.0 / _cloud.texture.get_size()
	_cloud_ink.set_shader_parameter(&"lifetime", _lifetime)
	if _light == null:
		_light = Node2D.new()
		_light.z_index = -1
		_light.material = RepeaterVisualPalette.glow_material()
		_light.draw.connect(_draw_light)
		add_child(_light)
	set_age(0.0)

## 由战斗层提供时间；没有额外Tween、Timer、全局TIME或碰撞。
func set_age(seconds: float) -> void:
	_age = maxf(seconds, 0.0)
	visible = _age < _lifetime
	if is_instance_valid(_cloud_ink):
		_cloud_ink.set_shader_parameter(&"age", _age)
	queue_redraw()
	if is_instance_valid(_light):
		_light.queue_redraw()

## 所有实际命中的星核与绘制共享同一条旋臂轨迹。
func positions_at(seconds: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	if seconds < 0.0 or seconds >= _lifetime:
		return points
	for index: int in range(_primary.size()):
		var star: Vector4 = _primary[index]
		points.append(_orbit(star.x, index % ARM_COUNT, star.y, seconds))
	return points

## 星臂先快速释放，再缓慢自转；最大半径受当地格距严格约束。
func _orbit(radius: float, arm: int, offset: float, seconds: float) -> Vector2:
	var expansion: float = RepeaterVisualPalette.out_cubic(seconds / (0.46 + radius * 0.34)) # 外缘更晚展开，内核率先绽放。
	var rotation: float = 0.31 * maxf(0.0, seconds - 0.10) * (0.46 + radius * 0.54)
	var uncoil: float = -(1.0 - expansion) * 1.25 # 起飞时先卷紧，随后沿旋臂松开。
	var angle: float = float(arm) * TAU / float(ARM_COUNT) + radius * 2.95 + offset + rotation + uncoil
	return Vector2(cos(angle) * _pitch.x * 0.94, sin(angle) * _pitch.y * 0.78) * radius * expansion

## 全星系统一淡入、淡出；个别星星的闪烁只影响亮度而不影响位置。
func _envelope() -> float:
	return RepeaterVisualPalette.smooth(_age / 0.15) * RepeaterVisualPalette.smooth((_lifetime - _age) / 0.56)

## 粒子不使用随机帧位移；与星臂同向旋动，形成疏密与运动透视。
func _draw() -> void:
	var fade: float = _envelope()
	for index: int in range(_dust.size()):
		var mote: Vector4 = _dust[index]
		var point: Vector2 = _orbit(mote.x, index % ARM_COUNT, mote.y, _age)
		var shimmer: float = 0.56 + 0.44 * sin(_age * (1.8 + mote.w) + mote.z + mote.x * 4.0)
		var hue: Color = STAR_HUES[(index * 5 + index / 7) % STAR_HUES.size()]
		var radius: float = 0.50 + 1.22 * mote.w
		draw_circle(point, radius, Color(hue, fade * shimmer * (0.35 + mote.w * 0.45)))
		if index % 13 == 0:
			draw_line(point - Vector2(3.0, 0.0), point + Vector2(3.0, 0.0), Color(hue, fade * shimmer * 0.45), 0.7, true)
	var points: PackedVector2Array = positions_at(_age)
	var previous: PackedVector2Array = positions_at(maxf(0.0, _age - 0.075)) # 飞散初段的真实旧轨迹，而非凭空随机划线。
	for index: int in range(points.size()):
		var star: Vector4 = _primary[index]
		var shimmer: float = 0.73 + 0.27 * sin(_age * (2.4 + star.w) + star.z)
		var hue: Color = STAR_HUES[(index * 5 + index / 3) % STAR_HUES.size()]
		if index < previous.size() and _age < 0.90:
			draw_line(previous[index], points[index], Color(hue, fade * (1.0 - _age / 0.90) * 0.68), 1.3, true) # 弧形星迹随减速而自然缩短。
		var core_radius: float = 1.2 + star.w * 1.65 # 不再把原版绿色五角星当作恒星；用小白点和衍射芒表达真实星海。
		draw_circle(points[index], core_radius, Color(hue, fade * shimmer * 0.86))
		draw_circle(points[index], maxf(0.75, core_radius * 0.45), Color(1.0, 0.97, 1.0, fade * (0.84 + shimmer * 0.16)))
		if index % 3 == 0:
			_draw_glint(points[index], hue, fade * shimmer, 5.0 + 4.0 * star.w)

## 在少数明亮星旁绘制长短不等的衍射芒，而非所有星同步闪烁。
func _draw_glint(point: Vector2, hue: Color, alpha: float, size: float) -> void:
	var flare: float = 0.35 + 0.65 * pow(0.5 + 0.5 * sin(_age * 3.4 + point.x * 0.13), 4.0)
	draw_line(point - Vector2(size, 0.0), point + Vector2(size, 0.0), Color(hue, alpha * flare * 0.68), 0.8, true)
	draw_line(point - Vector2(0.0, size * 1.35), point + Vector2(0.0, size * 1.35), Color(hue, alpha * flare * 0.76), 0.8, true)
	draw_circle(point, 1.55, Color("#ffffff", alpha * flare))

## 多层加色星云：旋臂色带、雾状气团和星核微光，均不参与碰撞。
func _draw_light() -> void:
	var fade: float = _envelope()
	var halo: Texture2D = RepeaterVisualPalette.halo_texture()
	_light.draw_texture_rect(halo, Rect2(-69.0, -52.0, 138.0, 104.0), false, Color(0.22, 0.23, 0.94, fade * 0.36)) # 星盘外圈的深蓝电离气体。
	_light.draw_texture_rect(halo, Rect2(-35.0, -30.0, 70.0, 60.0), false, Color(0.68, 0.35, 1.0, fade * 0.50)) # 紫粉色内核雾。
	_light.draw_texture_rect(halo, Rect2(-17.0, -15.0, 34.0, 30.0), false, Color(0.94, 0.90, 1.0, fade * 0.75)) # 集中而不刺眼的银白核心。
	for arm: int in range(ARM_COUNT):
		var points := PackedVector2Array()
		var colors := PackedColorArray()
		var soft_colors := PackedColorArray()
		for step: int in range(25):
			var radial: float = 0.055 + float(step) / 24.0 * 0.93
			var point: Vector2 = _orbit(radial, arm, 0.0, _age)
			var hue: Color = STAR_HUES[(arm * 2 + int(radial * 5.0)) % STAR_HUES.size()]
			var intensity: float = sin(PI * radial) * fade
			points.append(point)
			colors.append(Color(hue, 0.13 * intensity))
			soft_colors.append(Color(hue, 0.055 * intensity))
			if step % 5 == 2:
				var cloud_size: float = 18.0 + 22.0 * radial
				_light.draw_texture_rect(halo, Rect2(point - Vector2.ONE * cloud_size, Vector2.ONE * 2.0 * cloud_size), false,
					Color(hue, fade * (0.12 + 0.10 * sin(_age * 1.5 + radial * 4.0))))
		_light.draw_polyline_colors(points, soft_colors, 12.0, true)
		_light.draw_polyline_colors(points, colors, 1.6, true)
	var anchors: PackedVector2Array = positions_at(_age)
	for index: int in range(anchors.size()):
		var hue: Color = STAR_HUES[(index * 5 + index / 3) % STAR_HUES.size()]
		var phase: float = _primary[index].z
		var gleam: float = 0.60 + 0.40 * sin(_age * 3.3 + phase)
		var spread: float = 14.0 + _primary[index].w * 10.0
		_light.draw_texture_rect(halo, Rect2(anchors[index] - Vector2.ONE * spread, Vector2.ONE * 2.0 * spread), false,
			Color(hue, fade * gleam * 0.36))
