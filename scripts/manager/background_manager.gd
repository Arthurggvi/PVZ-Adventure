extends MainGameSubManager
class_name BackgroundManager
## 背景管理器,管理背景和前景

@onready var background: Sprite2D = %Background
@onready var frontground: Node2D = %Frontground

@onready var home: MainGameHome = %Home
## 泳池
var pool:Pool
## 浓雾
var fog:Fog

## 单一战斗天气导演：负责原版雨幕、湿镜头和可持续过渡。
var weather: BattleWeatherDirector

## 雾
const FOG = preload("uid://bs55ei6xiuugg")
## 阶段无天气配置时，导演保留原版关卡自带雨势；有配置则按时间轴过渡。
const WEATHER_DIRECTOR = preload("res://scripts/weather/battle_weather_director.gd")


func init_manager() -> void:
	init_background()
	init_frontground()

## 初始化背景
func init_background():
	var curr_bg_texture: Texture2D = game_para.battle_background_texture
	if curr_bg_texture == null:
		curr_bg_texture = ConstLevelData.GameBgTextureMap[game_para.game_BG]
	background.texture = curr_bg_texture
	home.init_home(game_para.game_BG)
	if not game_para.is_zombie_can_home:
		print("僵尸无法进房")
		home.disable_home()
	match game_para.game_BG:
		ConstLevelData.GameBg.Pool, ConstLevelData.GameBg.Fog:
			pool = background.get_node(^"Pool")
			pool.init_pool(game_para)

## 初始化前景
## 建立固定的天气生命周期；天气由数据与阶段事件触发，而非关卡 ID 分支。
func init_frontground() -> void:
	if game_para.is_fog:
		fog = FOG.instantiate()
		frontground.add_child(fog)
	weather = WEATHER_DIRECTOR.new() as BattleWeatherDirector
	weather.setup(frontground, get_parent().get_parent(), game_para.weather_lens_profile, game_para.is_rain, background)
	add_child(weather)
	if AdventureSession.owns_battle(game_para):
		apply_phase_weather(AdventureSession.get_active_phase(game_para))

## 任意环境事件、阶段或演出可请求天气变化；null 表示保持已存在的天气。
## [param timeline] 表现强度关键帧构成的通用过渡。
func transition_weather(timeline: WeatherSequence) -> void:
	if is_instance_valid(weather):
		weather.play_sequence(timeline)

## 阶段系统只负责提供数据，不处理雨声、粒子或镜头实现。
## [param phase] 当前权威阶段，空值保持天气。
func apply_phase_weather(phase: StagePhaseDefinition) -> void:
	if phase != null:
		transition_weather(phase.weather_sequence)

## 展示下一轮僵尸前退雾；直接进入下一轮时保留当前三叶草效果和移动。
func start_next_game_background_manager_update():
	if game_para.look_show_zombie and is_instance_valid(fog):
		fog.fog_outside()
