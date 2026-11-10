## 通用 2D 湿镜头后处理。只维护镜头接口、擦拭与闪电；水珠由独立模拟器实现。
extends CanvasLayer
class_name WeatherLensController


## 由关卡环境配置提供的镜头参数。
@export var profile: WeatherLensProfile
## 全屏画面后处理矩形。
@onready var lens_rect: ColorRect = $Lens

## 每场战斗的独立 ShaderMaterial 实例。
var _material: ShaderMaterial
## 光源锚点所依附的正式场景背景节点，由天气导演注入。
var background_sprite: Sprite2D
## 同一场天气唯一的离屏光场实例。
var _light_field: WeatherLightField
## 独立水珠模拟器脚本的权威资源路径，避免依赖编辑器类名缓存。
const DROPLET_SIMULATION = preload("res://scripts/weather/weather_lens_droplets.gd")
## 分辨率独立的地图光场组件，只有设置地图光源时才创建。
const LIGHT_FIELD_CLASS = preload("res://scripts/weather/weather_light_field.gd")
## 鼠标湿镜头轨迹由独立状态模拟器管理。
const WIPE_SIMULATION = preload("res://scripts/weather/weather_lens_wipe.gd")
## 可复用的镜头水珠状态模拟器。
var _droplets = DROPLET_SIMULATION.new()
## 擦拭路径点记录，xy 为 UV，z 为创建时间。
var _wipe = WIPE_SIMULATION.new()
## 逻辑游戏时间，暂停时不推进。
var _clock: float = 0.0
## 闪电随机时间的发生器。
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## 下一次随机闪电的游戏时间。
var _next_lightning: float = 9.0
## 上次闪电经过的游戏时间，负值表示无闪电。
var _flash_age: float = -1.0
## 当前天气镜头强度，允许同一组件从晴天连续淡入或淡出。
var _strength: float = 1.0


## 场景创建后克隆材质，并根据可选预设启停后处理。
func _ready() -> void:
    _material = lens_rect.material.duplicate() as ShaderMaterial
    lens_rect.material = _material
    _rng.seed = 20261110
    if profile != null and profile.light_profile != null and is_instance_valid(background_sprite):
        _light_field = LIGHT_FIELD_CLASS.new() as WeatherLightField
        _light_field.profile = profile.light_profile
        _light_field.background_sprite = background_sprite
        add_child(_light_field)
        _material.set_shader_parameter("light_field", _light_field.get_light_texture())
        _material.set_shader_parameter("bloom_tight", _light_field.get_tight_texture())
        _material.set_shader_parameter("bloom_wide", _light_field.get_wide_texture())
        _material.set_shader_parameter("has_light_field", true)
    get_viewport().size_changed.connect(_sync_viewport)
    configure(profile)


## 统一镜头配置入口；[param next_profile] 为 null 时关闭而不影响天气本体。
func configure(next_profile: WeatherLensProfile) -> void:
    profile = next_profile
    if not is_node_ready():
        return
    lens_rect.visible = profile != null
    set_process(profile != null)
    if profile != null:
        reset_effect()
        _apply_profile()


## 将资源参数映射至光学 Shader；与具体关卡编号无关。
func _apply_profile() -> void:
    _material.set_shader_parameter("soft_focus", profile.soft_focus)
    _material.set_shader_parameter("bloom_strength", profile.bloom_strength)
    _material.set_shader_parameter("haze_strength", profile.haze_strength)
    _material.set_shader_parameter("haze_color", profile.haze_color)
    if profile.light_profile != null and _light_field != null:
        _material.set_shader_parameter("bloom_tight_gain", profile.light_profile.bloom_tight)
        _material.set_shader_parameter("bloom_wide_gain", profile.light_profile.bloom_wide)
        _material.set_shader_parameter("air_scatter_gain", profile.light_profile.air_scatter)
        _material.set_shader_parameter("droplet_light_gain", profile.light_profile.droplet_response)
    _material.set_shader_parameter("droplet_strength", profile.droplet_strength)
    _material.set_shader_parameter("refraction_strength", profile.refraction_strength)
    _material.set_shader_parameter("wipe_radius", profile.wipe_radius)
    _material.set_shader_parameter("wipe_recovery_seconds", profile.wipe_recovery_seconds)
    set_weather_strength(_strength)
    _sync_viewport()
    _upload_gpu_state()


