## 天气导演：只负责状态、过渡和环境表现生命周期，与关卡身份彻底解耦。
extends Node
class_name BattleWeatherDirector

## 原有雨幕场景，继续提供原版 GPU 雨粒子与双层雾。
const RAIN_SCENE = preload("res://scenes/main_game_bg/rain.tscn")
## 已实现的湿镜头场景。
const LENS_SCENE = preload("res://scenes/weather/weather_lens.tscn")

## 战场前景层：只在需要时挂载雨幕或风沙。
var _rain_parent: Node2D
## 战斗根节点：只在需要时挂载固定屏幕空间的镜头层。
var _overlay_parent: Node
## 本局可以复用的湿镜头参数预设，允许为空。
var _lens_profile: WeatherLensProfile
## 光源位置所依附的地图背景 Sprite2D。
var _background_sprite: Sprite2D
## 关卡开始时的雨势及镜头强度。
var _initial: Vector2 = Vector2.ZERO
## 当前过渡时间轴；空值表示保持上次天气不再驱动。
var _sequence: WeatherSequence
## 当前过渡时钟，遵守战斗暂停。
var _elapsed: float = 0.0
## 当前天气状态 x=雨势，y=镜头强度。
var _strength: Vector2 = Vector2.ZERO
## 最高雨强的粒子密度，0 沿用原雨景场景的默认密度。
var _peak_particle_ratio: float = 0.0
## 上次天气过渡选用的分层雨幕表现配置。
var _rain_visual_profile: RainVisualProfile
## 上次天气过渡选用的降雨混音预设，未配置时为 null。
var _rain_audio_profile: RainAudioProfile
## 按需实例化的原版雨景。
var _rain: MainGameRain
## 按需实例化的湿镜头。
var _lens: WeatherLensController
## 独立风沙通道的当前强度，保留既有雨景 Vector2 接口。
var _sand_strength: float = 0.0
## 当前时间轴选用的风沙表现预设。
var _sand_visual_profile: SandVisualProfile
## 按需创建的分层风沙；场景切换时随战场释放。
var _sand: SandStormRenderer
## 沙暴指针漂移由独立输入组件接收同一风场，默认关闭。
var _sand_cursor: WeatherCursorDrift
## 当前阶段允许的最大指针漂移速度，单位视口像素/秒。
var _sand_cursor_speed: float = 0.0


## 创建天气导演前配置权威挂载点和默认环境。
## [param rain_parent] 现有战场前景层。
## [param overlay_parent] 战场根节点，镜头使用独立 CanvasLayer。
## [param lens_profile] 当前关卡可用的镜头光学参数。
## [param initial_rain] 静态环境是否持续下雨，适配原版雨关。
## [param background_sprite] 最终背景精灵，为分层天气提供权威坐标。
func setup(rain_parent: Node2D, overlay_parent: Node, lens_profile: WeatherLensProfile,
        initial_rain: bool, background_sprite: Sprite2D = null) -> void:
    _background_sprite = background_sprite
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
    _peak_particle_ratio = timeline.rain_particle_ratio_at_full
    _rain_visual_profile = timeline.rain_visual_profile
    _rain_audio_profile = timeline.rain_audio_profile
    _sand_visual_profile = timeline.sand_visual_profile
    _sand_cursor_speed = timeline.sand_cursor_speed
    if is_instance_valid(_sand_cursor):
        _sand_cursor.speed = _sand_cursor_speed
    if is_instance_valid(_sand):
        _sand.configure(_sand_visual_profile)
    if is_instance_valid(_rain):
        _rain.set_peak_particle_ratio(_peak_particle_ratio)
        _rain.set_visual_profile(_rain_visual_profile)
        _rain.rain_audio_profile = _rain_audio_profile
    _elapsed = 0.0
    _apply_channels(timeline.sample_channels(0.0))
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
    _apply_channels(_sequence.sample_channels(_elapsed))
    if _elapsed >= _sequence.get_duration():
        # 释放过渡但保留各通道末帧强度，渲染器继续推进自身风场。
        _sequence = null
        set_process(false)


## 读取已生效的天气强度，供调试器或预览使用。
func current_strength() -> Vector2:
    return _strength


## 返回当前风沙强度，0..1；不改变既有降雨查询协议。
func current_sand_strength() -> float:
    return _sand_strength


## 同步所有天气通道；[param values] 的 x/y/z 分别为雨、湿镜头、风沙。
func _apply_channels(values: Vector3) -> void:
    _apply_strength(Vector2(values.x, values.y))
    _sand_strength = clampf(values.z, 0.0, 1.0)
    if _sand_strength > 0.001 and _sand == null:
        _sand = SandStormRenderer.new()
        _sand.name = "SandStorm"
        _sand.setup(_background_sprite, _sand_visual_profile)
        _rain_parent.add_child(_sand)
        _sand_cursor = WeatherCursorDrift.new()
        _sand_cursor.battle = _overlay_parent as MainGameManager
        _sand_cursor.speed = _sand_cursor_speed
        _sand.add_child(_sand_cursor)
        _sand.wind_advanced.connect(_sand_cursor.advance_wind)
    if is_instance_valid(_sand):
        _sand.set_intensity(_sand_strength)


## 同步雨幕与镜头表现，仅在需要时实例化对象。
## [param values] x 为雨强度、y 为镜头强度。
func _apply_strength(values: Vector2) -> void:
    _strength = Vector2(clampf(values.x, 0.0, 1.0), clampf(values.y, 0.0, 1.0))
    if _strength.x > 0.001 and _rain == null:
        _rain = RAIN_SCENE.instantiate() as MainGameRain
        _rain.peak_particle_ratio = _peak_particle_ratio
        _rain.visual_profile = _rain_visual_profile
        _rain.rain_audio_profile = _rain_audio_profile
        _rain.initial_intensity = _strength.x
        _rain_parent.add_child(_rain)
    if is_instance_valid(_rain):
        _rain.set_intensity(_strength.x)
        _rain.visible = _strength.x > 0.001
    if _strength.y > 0.001 and _lens == null and _lens_profile != null:
        _lens = LENS_SCENE.instantiate() as WeatherLensController
        _lens.profile = _lens_profile
        _lens.background_sprite = _background_sprite
        _lens.set_weather_strength(_strength.y)
        _overlay_parent.add_child(_lens)
    if is_instance_valid(_lens):
        _lens.set_weather_strength(_strength.y)
        if is_instance_valid(_rain) and _lens.get_light_field_texture() != null:
            var response: float = _lens_profile.light_profile.rain_response
            _rain.set_light_field(_lens.get_light_field_texture(), response)


## 风沙挂在外部前景容器，导演被单独移除时也应停止风场、指针漂移和背景沙墙。
func _exit_tree() -> void:
    if is_instance_valid(_sand):
        _sand.queue_free()
