## 场景内的分层环境合成器：背景折射、低分辨率雾场和选择性柔光。
extends Node
class_name BattleEnvironmentRenderer

## 低分辨率介质场，只计算一次供全屏背景采样。
const FIELD_SHADER = preload("res://shaders/environment/medium_field.gdshader")
## 位于实体之前的背景介质合成。
const MEDIUM_SHADER = preload("res://shaders/environment/background_medium.gdshader")
## 位于实体之后、卡栏之前的亮部合成。
const BLOOM_SHADER = preload("res://shaders/environment/selective_bloom.gdshader")
## 当前背景，用实际画布变换保护近景船体。
var _background: Sprite2D
## 可选的独立天幕，不假设关卡节点名。
var _sky: Sprite2D
## 介质数据视口，四分之一宽高。
var _field: SubViewport
## 三个通道共享的材质实例，均随战斗释放。
var _materials: Array[ShaderMaterial] = []
## 背景、战斗亮部两个明确排序的画布层。
var _layers: Array[CanvasLayer] = []
## 全屏复制与可见层共同启停，不依赖 CanvasLayer 隐藏的隐式行为。
var _copies: Array[BackBufferCopy] = []
var _active := false
var _field_dirty := true
## 已识别的场景照明材质，换图后更新绑定。
var _light_materials: Array[ShaderMaterial] = []
## 最近检查过的原画材质，避免逐帧查询 uniform 列表。
var _seen_materials: Array[Material] = []
## 可选的整屏透镜，挂在窗口末尾以先处理输入，仍由本场景同步回收。
var lens: BattleEnvironmentLens
## 延后安装根画布时所需的本场配置。
var _profile: BattleEnvironmentProfile

## [param profile] 提供渲染参数；[param background] 与 [param sky] 仍由原场景负责纹理和坐标。
func configure(profile: BattleEnvironmentProfile, background: Sprite2D, sky: Sprite2D) -> void:
	_profile = profile
	_background = background
	_sky = sky
	_field = SubViewport.new()
	_field.name = "MediumField"
	_field.disable_3d = true
	_field.transparent_bg = true
	_field.gui_disable_input = true
	_field.render_target_update_mode = SubViewport.UPDATE_DISABLED # 首次有效状态才运行介质场。
	add_child(_field)
	var field_material := ShaderMaterial.new() # 数据纹理专属材质，不读屏幕。
	field_material.shader = FIELD_SHADER
	_materials.append(field_material)
	var field_rect := ColorRect.new() # 一个低分辨率四边形覆盖整个雾场。
	field_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	field_rect.material = field_material
	_field.add_child(field_rect)
	_make_composite(-9, MEDIUM_SHADER, "BackgroundMedium")
	_make_composite(8, BLOOM_SHADER, "SelectiveBloom")
	_materials[1].set_shader_parameter("medium_field", _field.get_texture())
	_materials[1].set_shader_parameter("refraction_pixels", profile.refraction_pixels)
	_materials[1].set_shader_parameter("haze_strength", profile.haze_strength)
	_materials[1].set_shader_parameter("haze_color", profile.haze_color)
	_materials[1].set_shader_parameter("event_color", profile.event_color)
	_materials[2].set_shader_parameter("threshold", profile.bloom_threshold)
	_materials[2].set_shader_parameter("gains", profile.bloom_gains)
	_materials[2].set_shader_parameter("radii", profile.bloom_radii)
	_materials[2].set_shader_parameter("medium_field", _field.get_texture())
	_materials[2].set_shader_parameter("haze_color", profile.haze_color)
	_materials[2].set_shader_parameter("veil_strength", profile.veil_strength)
	_resize_field()
	get_viewport().size_changed.connect(_resize_field)
	if profile.screen_refraction_pixels > 0.0:
		_install_lens.call_deferred()

## 等正式场景入树完成后再追加透镜，避免重开时在父视口装配中修改根节点。
func _install_lens() -> void:
	if is_queued_for_deletion():
		return
	lens = BattleEnvironmentLens.new()
	lens.profile = _profile
	get_tree().root.add_child(lens)

