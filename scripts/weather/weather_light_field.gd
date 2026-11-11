## 半分辨率环境光场 + 两张四分之一分辨率扩散缓冲，统一输出给雨/雾/湿镜头。
extends Node
class_name WeatherLightField

const FIELD_SHADER = preload("res://shaders/weather/weather_light_field.gdshader")
const BLOOM_SHADER = preload("res://shaders/weather/weather_bloom_blur.gdshader")
const MAX_EMITTERS: int = 8

## 静态关卡光源预设；不包含战斗状态。
var profile: WeatherLightProfile
## 此地图的权威背景 Sprite2D，用其局部纹理 UV 计算实际屏幕光源位置。
var background_sprite: Sprite2D

## GPU 离屏光场与两级 bloom。
var _field_view: SubViewport
var _tight_view: SubViewport
var _wide_view: SubViewport
var _field_material: ShaderMaterial
## 未来卡牌/实体可以通过通用注册 API 接入动态光，不需更改本组件。
var _dynamic: Dictionary = {}
var _clock: float = 0.0
var _strength: float = 0.0


## 三个视口只渲染发光数据，不重新绘制游戏战场。
func _ready() -> void:
    if profile == null or not profile.validate().is_empty():
        set_process(false)
        return
    var full_size: Vector2i = get_viewport().get_visible_rect().size
    _field_view = _create_view(Vector2i(maxi(1, floori(float(full_size.x) / 2.0)), maxi(1, floori(float(full_size.y) / 2.0))))
    _field_material = ShaderMaterial.new()
    _field_material.shader = FIELD_SHADER
    _add_rect(_field_view, _field_material)
    _tight_view = _make_blur_view(full_size, 1.9, 0.04)
    _wide_view = _make_blur_view(full_size, 5.7, 0.018)
    get_viewport().size_changed.connect(_resize_views)
    set_process(true)
    _update_field()


## 建立透明的离屏纹理缓冲。
func _create_view(target_size: Vector2i) -> SubViewport:
    var viewport: SubViewport = SubViewport.new()
    viewport.size = target_size
    viewport.transparent_bg = true
    viewport.disable_3d = true
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    add_child(viewport)
    return viewport


## 在离屏渲染目标内填满一个全屏矩形。
func _add_rect(target: SubViewport, material: ShaderMaterial) -> void:
    var rect: ColorRect = ColorRect.new()
    rect.size = Vector2(target.size)
    rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
    rect.material = material
    target.add_child(rect)


## 根据上游半分辨率光场生成独立的四分之一分辨率模糊。
func _make_blur_view(full_size: Vector2i, radius: float, threshold: float) -> SubViewport:
    var target: SubViewport = _create_view(Vector2i(maxi(1, floori(float(full_size.x) / 4.0)), maxi(1, floori(float(full_size.y) / 4.0))))
    var material: ShaderMaterial = ShaderMaterial.new()
    material.shader = BLOOM_SHADER
    material.set_shader_parameter("light_field", _field_view.get_texture())
    material.set_shader_parameter("sample_pixel", Vector2.ONE / Vector2(_field_view.size))
    material.set_shader_parameter("blur_radius", radius)
    material.set_shader_parameter("threshold", threshold)
    _add_rect(target, material)
    return target


## 屏幕大小变化时重新设置离屏缓冲尺寸和 Shader 光场尺度。
func _resize_views() -> void:
    var full_size: Vector2i = get_viewport().get_visible_rect().size
    _field_view.size = Vector2i(maxi(1, floori(float(full_size.x) / 2.0)), maxi(1, floori(float(full_size.y) / 2.0)))
    for view: SubViewport in [_tight_view, _wide_view]:
        view.size = Vector2i(maxi(1, floori(float(full_size.x) / 4.0)), maxi(1, floori(float(full_size.y) / 4.0)))
        view.get_child(0).size = Vector2(view.size)
        (view.get_child(0).material as ShaderMaterial).set_shader_parameter(
            "sample_pixel", Vector2.ONE / Vector2(_field_view.size))
    _field_view.get_child(0).size = Vector2(_field_view.size)
    _update_field()


