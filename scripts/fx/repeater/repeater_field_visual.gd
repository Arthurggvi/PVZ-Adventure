## 持续星云和原版黑将军漩涡的纯视觉宿主，时间由战斗层显式提供。
extends Node2D
class_name RepeaterFieldVisual

## 辉夜场固定二十四枚可接触星屑；光晕不参与碰撞。
const FRAGMENT_COUNT: int = 24
## 原画绘制尺寸十八像素，实心星轮廓的外接半径约五像素。
const FRAGMENT_RADIUS: float = 5.0
## 直接复用黑将军传送漩涡，不改动共享帧资源。
const PORTAL_FRAMES: SpriteFrames = preload("res://assets/adventure/zombies/black_general/parts/fx/generated/BlackGeneral_TeleportBlink.tres")
## 持续场的表现种类。
var _kind: StringName
## 当前出生后经过的战斗秒数。
var _age: float = 0.0
## 完整持续时间，衰退包含在此时长内。
var _lifetime: float = 3.0
## 当次棋盘格距；影响范围由战斗层与此表现共用。
var _pitch: Vector2 = Vector2(80.0, 100.0)
## 每枚星的角度、半径比例、相位和闪烁频率。
var _layout: Array[Vector4] = []
## 漩涡以两层相邻原版帧交叉混合，避免逐帧纹理硬跳。
var _portals: Array[Sprite2D] = []
## 纯加色柔光层。
var _glow: Node2D

## 入树后配置 [param kind]、纯视觉 [param seed]、格距 [param pitch] 与秒数 [param lifetime]。
## 本节点不自动计时；调用方通过 [method set_age] 提供同一战斗时间。
func configure(kind: StringName, seed: int, pitch: Vector2, lifetime: float) -> void:
	_kind = kind
	_pitch = Vector2(maxf(absf(pitch.x), 1.0), maxf(absf(pitch.y), 1.0))
	_lifetime = maxf(lifetime, 0.01)
	_layout.clear()
	var rng := RandomNumberGenerator.new() # 本地随机源不消耗战斗抽签。
	rng.seed = seed
	for index: int in range(FRAGMENT_COUNT): # 分层角度和半径让星云均匀而不机械。
		var angle: float = TAU * (float(index) + rng.randf_range(0.08, 0.92)) / float(FRAGMENT_COUNT) # 角扇内抖动。
		_layout.append(Vector4(angle, sqrt(rng.randf_range(0.08, 1.0)), rng.randf() * TAU, rng.randf_range(3.0, 6.0)))
	material = RepeaterVisualPalette.make_material(&"neutral")
	if _glow == null:
		_glow = Node2D.new()
		_glow.material = RepeaterVisualPalette.glow_material()
		_glow.draw.connect(_draw_glow)
		add_child(_glow)
	if _kind == &"hell" and _portals.is_empty():
		for _index: int in range(2): # 相邻帧同时存在，透明度和旋转连续。
			var sprite := Sprite2D.new() # 原帧纹理保持原版漩涡的扭转形状。
			sprite.material = RepeaterVisualPalette.make_material(&"hell", 0, float(seed % 97))
			sprite.z_index = -1
			add_child(sprite)
			_portals.append(sprite)
	set_age(0.0)

## [param seconds] 是出生后累计的战斗秒数；允许视觉录制在任意时间求值。
func set_age(seconds: float) -> void:
	_age = maxf(seconds, 0.0)
	visible = _age < _lifetime
	if _kind == &"hell":
		_update_portal()
	queue_redraw()
	if _glow != null:
		_glow.queue_redraw()

## 返回 [param age] 时真实星屑的局部中心；伤害查询必须使用这些坐标。
func get_fragment_positions_at(age: float) -> PackedVector2Array:
	var points := PackedVector2Array() # 一次查询返回值独立于内部布局。
	if _kind != &"kaguya" or age < 0.0 or age >= _lifetime:
		return points
	var expansion: float = RepeaterVisualPalette.out_cubic(age / 0.62) # 出场放射在0.62秒内柔和减速。
	var sway: float = RepeaterVisualPalette.smooth(age / 0.65) # 进入悬停时侧摆平滑接续。
	for shard: Vector4 in _layout: # 同一解析曲线被绘制和碰撞直接复用。
		var direction: Vector2 = Vector2.from_angle(shard.x) # 每枚星初始方向固定。
		var point: Vector2 = direction * _pitch * Vector2(0.88, 0.75) * shard.y * expansion # 椭圆形近场星云。
		point += direction.orthogonal() * _pitch * 0.045 * (sin(age * 1.15 + shard.z) - sin(shard.z)) * sway
		point.y += (sin(age * 1.8 + shard.z) - sin(shard.z)) * 2.5 * sway
		points.append(point)
	return points

## 返回可接触实心星核的半径；周围光晕只参与表现。
func get_fragment_radius() -> float:
	return FRAGMENT_RADIUS