## 在 [param layer_index] 建立显式读屏顺序；[param shader] 与 [param label] 指定本次合成的材质和名称。
func _make_composite(layer_index: int, shader: Shader, label: String) -> void:
	var canvas := CanvasLayer.new() # 非跟随画布，原版选卡镜头保持不变。
	canvas.name = label
	canvas.layer = layer_index
	add_child(canvas)
	_layers.append(canvas)
	var copy := BackBufferCopy.new() # 每次读屏都有自己的完整复制，避免读到其他效果的旧缓存。
	copy.copy_mode = BackBufferCopy.COPY_MODE_DISABLED
	_copies.append(copy)
	canvas.add_child(copy)
	canvas.hide()
	var material := ShaderMaterial.new() # 仅这个场景持有，阶段退出可完全释放。
	material.shader = shader
	_materials.append(material)
	var rect := ColorRect.new() # UI 输入穿透，实际命中区域不受视觉处理影响。
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = material
	canvas.add_child(rect)

## 跟随视口分辨率而非格子数量缩放开销，低分辨率纹理无需保留历史帧。
func _resize_field() -> void:
	_field.size = Vector2i(get_viewport().get_visible_rect().size / 4.0).max(Vector2i(1, 1))
	_field_dirty = true

## [param seconds] 为真实时钟；[param strength] 为阶段权重；[param event] 与 [param shape] 为共享事件状态。
## [param suspended] 冻结雾场计算，但保持最后一帧供暂停界面显示。
## [param afterglow] 是声画事件消退后平缓恢复的视觉适应量，不改变音频或场景亮度基准。
func apply_state(seconds: float, strength: float, event: Vector4, shape: Vector2, suspended: bool, afterglow: float = 0.0) -> void:
	if is_instance_valid(lens):
		lens.apply_state(seconds, strength, event.w)
	var active: bool = strength > 0.0001 # 与实际复合层可见条件完全一致。
	if active and not suspended:
		_field.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_field_dirty = false
	elif active and (_field_dirty or not _active):
		_field.render_target_update_mode = SubViewport.UPDATE_ONCE
		_field_dirty = false
	elif not active or _field.render_target_update_mode != SubViewport.UPDATE_ONCE:
		_field.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_active = active
	_materials[0].set_shader_parameter("clock_seconds", seconds)
	_materials[0].set_shader_parameter("current_event", event)
	_materials[0].set_shader_parameter("event_shape", shape)
	_materials[2].set_shader_parameter("clock_seconds", seconds)
	for index: int in range(2): # 两次全屏合成共用平滑的阶段渐变。
		_layers[index].visible = active
		_copies[index].copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT if active else BackBufferCopy.COPY_MODE_DISABLED
		_materials[index + 1].set_shader_parameter("strength", strength)
		_materials[index + 1].set_shader_parameter("afterglow", afterglow)
	if is_instance_valid(_background) and _background.texture != null:
		var viewport_size: Vector2 = get_viewport().get_visible_rect().size # 与 SCREEN_UV 使用同一视口尺度。
		var rect: Rect2 = _background.get_global_transform_with_canvas() * _background.get_rect() # 原画矩形，不包含右侧虚拟延展。
		var art_rect := Vector4(rect.position.x / viewport_size.x, rect.position.y / viewport_size.y, rect.size.x / viewport_size.x, rect.size.y / viewport_size.y) # 雾场及悬浮物跟随原画变换，避免跟着镜头滑动。
		for material: ShaderMaterial in _materials: # 四分之一介质场与两次合成都使用同一原画空间。
			material.set_shader_parameter("board_rect", art_rect)
	_bind_lights()
	for material: ShaderMaterial in _light_materials: # 天幕和地面照明接收同一环境事件，不再各自持续高亮。
		material.set_shader_parameter("abyss_strength", strength)
		material.set_shader_parameter("ambient_energy", event.w)

## 只绑定主动声明环境接口的材质；普通关卡材质无须跟随此效果改造。
func _bind_lights() -> void:
	for sprite: Sprite2D in [_background, _sky]: # 可选的两张原画各自保留原材质。
		if not is_instance_valid(sprite) or sprite.material == null or _seen_materials.has(sprite.material):
			continue
		_seen_materials.append(sprite.material)
		var material := sprite.material as ShaderMaterial # 非 Shader 材质保持原样。
		if material == null or material.shader == null:
			continue
		for uniform: Dictionary in material.shader.get_shader_uniform_list(): # 仅在换材质时查询一次。
			if uniform.name == "abyss_strength":
				_light_materials.append(material)
				break

## 环境结束后释放对原场景材质的控制，重开和 Boss 不继承参数。
func _exit_tree() -> void:
	if is_instance_valid(lens):
		lens.dispose()
		lens.queue_free()
	for material: ShaderMaterial in _light_materials: # 材质资源可能继续由原场景使用。
		material.set_shader_parameter("abyss_strength", 0.0)
		material.set_shader_parameter("ambient_energy", 0.0)