## 当前镜头强度影响额外的散射，背景贴图本身仍照常显示。
func set_strength(value: float) -> void:
    _strength = clampf(value, 0.0, 1.0)
    if _field_material != null:
        _field_material.set_shader_parameter("weather_strength", _strength)


## 注册任意运行中发光实体。
## [param emitter] 实体节点，释放后自动失效。
## [param source] 光学描述，位置以实体节点的当前屏幕位置为准。
func register_emitter(emitter: CanvasItem, source: WeatherLightSource) -> void:
    if emitter != null and source != null:
        _dynamic[emitter.get_instance_id()] = {"node": weakref(emitter), "source": source}


## 移除运行实体的环境发光。
func unregister_emitter(emitter: CanvasItem) -> void:
    if emitter != null:
        _dynamic.erase(emitter.get_instance_id())


## 每帧统一计算位置，光源锚点自动跟随背景和镜头转换。
func _process(delta: float) -> void:
    _clock += delta
    _update_field()


## 生成固定长度 GPU uniform 数组，不创建逐光源 Sprite 或粒子。
func _update_field() -> void:
    if _field_material == null:
        return
    var positions: PackedVector4Array = PackedVector4Array()
    var colors: PackedVector4Array = PackedVector4Array()
    var full_size: Vector2 = get_viewport().get_visible_rect().size
    if is_instance_valid(background_sprite) and background_sprite.texture != null:
        var image_size: Vector2 = background_sprite.texture.get_size()
        var world_to_screen: Transform2D = background_sprite.get_global_transform_with_canvas()
        for source: WeatherLightSource in profile.sources:
            if positions.size() >= MAX_EMITTERS:
                break
            var px: Vector2 = world_to_screen * (source.background_uv * image_size)
            _append_source(positions, colors, px / full_size, source)
    for key: int in _dynamic.keys():
        var record: Dictionary = _dynamic[key]
        var emitter: CanvasItem = (record["node"] as WeakRef).get_ref() as CanvasItem
        if not is_instance_valid(emitter):
            _dynamic.erase(key)
            continue
        if positions.size() >= MAX_EMITTERS:
            break
        var px: Vector2 = emitter.get_global_transform_with_canvas().origin
        _append_source(positions, colors, px / full_size, record["source"])
    var active_sources: int = positions.size()
    while positions.size() < MAX_EMITTERS:
        positions.append(Vector4.ZERO)
        colors.append(Vector4.ZERO)
    _field_material.set_shader_parameter("lights", positions)
    _field_material.set_shader_parameter("light_colors", colors)
    _field_material.set_shader_parameter("light_count", active_sources)
    _field_material.set_shader_parameter("full_view_size", full_size)
    _field_material.set_shader_parameter("clock_seconds", _clock)
    _field_material.set_shader_parameter("weather_strength", _strength)


## 将一个发光源的受光半径、颜色及闪烁统一转换成 GPU 参数。
func _append_source(positions: PackedVector4Array, colors: PackedVector4Array, uv: Vector2,
        source: WeatherLightSource) -> void:
    var flicker: float = 1.0 + source.flicker * (
        0.65 * sin(_clock * 11.2 + uv.x * 27.0) +
        0.35 * sin(_clock * 18.7 + uv.y * 16.0))
    positions.append(Vector4(uv.x, uv.y, source.radius_px, source.intensity * flicker))
    colors.append(Vector4(source.color.r, source.color.g, source.color.b, 1.0))


## 最终合成与雨幕共享的光照场。
func get_light_texture() -> Texture2D:
    return _field_view.get_texture() if _field_view != null else null


## 两个独立的散射半径供最终合成使用。
func get_tight_texture() -> Texture2D:
    return _tight_view.get_texture() if _tight_view != null else null


func get_wide_texture() -> Texture2D:
    return _wide_view.get_texture() if _wide_view != null else null
