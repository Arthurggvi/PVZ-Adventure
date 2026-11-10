## 原版雨景的可调强度控制。原版关卡默认完整雨势；阶段过渡按 0..1 驱动。
extends Control
class_name MainGameRain

## 场景第一次进入树时的雨强度；沿用原场景时默认是 1。
@export_range(0.0, 1.0, 0.01) var initial_intensity: float = 1.0
## 最高强度下粒子比例；0 沿用原版场景自身值，以兼容其它雨关。
@export_range(0.0, 1.0, 0.01) var peak_particle_ratio: float = 0.0
## 可复用的多层雨幕参数；未指定时继续使用默认中雨参数。
@export var visual_profile: RainVisualProfile
## 原有 GPU 雨滴节点。
@onready var rain_particles: GPUParticles2D = $rainParticles
## 原有第一层空间雾。
@onready var rain_fog: ColorRect = $Fog
## 原有第二层体积感雾。
@onready var rain_fog_detail: ColorRect = $Fog3
## 新雨幕只负责视觉，原雨粒子和雨声仍使用其权威节点。
@onready var storm_renderer: RainStormRenderer = $StormRenderer

## 雨粒子场景配置的基准发射比例。
var _original_particle_ratio: float = 0.162
## 当前归一化雨势。
var _intensity: float = 1.0
## 节点是否已完成可用的雨幕粒子与雾节点初始化。
var _initialized: bool = false


## 保持原版雨声并应用指定初始强度，0 不开始播放。
func _ready() -> void:
    _original_particle_ratio = rain_particles.amount_ratio
    _initialized = true
    storm_renderer.configure(visual_profile)
    set_intensity(initial_intensity)


## 更新原版雨幕密度、两层雾及独立雨声音量。
## [param value] 目标雨强度，0=无雨，1=原场景完整雨势。
func set_intensity(value: float) -> void:
    _intensity = clampf(value, 0.0, 1.0)
    if not _initialized:
        initial_intensity = _intensity
        return
    rain_particles.emitting = _intensity > 0.001
    var peak: float = peak_particle_ratio if peak_particle_ratio > 0.0 else _original_particle_ratio
    rain_particles.amount_ratio = peak * _intensity
    rain_fog.modulate.a = _intensity
    rain_fog_detail.modulate.a = _intensity
    storm_renderer.set_intensity(_intensity)
    if is_instance_valid(Global.main_game):
        SoundManager.set_rain_intensity(_intensity)


## 切换分层雨幕材质的视觉参数，不影响关卡难度或天气阶段。
## [param next_profile] 新的暴雨表现配置。
func set_visual_profile(next_profile: RainVisualProfile) -> void:
    visual_profile = next_profile
    if _initialized:
        storm_renderer.configure(next_profile)


## 更新满雨势粒子预算而不改变当前雨强度；用于不同场景的天气时间轴。
## [param value] 0 为沿用原雨场景发射比例，非零值是满雨势的粒子比例。
func set_peak_particle_ratio(value: float) -> void:
    peak_particle_ratio = clampf(value, 0.0, 1.0)
    set_intensity(_intensity)


## 返回当前雨幕强度供调试预览读取。
func get_intensity() -> float:
    return _intensity


## 雨景退出时停止独立环境雨声，不影响 BGM 或其它 SFX。
func _exit_tree() -> void:
    SoundManager.stop_rain_SFX()
