## 冒险关卡的纯环境配置；波次、Boss、备战、胜负、掉落均不在这里。
## 由兼容层转换为底层 PVZ 引擎的 ResourceLevelData，不读取任何原版关卡规则。
extends Resource
class_name AdventureBattleEnvironment

@export var scene: MainSceneRegistry.MainScenes = MainSceneRegistry.MainScenes.MainGameFront
@export var background: ConstLevelData.GameBg = ConstLevelData.GameBg.FrontDay
@export var background_texture: Texture2D
## 独立水面视觉预设，空值不创建水面渲染层。
@export var water_surface_profile: WaterSurfaceProfile
## 战场逐行地形；空数组沿用原版场景节点设置，顺序自上而下。
@export var terrain_rows: Array[CharacterRegistry.ZombieRowType] = []
@export var music: ConstLevelData.GameBGM = ConstLevelData.GameBGM.FrontDay
@export var fog := false
## 进入战斗时的静态默认天气；阶段关键帧可以在战斗中改变雨势。
@export var rain := false
## 可选镜头后处理预设；空值代表无需镜头湿润特效。
@export var weather_lens_profile: WeatherLensProfile
@export var daytime := true
@export var daytime_sun := true
@export var lawn_mowers := true
@export var zombie_can_reach_home := true
@export var initial_sun: int = 150
@export var zombie_power_multiplier: int = 1
## 关卡指定的僵王本地出生点，零向量使用默认出场布局。
@export var boss_spawn_position := Vector2.ZERO
@export var shovel_enabled := true
@export var preplanted: Array[PrePlantResource] = []

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if scene == MainSceneRegistry.MainScenes.Null or not MainSceneRegistry.MainScenes.values().has(scene):
		errors.append("冒险战斗场景不存在。")
	if not ConstLevelData.GameBg.values().has(background):
		errors.append("冒险背景类型无效。")
	if not ConstLevelData.GameBGM.values().has(music):
		errors.append("冒险音乐类型无效。")
	if initial_sun < 0:
		errors.append("初始阳光不得为负数。")
	if zombie_power_multiplier < 1:
		errors.append("僵尸战力倍率必须为正整数。")
	return errors