## 设置当前天气的渐进镜头强度；调用方无需知道 Shader 的参数细节。
## [param intensity] 0 完全透明，1 使用完整的镜头配置。
func set_weather_strength(intensity: float) -> void:
    _strength = clampf(intensity, 0.0, 1.0)
    if _light_field != null:
        _light_field.set_strength(_strength)
    if _material == null or profile == null:
        return
    lens_rect.visible = _strength > 0.001
    _material.set_shader_parameter("soft_focus", profile.soft_focus * _strength)
    _material.set_shader_parameter("bloom_strength", profile.bloom_strength * _strength)
    _material.set_shader_parameter("haze_strength", profile.haze_strength * _strength)
    _material.set_shader_parameter("droplet_strength", profile.droplet_strength * _strength)


## 暴露共享环境光场给雨幕和其它天气效果。
func get_light_field_texture() -> Texture2D:
    return _light_field.get_light_texture() if _light_field != null else null


## 注册运行时动态发光实体的统一接口，不修改战斗系统。
func register_light_emitter(emitter: CanvasItem, source: WeatherLightSource) -> void:
    if _light_field != null:
        _light_field.register_emitter(emitter, source)


## 移除运行时已注册的发光实体。
func unregister_light_emitter(emitter: CanvasItem) -> void:
    if _light_field != null:
        _light_field.unregister_emitter(emitter)


## 视口缩放时更新屏幕像素比例。
func _sync_viewport() -> void:
    if _material != null:
        _material.set_shader_parameter("viewport_size", get_viewport().get_visible_rect().size)


## 跟随引擎战斗时间，暂停和恢复自然生效。
## [param delta] 引擎游戏帧增量秒数。
func _process(delta: float) -> void:
    advance_effect(delta, get_viewport().get_mouse_position())


## 正式游戏与离线烘焙共享的状态推进入口。
## [param delta] 游戏增量秒数，不接受负增长。
## [param mouse_position] 鼠标视口像素位置；INF 表示没有擦拭。
func advance_effect(delta: float, mouse_position: Vector2) -> void:
    if profile == null or _material == null:
        return
    var dt: float = maxf(0.0, delta) # 本帧实际游戏增量。
    _clock += dt
    _droplets.advance(dt, profile.droplet_speed, mouse_position, profile.wipe_radius,
        get_viewport().get_visible_rect().size)
    _wipe.advance(mouse_position, _clock, get_viewport().get_visible_rect().size,
        profile.wipe_recovery_seconds)
    if _clock >= _next_lightning:
        if _strength >= 0.7:
            trigger_lightning()
        _next_lightning = _clock + _rng.randf_range(8.0, 14.0)
    if _flash_age >= 0.0:
        _flash_age += dt
    var flash: float = 0.0 # 含回闪的双脉冲强度。
    if _flash_age >= 0.0 and _flash_age < 0.6:
        flash = exp(-_flash_age * 17.0)
        if _flash_age > 0.17:
            flash += 0.47 * exp(-(_flash_age - 0.17) * 14.0)
    _material.set_shader_parameter("lightning", flash * profile.lightning_strength * _strength)
    _material.set_shader_parameter("clock_seconds", _clock)
    _upload_gpu_state()


## 外部天气事件使用的闪电光学表现入口，不改变关卡数值。
func trigger_lightning() -> void:
    _flash_age = 0.0


## 将擦拭历史和水珠位置统一同步给 GPU Shader。
func _upload_gpu_state() -> void:
    _material.set_shader_parameter("wipe_points", _wipe.get_uniform_data())
    _material.set_shader_parameter("drops", _droplets.get_uniform_data())


## 用于重开关卡或演示的明确状态清理。
func reset_effect() -> void:
    _clock = 0.0
    _wipe.reset()
    _flash_age = -1.0
    _next_lightning = _rng.randf_range(8.0, 14.0)
    _droplets.reset()
    if _material != null:
        _material.set_shader_parameter("clock_seconds", 0.0)
        _material.set_shader_parameter("lightning", 0.0)
        _upload_gpu_state()
