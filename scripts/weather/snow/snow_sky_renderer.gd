## 独立极光与可选高云沿游戏时间移动，固定山体由同一世界雪墙逐层遮蔽。
extends Node
class_name SnowSkyRenderer

## 原关卡的天空精灵，保持既有位置、跟随视口和图层顺序。
var _sprite: Sprite2D
## 退出或控制器拆除时恢复静态天幕。
var _original_texture: Texture2D
## 天幕原有材质，可为空。
var _original_material: Material
## 当前场景独占的极光与云材质。
var _material: ShaderMaterial
## 只有提供独立透明高云时才推进云相位。
var _has_storm_clouds := false
## 三个独立的有界相位，分别驱动弯曲、内部流动、亮度。
var _aurora := Vector3.ZERO
## 独立云图的无缝横向位移。
var _cloud: float = 0.0

## 用 [param descent] 移动天空材质的近山散射边界，远山和极光仍处在原画布。
func set_board_descent(descent: float) -> void:
	if _material != null:
		_material.set_shader_parameter(&"snow_ridge_descent", descent)

## 返回当前极光缓慢明灭的亮度，供远景人物的侧光共用。
func light_level() -> float:
	return 0.5 + 0.5 * sin(_aurora.z * TAU) if _material != null else 0.0

## 使用 [param profile] 的分层覆盖 [param sprite]，并由 [param surface] 提供实际雪线，画布须与旧天幕匹配。
func configure(sprite: Sprite2D, profile: SnowVisualProfile, surface: SnowSurface) -> void:
	if not profile.has_aurora_layers() or sprite.texture == null \
			or sprite.texture.get_size() != profile.sky_without_aurora.get_size():
		push_warning("雪山极光需要无极光底图、对齐山体和独立条带，画布须与原天幕一致。")
		return
	_sprite = sprite
	_original_texture = sprite.texture
	_original_material = sprite.material
	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/weather/snow_layered_sky.gdshader") as Shader
	surface.bind_ground_ridge(_material)
	var distant_air: Color = profile.haze_color.lerp(Color(0.85, 0.87, 0.89), 0.62) # 远山散射靠近冷灰白，仍沿用本局风雪颜色。
	_material.set_shader_parameter("snow_air_color", distant_air)
	_material.set_shader_parameter("animate_aurora", true)
	_material.set_shader_parameter("mountains", profile.mountains)
	_material.set_shader_parameter("ribbon", profile.aurora_ribbon)
	var region: Rect2 = profile.aurora_region # 只采样选定条带，图集和独立纹理共享入口。
	_material.set_shader_parameter("ribbon_region", Vector4(region.position.x, region.position.y,
		region.size.x, region.size.y))
	_has_storm_clouds = profile.storm_clouds != null
	if _has_storm_clouds:
		_material.set_shader_parameter("has_storm_clouds", true)
		_material.set_shader_parameter("clouds", profile.storm_clouds)
	sprite.texture = profile.sky_without_aurora
	sprite.material = _material

## 以 [param delta] 游戏秒运行；[param channels] 依次为平滑后的降雪、雪风和云量，[param wind_x] 为世界风速。
## [param visibility_loss] 为归一化能见度损失，[param wall_phase] 为共享雪墙周期，范围 0..1。
## [param high_quality] 决定第二条极光；返回随遮蔽减弱的微量地面环境色。
func advance(delta: float, channels: Vector3, wind_x: float, visibility_loss: float,
		wall_phase: float, high_quality: bool) -> Color:
	if _material == null:
		return Color.TRANSPARENT
	var phase_rates := Vector3(1.0 / 43.0, 1.0 / 11.0, 1.0 / 21.0) # 三种慢速运动各自连续，风力只改变遮蔽和云位移。
	_aurora = (_aurora + phase_rates * delta).posmod(1.0)
	if _has_storm_clouds:
		_cloud = fposmod(_cloud + wind_x * delta / 7500.0, 1.0)
		_material.set_shader_parameter("cloud_phase", _cloud)
	var swell: float = light_level() # 低频明暗起伏同时驱动极光和微弱雪面反馈。
	_material.set_shader_parameter("aurora_phase", Vector2(_aurora.x, _aurora.y))
	_material.set_shader_parameter("aurora_swell", swell)
	_material.set_shader_parameter("visibility_loss", visibility_loss)
	_material.set_shader_parameter("wall_phase", wall_phase)
	_material.set_shader_parameter("cover", channels.z)
	_material.set_shader_parameter("second_ribbon", high_quality)
	var transmission: float = (1.0 - 0.40 * channels.z) * (1.0 - 0.94 * smoothstep(0.13, 0.70, visibility_loss)) # 整体透光用于地面，局部云缝留在天幕。
	var ground_glow: float = 0.055 * lerpf(0.70, 1.0, swell) * transmission # 只保留极弱的雪面环境色。
	return Color(0.59, 0.74, 0.70, ground_glow)

## 控制器独立卸载时，恢复原天空实例。
func _exit_tree() -> void:
	if is_instance_valid(_sprite) and _sprite.material == _material:
		_sprite.material = _original_material
		_sprite.texture = _original_texture
