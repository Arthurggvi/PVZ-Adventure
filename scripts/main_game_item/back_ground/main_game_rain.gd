## 原版雨景的可调强度控制。原版关卡默认完整雨势；阶段过渡按 0..1 驱动。
extends Control
class_name MainGameRain

## 场景第一次进入树时的雨强度；沿用原场景时默认是 1。
@export_range(0.0, 1.0, 0.01) var initial_intensity: float = 1.0
## 原有 GPU 雨滴节点。
@onready var rain_particles: GPUParticles2D = $rainParticles
## 原有第一层空间雾。
@onready var rain_fog: ColorRect = $Fog
## 原有第二层体积感雾。
@onready var rain_fog_detail: ColorRect = $Fog3

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
    set_intensity(initial_intensity)


## 更新原版雨幕密度、两层雾及独立雨声音量。
## [param value] 目标雨强度，0=无雨，1=原场景完整雨势。
func set_intensity(value: float) -> void:
    _intensity = clampf(value, 0.0, 1.0)
    if not _initialized:
        initial_intensity = _intensity
        return
    rain_particles.emitting = _intensity > 0.001
    rain_particles.amount_ratio = _original_particle_ratio * _intensity
    rain_fog.modulate.a = _intensity
    rain_fog_detail.modulate.a = _intensity
    if is_instance_valid(Global.main_game):
        SoundManager.set_rain_intensity(_intensity)


## 返回当前雨幕强度供调试预览读取。
func get_intensity() -> float:
    return _intensity


## 雨景退出时停止独立环境雨声，不影响 BGM 或其它 SFX。
func _exit_tree() -> void:
    SoundManager.stop_rain_SFX()
