## 明灯的场景照明。把随动作移动的光源汇入低分辨率照度场，再用它照亮已绘制的场景。
extends CanvasLayer
class_name MingLanternLighting

## 原画与角色共用的受光材质，位置在卡槽和界面之下。
const SURFACE_SHADER: Shader = preload("res://shaders/adventure/wonderland/ming_lantern_scene_light.gdshader")
## 低频照度场每边为主视口尺寸的四分之一。
const FIELD_DIVISOR := 4.0
## 场景内共享一个照明通道，图鉴的独立视口也使用相同名称。
const LAYER_NAME := &"MingLanternLighting"

## 每个光源由它所属的可见节点及绘制回调标识，离树时自动移除。
var _sources: Dictionary[Node2D, Callable] = {}
## 存储线性光强的低分辨率视口。
var _field: SubViewport
## 在照度场中绘制光源衰减，不绘制场景贴图。
var _stamps: Node2D
## 位于照明层之前的场景颜色快照。
var _capture: BackBufferCopy
## 照明合成的场景私有材质。
var _surface: ShaderMaterial
## 普通光源的径向距离衰减。
var _pool_mask: GradientTexture2D
## 扩散震颤的环形距离衰减。
var _ring_mask: GradientTexture2D
## 战斗秒数，供水面焦散缓慢游移。
var _seconds := 0.0

## 返回 [param host] 专属的照明层。战场根节点或图鉴子视口卸载时一并释放。
static func for_host(host: Node) -> MingLanternLighting:
	var lighting := host.get_node_or_null(NodePath(LAYER_NAME)) as MingLanternLighting # 同战场的多个明灯共用一次合成。
	if lighting == null:
		lighting = MingLanternLighting.new()
		lighting.name = LAYER_NAME
		host.add_child(lighting)
	return lighting

## 建立一个低分辨率照度场与一次显式读屏。先照亮战场，再交给后续环境柔光合成。
func _ready() -> void:
	layer = 7 # 前景绘制结束，后续环境柔光在 8，卡槽从 10 开始。
	_field = SubViewport.new()
	_field.name = &"Irradiance"
	_field.disable_3d = true
	_field.gui_disable_input = true
	_field.transparent_bg = true
	add_child(_field)
	_stamps = Node2D.new()
	var additive := CanvasItemMaterial.new() # 光强累加，贴图的透明通道是距离衰减。
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_stamps.material = additive
	_stamps.draw.connect(_draw_emitters)
	_field.add_child(_stamps)
	_pool_mask = _make_mask([0.0, 0.21, 0.51, 0.78, 1.0], [1.0, 0.88, 0.44, 0.12, 0.0])
	_ring_mask = _make_mask([0.0, 0.39, 0.54, 0.72, 0.86, 1.0], [0.0, 0.035, 0.28, 1.0, 0.38, 0.0])
	_capture = BackBufferCopy.new()
	add_child(_capture)
	_surface = ShaderMaterial.new()
	_surface.shader = SURFACE_SHADER
	_surface.set_shader_parameter(&"irradiance", _field.get_texture())
	var rect := ColorRect.new() # 只接收已经绘制的场景颜色，不参与输入。
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = _surface
	add_child(rect)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_viewport().size_changed.connect(_resize_field)
	_resize_field()
	_set_active(false)

## 让 [param source] 在其可见时通过 [param draw_light] 描述本帧光场。回调接收此照明层。
func watch(source: Node2D, draw_light: Callable) -> void:
	if not _sources.has(source):
		source.tree_exiting.connect(_remove_source.bind(source), CONNECT_ONE_SHOT)
	_sources[source] = draw_light
	_set_active(true)

