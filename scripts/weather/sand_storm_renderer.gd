## 分层风沙：远处沙墙在角色后方，贴地流沙与飞砂在前景；生命周期归天气导演所有。
extends Node2D
class_name SandStormRenderer

## 正常游戏帧发布 [param delta] 秒、[param intensity] 沙强度、[param gust] 阵风幅度。
## 离线 [method advance] 不发送此信号，不干预鼠标。
signal wind_advanced(delta: float, intensity: float, gust: float)

## 两个深度层共用的程序材质，无需额外大图或逐帧素材。
const SAND_SHADER: Shader = preload("res://shaders/weather/sand_storm.gdshader")
## 当前场景的独立风沙参数。
var _profile: SandVisualProfile
## 提供真实底图矩形与坐标变换的背景精灵。
var _background: Sprite2D
## 挂在底图上的远景，离开时由本控制器回收。
var _backdrop: ColorRect
## 跟随底图坐标的前景飞砂。
var _foreground: ColorRect
## 两个深度层各自持有材质，禁止修改共享资源。
var _materials: Array[ShaderMaterial] = []
## 当前时间轴的风沙强度，0..1。
var _intensity: float = 0.0
## 随战斗暂停的风场时钟，单位秒。
var _clock: float = 0.0
## 累积风位移，避免阵风改变速度时纹理突然跳动。
var _travel: float = 0.0
## 当前风场的阵风幅度，同时驱动飞砂和指针。
var _gust: float = 0.0


## 在入树前指定 [param background] 的底图坐标和 [param profile] 的视觉参数。
func setup(background: Sprite2D, profile: SandVisualProfile) -> void:
    _background = background
    _profile = profile


## 仅在真实底图存在时构造两个轻量绘制层，不拦截战场鼠标事件。
func _ready() -> void:
    if not is_instance_valid(_background) or _background.texture == null:
        set_process(false)
        return
    _backdrop = _create_layer(0.0)
    _background.add_child(_backdrop)
    _foreground = _create_layer(1.0)
    add_child(_foreground)
    configure(_profile)
    _sync_geometry()
    set_intensity(_intensity)


## 根据 [param depth] 创建远景（0）或前景（1），返回独立绘制矩形。
func _create_layer(depth: float) -> ColorRect:
    var surface := ColorRect.new() # 共享底图尺寸的无交互天气画布。
    surface.name = "SandWall" if depth < 0.5 else "FlyingSand"
    surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var sand_material := ShaderMaterial.new() # 当前深度层独有的材质。
    sand_material.shader = SAND_SHADER
    sand_material.set_shader_parameter("layer_depth", depth)
    surface.material = sand_material
    _materials.append(sand_material)
    return surface


## 更新 [param profile] 的视觉预设；空值使用通用风沙参数，不重置正在滚动的风场。
func configure(profile: SandVisualProfile) -> void:
    _profile = profile if profile != null else SandVisualProfile.new()
    for sand_material: ShaderMaterial in _materials: # 同步两个深度层的公共参数。
        sand_material.set_shader_parameter("shadow_color", _profile.shadow_color)
        sand_material.set_shader_parameter("sunlit_color", _profile.sunlit_color)
        sand_material.set_shader_parameter("wall_opacity", _profile.wall_opacity)
        sand_material.set_shader_parameter("veil_opacity", _profile.veil_opacity)
        sand_material.set_shader_parameter("grain_density", _profile.grain_density)
        sand_material.set_shader_parameter("clear_bounds", Vector4(
            _profile.clear_bounds.position.x, _profile.clear_bounds.position.y,
            _profile.clear_bounds.size.x, _profile.clear_bounds.size.y))


## 应用 [param intensity] 的归一化强度；归零后同时隐藏两层并停止逐帧更新。
func set_intensity(intensity: float) -> void:
    _intensity = clampf(intensity, 0.0, 1.0)
    var active: bool = _intensity > 0.001 and is_instance_valid(_backdrop) # 无底图不启动风场。
    visible = active
    if is_instance_valid(_backdrop):
        _backdrop.visible = active
    set_process(active)
    for sand_material: ShaderMaterial in _materials: # 阶段过渡不重建材质。
        sand_material.set_shader_parameter("intensity", _intensity)


## [param delta] 为受战斗暂停控制的游戏秒数。
func _process(delta: float) -> void:
    advance(delta)
    wind_advanced.emit(delta, _intensity, _gust)


## 战斗与离线制作共用同一推进入口；[param delta] 小于零时不倒转风场。
func advance(delta: float) -> void:
    if _intensity <= 0.001 or _materials.is_empty():
        return
    var seconds: float = maxf(delta, 0.0) # 本次有效游戏增量。
    _clock += seconds
    _gust = pow(maxf(0.0, sin(_clock * 0.49) * 0.72
        + sin(_clock * 0.21 + 1.4) * 0.28), 2.0) * _profile.gust_strength
    _travel += seconds * _profile.wind_speed * (0.6 + _intensity * 0.65 + _gust)
    _sync_geometry()
    for sand_material: ShaderMaterial in _materials: # 由显式游戏时钟驱动，禁止使用 Shader TIME。
        sand_material.set_shader_parameter("clock_seconds", _clock)
        sand_material.set_shader_parameter("wind_travel", _travel)
        sand_material.set_shader_parameter("gust", _gust)


## 从底图矩形映射到前景 CanvasLayer；兼容镜头平移和缩放，不依赖关卡坐标补丁。
func _sync_geometry() -> void:
    if not is_instance_valid(_background):
        return
    transform = (get_parent() as Node2D).get_global_transform_with_canvas().affine_inverse() \
        * _background.get_global_transform_with_canvas()
    var bounds: Rect2 = _background.get_rect() # 包含 centered/offset 的实际纹理矩形。
    for surface: ColorRect in [_backdrop, _foreground]: # 两个空间使用相同底图 UV。
        surface.position = bounds.position
        surface.size = bounds.size
    for sand_material: ShaderMaterial in _materials: # 保持不同分辨率下的砂粒像素尺度。
        sand_material.set_shader_parameter("canvas_size", bounds.size)


## 背景层不是本节点的子节点，独立移除天气导演时也不能留下沙墙。
func _exit_tree() -> void:
    if is_instance_valid(_backdrop):
        _backdrop.queue_free()
