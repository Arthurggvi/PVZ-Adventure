## 天气导演：只负责状态、过渡和环境表现生命周期，与关卡身份彻底解耦。
extends Node
class_name BattleWeatherDirector

## 原有雨幕场景，继续提供原版 GPU 雨粒子与双层雾。
const RAIN_SCENE = preload("res://scenes/main_game_bg/rain.tscn")
## 已实现的湿镜头场景。
const LENS_SCENE = preload("res://scenes/weather/weather_lens.tscn")

## 战场前景层：只在需要时挂载原版雨幕。
var _rain_parent: Node2D
## 战斗根节点：只在需要时挂载固定屏幕空间的镜头层。
var _overlay_parent: Node
## 本局可以复用的湿镜头参数预设，允许为空。
var _lens_profile: WeatherLensProfile
## 关卡开始时的雨势及镜头强度。
var _initial: Vector2 = Vector2.ZERO
## 当前过渡时间轴；空值表示保持上次天气不再驱动。
var _sequence: WeatherSequence
## 当前过渡时钟，遵守战斗暂停。
var _elapsed: float = 0.0
## 当前天气状态 x=雨势，y=镜头强度。
var _strength: Vector2 = Vector2.ZERO
## 按需实例化的原版雨景。
var _rain: MainGameRain
## 按需实例化的湿镜头。
var _lens: WeatherLensController


## 创建天气导演前配置权威挂载点和默认环境。
## [param rain_parent] 现有战场前景层。
## [param overlay_parent] 战场根节点，镜头使用独立 CanvasLayer。
## [param lens_profile] 当前关卡可用的镜头光学参数。
## [param initial_rain] 静态环境是否持续下雨，适配原版雨关。
func setup(rain_parent: Node2D, overlay_parent: Node, lens_profile: WeatherLensProfile,
        initial_rain: bool) -> void:
    _rain_parent = rain_parent
    _overlay_parent = overlay_parent
    _lens_profile = lens_profile
    _initial = Vector2.ONE if initial_rain else Vector2.ZERO


## 默认保持当前环境，不存在时间轴时没有逐帧计算。
func _ready() -> void:
    set_process(false)
    _apply_strength(_initial)


## 任意事件可以请求新天气时间轴；空值意味着原天气持续，不清零、不回晴。
## [param timeline] 可在任意关卡或剧情中复用的带强度关键帧的天气时间轴。
func play_sequence(timeline: WeatherSequence) -> void:
    if timeline == null:
        return
    if not timeline.validate().is_empty():
        push_error("天气时间轴配置无效：" + str(timeline.validate()))
        return
    _sequence = timeline
    _elapsed = 0.0
    _apply_strength(timeline.sample(0.0))
    set_process(timeline.get_duration() > 0.0)


## 每帧推进天气过渡。空值阶段不执行这个循环。
## [param delta] 引擎提供的游戏秒数。
func _process(delta: float) -> void:
    advance_weather(delta)


## 统一的过渡推进算法，离线预览可直接使用同一套逻辑。
## [param delta] 游戏时间推进量，单位秒。
func advance_weather(delta: float) -> void:
    if _sequence == null:
        return
    _elapsed = minf(_sequence.get_duration(), _elapsed + maxf(delta, 0.0))
    _apply_strength(_sequence.sample(_elapsed))
    if _elapsed >= _sequence.get_duration():
        # 释放过渡但保留最后雨势，直到新时间轴显式接管。
        _sequence = null
        set_process(false)


## 读取已生效的天气强度，供调试器或预览使用。
func current_strength() -> Vector2:
    return _strength


## 同步雨幕与镜头表现，仅在需要时实例化对象。
## [param values] x 为雨强度、y 为镜头强度。
func _apply_strength(values: Vector2) -> void:
    _strength = Vector2(clampf(values.x, 0.0, 1.0), clampf(values.y, 0.0, 1.0))
    if _strength.x > 0.001 and _rain == null:
        _rain = RAIN_SCENE.instantiate() as MainGameRain
        _rain.initial_intensity = _strength.x
        _rain_parent.add_child(_rain)
    if is_instance_valid(_rain):
        _rain.set_intensity(_strength.x)
        _rain.visible = _strength.x > 0.001
    if _strength.y > 0.001 and _lens == null and _lens_profile != null:
        _lens = LENS_SCENE.instantiate() as WeatherLensController
        _lens.profile = _lens_profile
        _lens.set_weather_strength(_strength.y)
        _overlay_parent.add_child(_lens)
    if is_instance_valid(_lens):
        _lens.set_weather_strength(_strength.y)
