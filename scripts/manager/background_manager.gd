extends MainGameSubManager
class_name BackgroundManager
## 背景管理器,管理背景和前景

## 可选的独立战场画面；不指定时使用原版背景，避免美术缩放带动选卡预览容器。
@export var background: Sprite2D
## 可选独立天幕，环境合成通过此引用绑定，不查找特定关卡节点。
@export var environment_sky: Sprite2D
## 雪山场景注入的本局雪表现，其他战场不实例化。
@export var snow_environment: SnowEnvironmentController
@onready var frontground: Node2D = %Frontground

@onready var home: MainGameHome = %Home
## 泳池
var pool:Pool
## 通用的冒险关卡局部水面控制器，原版泳池仍由 Pool 持有独立控制器。
var water_surface: WaterSurfaceController
## 浓雾
var fog:Fog

## 单一战斗天气导演：负责原版雨幕、湿镜头和可持续过渡。
var weather: BattleWeatherDirector
## 阶段配置需要时才创建的环境声画导演，随当前战斗释放。
var environment: BattleEnvironmentController

## 雾
const FOG = preload("uid://bs55ei6xiuugg")
## 阶段无天气配置时，导演保留原版关卡自带雨势；有配置则按时间轴过渡。
const WEATHER_DIRECTOR = preload("res://scripts/weather/battle_weather_director.gd")


## 保持原版的就绪时机，其他子管理器初始化前即可读取背景节点。
func _ready() -> void:
	if background == null:
		background = %Background


func init_manager() -> void:
	init_background()
	init_frontground()

## 初始化背景
func init_background():
	var curr_bg_texture: Texture2D = game_para.battle_background_texture
	if curr_bg_texture == null:
		curr_bg_texture = ConstLevelData.GameBgTextureMap[game_para.game_BG]
	background.texture = curr_bg_texture
	# 水面区域来自关卡资源，渲染与原版背景层共坐标，不侵入其他 CanvasLayer。
	if game_para.water_surface_profile != null:
		water_surface = WaterSurfaceController.new()
		water_surface.name = "WaterSurface"
		background.add_child(water_surface)
		# 水面在背景之后、其他道具之前绘制，不遮盖现有实体。
		background.move_child(water_surface, 0)
		water_surface.configure_background(background, game_para.water_surface_profile)
	# 自定义背景已绘制入口，原版房门和遮罩只与原版背景配套。
	home.init_home(game_para.game_BG, game_para.battle_background_texture == null)
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
	if is_instance_valid(snow_environment):
		snow_environment.configure(get_parent().get_parent() as MainGameManager, background, environment_sky)
		weather.bind_snow(snow_environment)
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
		transition_phase_environment(phase.environment_profile)

## 使用权威阶段的 [param profile] 过渡环境；空值退出滤镜与音效通道。
## [param cinematic] 仅用于已有阶段演出的暂停锁，不创建新的阶段状态机。
func transition_phase_environment(profile: BattleEnvironmentProfile, cinematic: bool = false) -> void:
	if profile != null and not is_instance_valid(environment):
		environment = BattleEnvironmentController.new()
		environment.name = "PhaseEnvironment"
		add_child(environment)
	if is_instance_valid(environment):
		environment.configure(profile, background, environment_sky, cinematic)

## 展示下一轮僵尸前退雾；直接进入下一轮时保留当前三叶草效果和移动。
func start_next_game_background_manager_update():
	if game_para.look_show_zombie and is_instance_valid(fog):
		fog.fog_outside()
