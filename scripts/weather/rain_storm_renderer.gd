## 三层雨幕、地面水花与阵风的唯一渲染控制器；不关心关卡编号或波次。
extends Control
class_name RainStormRenderer

## 各个雨景共用的可选参数预设。
@export var profile: RainVisualProfile
## 模拟参数可独立变更，实际降雨强度由天气导演统一下发。
@onready var dim_overlay: ColorRect = $Dim
@onready var cloud_overlay: ColorRect = $StormClouds
@onready var far_rain: ColorRect = $FarRain
@onready var middle_rain: ColorRect = $MiddleRain
@onready var splashes: ColorRect = $Splashes
@onready var near_rain: ColorRect = $NearRain

## 每场景独有的 ShaderMaterial，避免场景复用引起 uniform 串联。
var _materials: Array[ShaderMaterial] = []
## 月光与天空上缘的流动云层使用另一份独立材质。
var _cloud_material: ShaderMaterial
## 连续阵风时间场，仅计算当前战场的动态风。
var _wind: RainWindField = RainWindField.new()
## 模拟时钟，战斗暂停自动停止。
var _clock: float = 0.0
## 导演传入的最终降雨强度。
var _intensity: float = 0.0


## 克隆材质，并使可配置层级与阶段过渡分离。
func _ready() -> void:
    for canvas: ColorRect in [far_rain, middle_rain, splashes, near_rain]:
        var material_copy: ShaderMaterial = canvas.material.duplicate() as ShaderMaterial
        canvas.material = material_copy
        _materials.append(material_copy)
    _cloud_material = cloud_overlay.material.duplicate() as ShaderMaterial
    cloud_overlay.material = _cloud_material
    configure(profile)
    set_intensity(_intensity)


## 设置通用雨天表现预设，null 退回普通中雨预设。
## [param next_profile] 可复用的雨视觉参数。
func configure(next_profile: RainVisualProfile) -> void:
    profile = next_profile if next_profile != null else RainVisualProfile.new()
    if not is_node_ready():
        return
    _set_layer(0, profile.far_density, profile.far_opacity, 500.0, 28.0, 0.8, 13.0, 95.0, 0.11)
    _set_layer(1, profile.middle_density, profile.middle_opacity, 920.0, 43.0, 1.25, 17.0, 120.0, 0.15)
    _set_layer(3, profile.near_density, profile.near_opacity, 1660.0, 88.0, 2.2, 25.0, 195.0, 0.22)
    for index: int in [0, 1, 3]:
        _materials[index].set_shader_parameter("rain_color", profile.rain_color)
    _materials[2].set_shader_parameter("ground_bounds", Vector4(
        profile.ground_bounds.position.x, profile.ground_bounds.position.y,
        profile.ground_bounds.size.x, profile.ground_bounds.size.y))
    _materials[2].set_shader_parameter("splash_strength", profile.splash_strength)
    _cloud_material.set_shader_parameter("shade", profile.storm_dim * 1.4)
    set_intensity(_intensity)


## 固定层配置，由资源控制密度、透明度，层级参数只在此定义。
func _set_layer(index: int, density: float, opacity: float, speed: float,
        length_px: float, width_px: float, column_px: float, row_px: float,
        slant: float) -> void:
    var material: ShaderMaterial = _materials[index]
    material.set_shader_parameter("density", density)
    material.set_shader_parameter("layer_opacity", opacity)
    material.set_shader_parameter("rain_speed", speed * profile.speed)
    material.set_shader_parameter("streak_length", length_px)
    material.set_shader_parameter("streak_width", width_px)
    material.set_shader_parameter("cell_width", column_px)
    material.set_shader_parameter("cell_height", row_px)
    material.set_shader_parameter("slant", slant)
    material.set_shader_parameter("canvas_size", size)


## 修改阶段雨势；不重建粒子系统，也不改其它天气层。
## [param intensity] 0 晴天，1 是当前预设的完整雨势。
func set_intensity(intensity: float) -> void:
    _intensity = clampf(intensity, 0.0, 1.0)
    if not is_node_ready():
        return
    visible = _intensity > 0.001
    set_process(visible)
    _cloud_material.set_shader_parameter("intensity", _intensity)
    dim_overlay.color = Color(0.06, 0.09, 0.17,
        profile.storm_dim * pow(_intensity, 1.35))
    for material: ShaderMaterial in _materials:
        material.set_shader_parameter("intensity", _intensity)


## 正式关卡每帧更新风向和雨帘密度。
func _process(delta: float) -> void:
    advance(delta)


## 供离线预览和战斗共用的确定性风场推进接口。
## [param delta] 天气逻辑增量（秒）。
func advance(delta: float) -> void:
    if _intensity <= 0.001 or not is_node_ready():
        return
    _clock += maxf(0.0, delta)
    var wind_sample: Vector2 = _wind.sample(_clock, profile.gust_strength)
    for index: int in [0, 1, 3]:
        _materials[index].set_shader_parameter("clock_seconds", _clock)
        _materials[index].set_shader_parameter("gust", wind_sample.x)
        _materials[index].set_shader_parameter("wind_density", wind_sample.y)
    _materials[2].set_shader_parameter("clock_seconds", _clock)
    _materials[2].set_shader_parameter("wind", wind_sample.x)
    _cloud_material.set_shader_parameter("clock_seconds", _clock)
    _cloud_material.set_shader_parameter("gust", wind_sample.x)


## 视口或雨场景大小改变时，保持雨线实际像素尺度一致。
func refresh_canvas_size() -> void:
    if _materials.is_empty():
        return
    for material: ShaderMaterial in _materials:
        material.set_shader_parameter("canvas_size", size)
