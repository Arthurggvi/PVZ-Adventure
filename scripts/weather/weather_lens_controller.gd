## 通用 2D 湿镜头后处理。只维护镜头接口、擦拭与闪电；水珠由独立模拟器实现。
extends CanvasLayer
class_name WeatherLensController

## GPU 允许的擦拭轨迹容量。
const WIPE_CAPACITY: int = 24
## 连续擦拭轨迹采样间距（像素）。
const WIPE_SPACING: float = 17.0

## 由关卡环境配置提供的镜头参数。
@export var profile: WeatherLensProfile
## 全屏画面后处理矩形。
@onready var lens_rect: ColorRect = $Lens

## 每场战斗的独立 ShaderMaterial 实例。
var _material: ShaderMaterial
## 独立水珠模拟器脚本的权威资源路径，避免依赖编辑器类名缓存。
const DROPLET_SIMULATION = preload("res://scripts/weather/weather_lens_droplets.gd")
## 可复用的镜头水珠状态模拟器。
var _droplets = DROPLET_SIMULATION.new()
## 擦拭路径点记录，xy 为 UV，z 为创建时间。
var _history: Array[Vector4] = []
## 逻辑游戏时间，暂停时不推进。
var _clock: float = 0.0
## 上一次有效的鼠标视口位置。
var _previous_mouse: Vector2 = Vector2.INF
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
    if _material == null or profile == null:
        return
    lens_rect.visible = _strength > 0.001
    _material.set_shader_parameter("soft_focus", profile.soft_focus * _strength)
    _material.set_shader_parameter("bloom_strength", profile.bloom_strength * _strength)
    _material.set_shader_parameter("haze_strength", profile.haze_strength * _strength)
    _material.set_shader_parameter("droplet_strength", profile.droplet_strength * _strength)


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
    if mouse_position.is_finite():
        _record_mouse(mouse_position)
    else:
        _previous_mouse = Vector2.INF
    _history = _history.filter(func(point: Vector4) -> bool:
        return _clock - point.z < profile.wipe_recovery_seconds * 5.0
    )
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


## 鼠标擦拭记录为固定容量的屏幕空间采样点。
## [param position] 当前鼠标在视口中的像素位置。
func _record_mouse(position: Vector2) -> void:
    var size: Vector2 = get_viewport().get_visible_rect().size # 当前视口尺寸。
    if position.x < 0.0 or position.y < 0.0 or position.x >= size.x or position.y >= size.y:
        _previous_mouse = Vector2.INF
        return
    if not _previous_mouse.is_finite():
        _add_brush(position / size)
    else:
        var distance_px: float = position.distance_to(_previous_mouse) # 鼠标位移。
        if distance_px >= WIPE_SPACING:
            var count: int = mini(WIPE_CAPACITY, ceili(distance_px / WIPE_SPACING))
            for index: int in range(1, count + 1):
                var sample: Vector2 = _previous_mouse.lerp(position, float(index) / float(count))
                _add_brush(sample / size)
    _previous_mouse = position


## 向擦拭记录中写入一处带出生时间的归一化笔刷位置。
## [param uv] 0-1 范围内的屏幕位置。
func _add_brush(uv: Vector2) -> void:
    _history.append(Vector4(uv.x, uv.y, _clock, 1.0))
    if _history.size() > WIPE_CAPACITY:
        _history.pop_front()


## 将擦拭历史和水珠位置统一同步给 GPU Shader。
func _upload_gpu_state() -> void:
    var brush_data: PackedVector4Array = PackedVector4Array() # 固定容量笔刷缓冲区。
    for index: int in range(WIPE_CAPACITY):
        brush_data.append(_history[index] if index < _history.size() else Vector4.ZERO)
    _material.set_shader_parameter("wipe_points", brush_data)
    _material.set_shader_parameter("drops", _droplets.get_uniform_data())


## 用于重开关卡或演示的明确状态清理。
func reset_effect() -> void:
    _clock = 0.0
    _previous_mouse = Vector2.INF
    _flash_age = -1.0
    _next_lightning = _rng.randf_range(8.0, 14.0)
    _history.clear()
    _droplets.reset()
    if _material != null:
        _material.set_shader_parameter("clock_seconds", 0.0)
        _material.set_shader_parameter("lightning", 0.0)
        _upload_gpu_state()
