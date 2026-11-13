## 持续场的纯视觉入口：辉夜委托星系模块，地狱保留原版黑将军传送漩涡。
extends Node2D
class_name RepeaterFieldVisual

## 复用黑将军十二帧传送动画；不修改共享纹理和动画资源。
const PORTAL_FRAMES: SpriteFrames = preload("res://assets/adventure/zombies/black_general/parts/fx/generated/BlackGeneral_TeleportBlink.tres")
## 持续场类型。
var _kind: StringName
## 外部战斗秒时钟的最近可见年龄。
var _age: float = 0.0
## 完整可见寿命。
var _lifetime: float = 3.0
## 当前战场的实际地形格距。
var _pitch: Vector2 = Vector2(80.0, 100.0)
## 辉夜星系拥有全部接触星核与装饰星云的唯一几何来源。
var _galaxy: RepeaterGalaxyVisual
## 原漩涡连续帧混合的两层纹理。
var _portals: Array[Sprite2D] = []
## 原漩涡的低亮度边缘光，与银河分层无关。
var _glow: Node2D

## [param seed] 为纯视觉局部随机种子；该入口只建立一种场表现。
func configure(kind: StringName, seed: int, pitch: Vector2, lifetime: float) -> void:
	_kind = kind
	_pitch = Vector2(maxf(absf(pitch.x), 1.0), maxf(absf(pitch.y), 1.0))
	_lifetime = maxf(lifetime, 0.01)
	if _kind == &"kaguya":
		_galaxy = RepeaterGalaxyVisual.new()
		add_child(_galaxy)
		_galaxy.configure(seed, _pitch, _lifetime)
	elif _kind == &"hell":
		material = RepeaterVisualPalette.make_material(&"neutral")
		_glow = Node2D.new()
		_glow.material = RepeaterVisualPalette.glow_material()
		_glow.draw.connect(_draw_glow)
		add_child(_glow)
		for _index: int in range(2):
			var sprite := Sprite2D.new()
			sprite.material = RepeaterVisualPalette.make_material(&"hell", 0, float(seed % 97))
			sprite.z_index = -1
			add_child(sprite)
			_portals.append(sprite)
	set_age(0.0)

## 视觉时间由战斗层提供，单帧可重复求值，不对外写战斗状态。
func set_age(seconds: float) -> void:
	_age = maxf(seconds, 0.0)
	visible = _age < _lifetime
	if is_instance_valid(_galaxy):
		_galaxy.set_age(_age)
	if _kind == &"hell":
		_update_portal()
		if is_instance_valid(_glow):
			_glow.queue_redraw()

## 直接返回真正绘制的24枚星核中心，不从装饰云雾猜测碰撞。
func get_fragment_positions_at(seconds: float) -> PackedVector2Array:
	if not is_instance_valid(_galaxy):
		return PackedVector2Array()
	return _galaxy.positions_at(seconds)

## 星核触碰半径不包含星云和衍射光，保持原有战斗数值。
func get_fragment_radius() -> float:
	return RepeaterGalaxyVisual.TOUCH_RADIUS

## 原漩涡先播放入场帧，中段流畅循环，结束前播放退场帧。
func _update_portal() -> void:
	if _portals.is_empty():
		return
	var remaining: float = _lifetime - _age
	var animation: StringName = &"arrive"
	var frame_value: float = minf(_age / 0.52, 1.0) * 11.0
	var next_frame: int = mini(int(frame_value) + 1, 11)
	if _age >= 0.52 and remaining > 0.68:
		frame_value = 9.0 + fposmod((_age - 0.52) * 4.2, 3.0)
		next_frame = 9 + (int(frame_value) - 9 + 1) % 3
	elif remaining <= 0.68:
		animation = &"depart"
		frame_value = clampf(1.0 - remaining / 0.68, 0.0, 1.0) * 11.0
		next_frame = mini(int(frame_value) + 1, 11)
	var blend: float = RepeaterVisualPalette.smooth(fposmod(frame_value, 1.0))
	var envelope: float = RepeaterVisualPalette.smooth(_age / 0.09) * RepeaterVisualPalette.smooth(remaining / 0.25)
	for index: int in range(2):
		var sprite: Sprite2D = _portals[index]
		sprite.texture = PORTAL_FRAMES.get_frame_texture(animation, int(frame_value) if index == 0 else next_frame)
		sprite.rotation = _age * -0.46
		sprite.scale = Vector2.ONE * (0.90 + 0.035 * sin(_age * 2.1))
		sprite.modulate.a = envelope * (1.0 - blend if index == 0 else blend) * 0.95
		(sprite.material as ShaderMaterial).set_shader_parameter(&"effect_seconds", _age)

## 地狱漩涡只添加原有的微弱紫色柔光，不混用辉夜新特效。
func _draw_glow() -> void:
	var fade: float = RepeaterVisualPalette.smooth((_lifetime - _age) / 0.55)
	var alpha: float = fade * RepeaterVisualPalette.smooth(_age / 0.25)
	_glow.draw_texture_rect(RepeaterVisualPalette.halo_texture(), Rect2(-75.0, -75.0, 150.0, 150.0), false,
		Color(0.29, 0.06, 0.42, alpha * 0.16))