## 原漩涡先按入场帧展开，中间混合末三帧，最后使用原退场帧缩散。
func _update_portal() -> void:
	if _portals.is_empty():
		return
	var remaining: float = _lifetime - _age # 退场在结束前开始，不额外延长伤害。
	var animation: StringName = &"arrive" # 共享原版帧表，只读不改loop。
	var frame_value: float = minf(_age / 0.52, 1.0) * 11.0 # 入场帧随连续时间推进。
	var next_frame: int = mini(int(frame_value) + 1, 11) # 相邻帧交叉淡化。
	if _age >= 0.52 and remaining > 0.68:
		frame_value = 9.0 + fposmod((_age - 0.52) * 4.2, 3.0)
		next_frame = 9 + (int(frame_value) - 9 + 1) % 3
	elif remaining <= 0.68:
		animation = &"depart"
		frame_value = clampf(1.0 - remaining / 0.68, 0.0, 1.0) * 11.0
		next_frame = mini(int(frame_value) + 1, 11)
	var blend: float = RepeaterVisualPalette.smooth(fposmod(frame_value, 1.0)) # 消除帧边缘抖动。
	var envelope: float = RepeaterVisualPalette.smooth(_age / 0.09) * RepeaterVisualPalette.smooth(remaining / 0.25) # 首尾透明度连续。
	for index: int in range(2): # 两帧共用同一缓慢旋转和呼吸缩放。
		var sprite: Sprite2D = _portals[index] # 当前混合层。
		sprite.texture = PORTAL_FRAMES.get_frame_texture(animation, int(frame_value) if index == 0 else next_frame)
		sprite.rotation = _age * -0.46
		sprite.scale = Vector2.ONE * (0.90 + 0.035 * sin(_age * 2.1))
		sprite.modulate.a = envelope * (1.0 - blend if index == 0 else blend) * 0.95
		(sprite.material as ShaderMaterial).set_shader_parameter(&"effect_seconds", _age)

## 星核保持完整尺寸到消散，光晕渐暗不会扩大真实接触半径。
func _draw() -> void:
	if _kind != &"kaguya":
		return
	var points: PackedVector2Array = get_fragment_positions_at(_age) # 与战斗层完全相同的位置。
	var fade: float = RepeaterVisualPalette.smooth((_lifetime - _age) / 0.55) # 最后半秒逐渐消散。
	for index: int in range(points.size()): # 每星只做集中绘制，无独立节点或Tween。
		var shard: Vector4 = _layout[index] # 固定的闪烁相位。
		var pulse: float = 0.58 + 0.42 * pow(0.5 + 0.5 * sin(_age * shard.w + shard.z), 2.0) # 星核不突然隐没。
		var color: Color = RepeaterVisualPalette.LIGHT_STARS[index % 5] # 五色轮替而不过度饱和。
		color.a = fade * pulse
		draw_set_transform(points[index], shard.z + sin(_age * 0.9 + shard.z) * 0.20)
		draw_texture_rect(RepeaterVisualPalette.STAR_TEXTURE, Rect2(Vector2(-9.0, -9.0), Vector2(18.0, 18.0)), false, color)
	draw_set_transform(Vector2.ZERO)

## 原画星核外只补低强度柔光；漩涡的紫光保持在边缘。
func _draw_glow() -> void:
	var fade: float = RepeaterVisualPalette.smooth((_lifetime - _age) / 0.55) # 只控制表现衰退。
	if _kind == &"hell":
		var portal_alpha: float = fade * RepeaterVisualPalette.smooth(_age / 0.25) # 漩涡轮廓缓慢亮起。
		_glow.draw_texture_rect(RepeaterVisualPalette.halo_texture(), Rect2(Vector2(-75.0, -75.0), Vector2(150.0, 150.0)), false, Color(0.29, 0.06, 0.42, portal_alpha * 0.16))
		return
	var points: PackedVector2Array = get_fragment_positions_at(_age) # 装饰光严格跟随星核。
	for index: int in range(points.size()): # 软光与小芒线不参与战斗接触。
		var shard: Vector4 = _layout[index] # 闪烁不同步，避免整片开关。
		var pulse: float = pow(0.5 + 0.5 * sin(_age * shard.w + shard.z), 4.0) # 偶尔出现轻微亮尖。
		var color: Color = RepeaterVisualPalette.LIGHT_STARS[index % 5] # 对应星核色系。
		color.a = fade * (0.18 + pulse * 0.30)
		_glow.draw_texture_rect(RepeaterVisualPalette.halo_texture(), Rect2(points[index] - Vector2.ONE * 14.0, Vector2.ONE * 28.0), false, color)
		_glow.draw_line(points[index] - Vector2(5.0 + pulse * 4.0, 0.0), points[index] + Vector2(5.0 + pulse * 4.0, 0.0), Color(color, fade * pulse * 0.35), 0.8, true)
