## 可配置的水面渲染器。独立泳池精灵和背景局部水域走同一套 Shader。
## 仅负责视觉；水陆判定与实体交互保持在原有战场管理器。
extends Node2D
class_name WaterSurfaceController

## 统一 Shader，不为不同水域复制实现。
const WATER_SHADER: Shader = preload("res://shaders/water/water_surface.gdshader")
## 每个区域私有的材质，避免不同关卡串值。
var _materials: Array[ShaderMaterial] = []
## 按配置创建的矩形水面节点。
var _regions: Array[ColorRect] = []
## 同一份区域数据生成的水体碰撞形状，提供统一入水/出水事件。
var _water_bodies: Array[WaterBodyArea] = []
## 绑定的原版泳池精灵。
var _source_sprite: Sprite2D
## 受游戏暂停控制的累计时间（秒）。
var _elapsed: float = 0.0
## 水面动态效果倍率，0..1。
var _intensity: float = 1.0
## 当前渲染预设。
var _profile: WaterSurfaceProfile

func _init() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_process(false)

## 将原版泳池等独立精灵接入统一 Shader。
## [param sprite] 有效的源纹理精灵。[param profile] 无需声明 regions。
func configure_sprite(sprite: Sprite2D, profile: WaterSurfaceProfile) -> void:
	_reset()
	if sprite == null or sprite.texture == null or profile == null:
		push_error("水面精灵或预设为空")
		return
	_profile = profile
	_source_sprite = sprite
	sprite.material = _create_material(sprite.texture, Rect2(Vector2.ZERO, Vector2.ONE))
	set_process(true)

## 按底图像素矩形绘制水域，视觉区域不影响地形判定。
## [param source] 已设置最终背景纹理的 Sprite2D。[param profile] 区域及表现参数。
func configure_background(source: Sprite2D, profile: WaterSurfaceProfile) -> void:
	_reset()
	if source == null or source.texture == null or profile == null:
		push_error("水面缺少源背景或预设")
		return
	var source_size: Vector2 = source.texture.get_size() # 背景原图宽高
	var errors: PackedStringArray = profile.validate_regions(source_size) # 区域合法性检查
	if not errors.is_empty():
		push_error("水面区域错误：" + "; ".join(errors))
		return
	_profile = profile
	for region: Rect2 in profile.regions:
		var surface := ColorRect.new() # 一块水域对应一个被矩形裁切的绘制节点
		surface.name = "WaterRegion"
		surface.position = region.position
		surface.size = region.size
		surface.color = Color.WHITE
		surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var atlas_rect := Rect2(region.position / source_size, region.size / source_size) # 源图采样范围
		surface.material = _create_material(source.texture, atlas_rect)
		add_child(surface)
		_regions.append(surface)
		# 物理检测与水面表现必须使用同一矩形，杜绝画面与入水判定脱节。
		var water_body := WaterBodyArea.from_region(region)
		water_body.name = "WaterBody"
		add_child(water_body)
		_water_bodies.append(water_body)
	set_process(not _materials.is_empty())

## 调整整体水面动态强度；[param intensity] 限定在 0..1。
func set_intensity(intensity: float) -> void:
	_intensity = clampf(intensity, 0.0, 1.0)
	if _profile == null:
		return
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter("ripple_strength", _profile.ripple_strength * _intensity)
		material.set_shader_parameter("caustic_strength", _profile.caustic_strength * _intensity)

## 自行累计游戏时间，规避 Shader TIME 在暂停时继续走动的问题。
func _process(delta: float) -> void:
	_elapsed += delta
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter("water_time", _elapsed)

## 构造单块水域的材质，并配置预设参数和源图采样矩形。
## [param texture] 用作像素采样源。[param uv] 归一化的纹理区域。
func _create_material(texture: Texture2D, uv: Rect2) -> ShaderMaterial:
	var material := ShaderMaterial.new() # 私有 ShaderMaterial
	material.shader = WATER_SHADER
	material.set_shader_parameter("surface_texture", texture)
	material.set_shader_parameter("uv_rect", Vector4(uv.position.x, uv.position.y, uv.size.x, uv.size.y))
	material.set_shader_parameter("water_time", _elapsed)
	material.set_shader_parameter("wave_speed", _profile.wave_speed)
	material.set_shader_parameter("ripple_strength", _profile.ripple_strength * _intensity)
	material.set_shader_parameter("wave_density", _profile.wave_density)
	material.set_shader_parameter("caustic_strength", _profile.caustic_strength * _intensity)
	material.set_shader_parameter("water_tint", _profile.water_tint)
	material.set_shader_parameter("tint_mix", _profile.tint_mix)
	material.set_shader_parameter("caustic_tint", _profile.caustic_tint)
	material.set_shader_parameter("opacity", _profile.opacity)
	_materials.append(material)
	return material

## 释放旧视效。既不残留场景节点，也不污染共用材质。
func _reset() -> void:
	set_process(false)
	if is_instance_valid(_source_sprite):
		_source_sprite.material = null
	_source_sprite = null
	for surface: ColorRect in _regions:
		if is_instance_valid(surface):
			remove_child(surface)
			surface.queue_free()
	_regions.clear()
	for body: WaterBodyArea in _water_bodies:
		if is_instance_valid(body):
			remove_child(body)
			body.queue_free()
	_water_bodies.clear()
	_materials.clear()
	_elapsed = 0.0
	_profile = null