## [param source] 是光源的坐标空间。[param center] 与 [param radius] 为局部像素。
## [param hue] 和 [param intensity] 给出光色与光强，[param ring] 表示沿环边传播。
func cast(source: Node2D, center: Vector2, radius: Vector2, hue: Color, intensity: float, ring: bool = false) -> void:
	if intensity <= 0.002 or radius.x <= 0.0 or radius.y <= 0.0:
		return
	var screen: Rect2 = get_viewport().get_visible_rect() # 光源与读屏 UV 必须基于同一视口。
	var canvas: Transform2D = source.get_global_transform_with_canvas() # 同时应用世界运动、镜头缩放与震动。
	var projected: Vector2 = canvas * center - screen.position # 光心在主视口中的像素位置。
	var span: Vector2 = canvas.basis_xform(Vector2(radius.x, 0.0)).abs() \
		+ canvas.basis_xform(Vector2(0.0, radius.y)).abs() # 横纵椭圆尺寸随镜头缩放。
	var bounds := Rect2(projected - span, span * 2.0) # 此次光源可能覆盖的屏幕矩形。
	if not bounds.intersects(Rect2(Vector2.ZERO, screen.size)):
		return
	var downsample: Vector2 = Vector2(_field.size) / screen.size # 光场在小视口中按相同比例绘制。
	_stamps.draw_texture_rect(_ring_mask if ring else _pool_mask,
		Rect2(bounds.position * downsample, bounds.size * downsample), false, Color(hue, minf(1.0, intensity)))

## [param source] 退场后立即撤销照明。最后一个光源退场后停止读屏。
func _remove_source(source: Node2D) -> void:
	_sources.erase(source)
	if _sources.is_empty():
		_set_active(false)

## [param active] 决定是否绘制照度场和读屏合成。
func _set_active(active: bool) -> void:
	visible = active
	_capture.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT if active else BackBufferCopy.COPY_MODE_DISABLED
	_field.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	set_process(active)
	if active:
		_stamps.queue_redraw()

## 视口变化时就地重新分配照度场，不保留历史帧。
func _resize_field() -> void:
	_field.size = Vector2i(get_viewport().get_visible_rect().size / FIELD_DIVISOR).max(Vector2i(1, 1))
	_project_frame()

## [param delta] 为战斗秒数。暂停时保持水面焦散的当前相位。
func _process(delta: float) -> void:
	_seconds += delta
	_surface.set_shader_parameter(&"clock_seconds", _seconds)
	_project_frame()

## 让焦散锚在当前世界坐标，镜头抖动和视口缩放时与光源同步。
func _project_frame() -> void:
	var screen: Rect2 = get_viewport().get_visible_rect() # 当前缩放后的画布区域。
	var world: Transform2D = get_viewport().get_canvas_transform().affine_inverse() # 从像素坐标反投影到世界。
	_surface.set_shader_parameter(&"world_origin", world * screen.position)
	_surface.set_shader_parameter(&"world_x", world.basis_xform(Vector2(screen.size.x, 0.0)))
	_surface.set_shader_parameter(&"world_y", world.basis_xform(Vector2(0.0, screen.size.y)))
	_stamps.queue_redraw()

## 只绘制当前仍可见的光源。每个回调读取动作节点此帧的实际姿态。
func _draw_emitters() -> void:
	for source: Node2D in _sources: # 本轮只读取源节点和衰减参数。
		if is_instance_valid(source) and not source.is_queued_for_deletion() and source.is_visible_in_tree():
			_sources[source].call(self)

## 从归一化距离 [param stops] 和 [param opacity] 构造共享光强曲线。
func _make_mask(stops: PackedFloat32Array, opacity: Array) -> GradientTexture2D:
	var gradient := Gradient.new() # 白色纹理的 alpha 只记录光强，不包含光源颜色。
	var colors := PackedColorArray() # 每个距离节点对应一个强度。
	for strength: float in opacity: # 由核心到外侧递减或在圆环附近抬升。
		colors.append(Color(1.0, 1.0, 1.0, strength))
	gradient.offsets = stops
	gradient.colors = colors
	gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CUBIC
	var texture := GradientTexture2D.new() # 在小视口中线性采样光强，不需要大图集。
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 96
	texture.height = 96
	return texture
