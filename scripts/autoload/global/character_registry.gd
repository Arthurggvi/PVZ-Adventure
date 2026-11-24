extends Node
class_name CharacterRegistry

## 战斗租约复用角色场景；战外图鉴等请求不再成为进程级强引用。
const BattleScope = preload("res://scripts/autoload/global/battle_resource_scope.gd")
## 当前注册表独占的战斗资源租约。
var _battle_scope := BattleScope.new()

## [param path] 为注册表的权威资源路径；仅本局战斗需要保留重复生成的根资源。
func _registry_resource(path: String) -> Resource:
	var global_node: Node = get_node_or_null("/root/Global") # 启动期也允许注册表独立查询。
	var owner: Node = global_node.get("main_game") if global_node != null else null # 当前战斗节点。
	var result: Resource = _battle_scope.resolve(owner, path) # 与现有加载入口共享资源。
	if result == null:
		push_error("CharacterRegistry: failed to load " + path)
	return result

## [param owner] 为目标战斗；[param resources] 是首屏批次。仅登记本局后续生成需要的注册资源。
func retain_prepared_battle(owner: Node, resources: Array) -> void:
	var paths: Dictionary = {} # 从权威注册表提取允许进入租约的路径。
	for entry: Dictionary in PlantInfo.values():
		for key: int in [PlantInfoAttribute.PlantScenes, PlantInfoAttribute.PlantConditionResource]:
			paths[entry.get(key, "")] = true
	for entry: Dictionary in ZombieInfo.values():
		paths[entry.get(ZombieInfoAttribute.ZombieScenes, "")] = true
	for entry: Dictionary in ZombieBossInfo.values():
		paths[entry.get(ZombieBossInfoAttribute.BossScenes, "")] = true
	for resource: Resource in resources:
		if paths.has(resource.resource_path):
			_battle_scope.retain(owner, resource)

func _attribute(entry: Dictionary, key: int, resource_keys: Array[int]) -> Variant:
	var value: Variant = entry.get(key)
	if key not in resource_keys:
		return value
	return _registry_resource(value) if value is String and not value.is_empty() else null


## 定义枚举
enum CharacterType {Null, Plant, Zombie, ZombieBoss}

#region 植物
## 植物信息属性
enum PlantInfoAttribute{
	PlantName,
	CoolTime,		## 植物种植冷却时间
	SunCost,		## 阳光消耗
	PlantScenes,	## 植物场景预加载
	PlantConditionResource,	## 植物种植条件资源预加载
}

## 植物类型
enum PlantType {
	Null = 0,
	P001PeaShooterSingle = 1,
	P002SunFlower,
	P003CherryBomb,
	P004WallNut,
	P005PotatoMine,
	P006SnowPea,
	P007Chomper,
	P008PeaShooterDouble,

	P009PuffShroom,
	P010SunShroom,
	P011FumeShroom,
	P012GraveBuster,
	P013HypnoShroom,
	P014ScaredyShroom,
	P015IceShroom,
	P016DoomShroom,

	P017LilyPad,
	P018Squash,
	P019ThreePeater,
	P020TangleKelp,
	P021Jalapeno,
	P022Caltrop,
	P023TorchWood,
	P024TallNut,

	P025SeaShroom,
	P026Plantern,
	P027Cactus,
	P028Blover,
	P029SplitPea,
	P030StarFruit,
	P031Pumpkin,
	P032MagnetShroom,

	P033CabbagePult,
	P034FlowerPot,
	P035CornPult,
	P036CoffeeBean,
	P037Garlic,
	P038UmbrellaLeaf,
	P039MariGold,
	P040MelonPult,

	P041GatlingPea,
	P042TwinSunFlower,
	P043GloomShroom,
	P044Cattail,
	P045WinterMelon,
	P046GoldMagnet,
	P047SpikeRock,
	P048CobCannon,

	P049PeaShooterDoubleReverse,
	## 闪电芦苇，保留现有植物的存档编号。
	P050LightningReed = 50,

	## 回旋镖射手的存档编号。
	P051Bloomerang = 51,

	## 电能豌豆的稳定存档编号，不改变已有植物身份。
	P052ElectricPeashooter = 52,

	## 模仿者
	P999Imitater = 999,
	## 发芽
	P1000Sprout = 1000,
	## 保龄球
	P1001WallNutBowling = 1001,
	P1002WallNutBowlingBomb,
	P1003WallNutBowlingBig,
	}


## 植物在格子中的位置
enum PlacePlantInCell{
	Norm,	## 普通位置
	Shell,	## 保护壳位置
	Down,	## 花盆（睡莲）位置
	Float,	## 漂浮位置
	Imitater,## 模仿者位置
}

#endregion

#region 僵尸
## 僵尸类型
enum ZombieType {
	Null = 0,

	Z001Norm = 1,
	Z002Flag,
	Z003Cone,
	Z004PoleVaulter,
	Z005Bucket,

	Z006Paper,
	Z007ScreenDoor,
	Z008Football,
	Z009Jackson,
	Z010Dancer,

	Z011Duckytube,
	Z012Snorkle,
	Z013Zamboni,
	Z014Bobsled,
	Z015Dolphinrider,

	Z016Jackbox,
	Z017Balloon,
	Z018Digger,
	Z019Pogo,
	Z020Yeti,

	Z021Bungi,
	Z022Ladder,
	Z023Catapult,
	Z024Gargantuar,
	Z025Imp,
	Z026AllStar,
	Z027Explorer,
	Z028StoneStatue = 28, ## 固定石壳保护同阶普通僵尸，编号不得随目录顺序变化。
	## 大型融合僵尸的稳定物种编号；新增角色不改变既有存档身份。
	Z029LargeFusion = 29,
	## 穴居僵尸的稳定物种编号；推冰行为由本体实例独立管理。
	Z030Troglobite = 30,
	## 雪人小鬼僵尸的稳定物种编号；直接生成时不携带冰壳。
	Z031YetiImp = 31,
	## 猎人僵尸的稳定物种编号；雪球寒冷与植物冰壳由战斗实例维护。
	Z032Hunter = 32,
	## 滑雪僵尸的稳定物种编号；冻结障碍与飞跃状态仅由战场实例管理。
	Z033Ski = 33,
	## 原版天空之城战斗机僵尸；固定编号不影响旧存档。
	Z034Fighter = 34,
	## 仲裁者-X型独立物种；35/36/37 留给天空之城其他机种。
	Z038ArbiterX = 38,
	## 导弹炮塔僵尸的稳定编号；导弹作为战场弹体单独管理。
	Z039CannonTurret = 39,
	## 运输舰僵尸从棋盘上方入场，战斗机继承已有物种编号。
	Z040TransportAirship = 40,
	## 火箭小鬼独立于普通小鬼的稳定物种编号。
	Z041RocketImp = 41,

	Z1001BobsledSingle=1001,	## 单个雪橇车僵尸
	}

## 僵尸行类型
enum ZombieRowType{
	Land,
	Pool,
	Both,
}

## 僵尸信息属性
enum ZombieInfoAttribute{
	ZombieName,
	CoolTime,		## 僵尸冷却时间
	SunCost,		## 阳光消耗
	ZombieScenes,	## 植物场景预加载
	ZombieRowType,	## 僵尸行类型
}


#endregion


#region 植物种植信息
## 紫卡植物种植前置植物
@export var AllPrePlantPurple:Dictionary[PlantType, PlantType]= {
	PlantType.P041GatlingPea:PlantType.P008PeaShooterDouble,
	PlantType.P042TwinSunFlower:PlantType.P002SunFlower,
	PlantType.P043GloomShroom:PlantType.P011FumeShroom,
	PlantType.P044Cattail:PlantType.P017LilyPad,
	PlantType.P045WinterMelon:PlantType.P040MelonPult,
	PlantType.P046GoldMagnet:PlantType.P032MagnetShroom,
	PlantType.P047SpikeRock:PlantType.P022Caltrop,
	PlantType.P048CobCannon:PlantType.P035CornPult,
}

const PlantInfo = {
	PlantType.P001PeaShooterSingle: {
		PlantInfoAttribute.PlantName: "PeaShooterSingle",
		PlantInfoAttribute.CoolTime: 7.5,
		PlantInfoAttribute.SunCost: 100,
		PlantInfoAttribute.PlantConditionResource:"res://resources/character_resource/plant_condition/000_common_plant_land.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_001_pea_shooter_single.tscn"
		},
	PlantType.P002SunFlower: {
		PlantInfoAttribute.PlantName: "SunFlower",
		PlantInfoAttribute.CoolTime: 7.5,
		PlantInfoAttribute.SunCost: 50,
		PlantInfoAttribute.PlantConditionResource:"res://resources/character_resource/plant_condition/000_common_plant_land.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_002_sun_flower.tscn"
		},
	PlantType.P003CherryBomb: {
		PlantInfoAttribute.PlantName: "CherryBomb",
		PlantInfoAttribute.CoolTime: 50.0,
		PlantInfoAttribute.SunCost: 150,
		PlantInfoAttribute.PlantConditionResource : "res://resources/character_resource/plant_condition/000_common_plant_land.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_003_cherry_bomb.tscn"
		},
	PlantType.P004WallNut: {
		PlantInfoAttribute.PlantName: "WallNut",
		PlantInfoAttribute.CoolTime: 30.0,
		PlantInfoAttribute.SunCost: 50,
		PlantInfoAttribute.PlantConditionResource : "res://resources/character_resource/plant_condition/000_common_plant_land.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_004_wall_nut.tscn"
		},
	PlantType.P005PotatoMine: {
		PlantInfoAttribute.PlantName: "PotatoMine",
		PlantInfoAttribute.CoolTime: 30.0,
		PlantInfoAttribute.SunCost: 25,
		PlantInfoAttribute.PlantConditionResource : "res://resources/character_resource/plant_condition/005_potato_mine.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_005_potato_mine.tscn"
		},
	PlantType.P006SnowPea: {
		PlantInfoAttribute.PlantName: "SnowPea",
		PlantInfoAttribute.CoolTime: 7.5,
		PlantInfoAttribute.SunCost: 175,
		PlantInfoAttribute.PlantConditionResource : "res://resources/character_resource/plant_condition/000_common_plant_land.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_006_snow_pea.tscn"
		},
	PlantType.P007Chomper: {
		PlantInfoAttribute.PlantName: "Chomper",
		PlantInfoAttribute.CoolTime: 7.5,
		PlantInfoAttribute.SunCost: 150,
		PlantInfoAttribute.PlantConditionResource : "res://resources/character_resource/plant_condition/000_common_plant_land.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_007_chomper.tscn"
		},
	PlantType.P008PeaShooterDouble: {
		PlantInfoAttribute.PlantName: "PeaShooterDouble",
		PlantInfoAttribute.CoolTime: 7.5,
		PlantInfoAttribute.SunCost: 200,
		PlantInfoAttribute.PlantConditionResource : "res://resources/character_resource/plant_condition/000_common_plant_land.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_008_pea_shooter_double.tscn"
		},
		#
	PlantType.P009PuffShroom: {
		PlantInfoAttribute.PlantName: "PuffShroom",
		PlantInfoAttribute.CoolTime: 7.5,
		PlantInfoAttribute.SunCost: 0,
		PlantInfoAttribute.PlantConditionResource : "res://resources/character_resource/plant_condition/000_common_plant_land.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_009_puff.tscn"
		},
	PlantType.P010SunShroom: {
		PlantInfoAttribute.PlantName: "SunShroom",
		PlantInfoAttribute.CoolTime: 7.5,
		PlantInfoAttribute.SunCost: 25,
		PlantInfoAttribute.PlantConditionResource : "res://resources/character_resource/plant_condition/000_common_plant_land.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_010_sun_shroom.tscn"
		},
	PlantType.P011FumeShroom: {
		PlantInfoAttribute.PlantName: "FumeShroom",
		PlantInfoAttribute.CoolTime: 7.5,
		PlantInfoAttribute.SunCost: 75,
		PlantInfoAttribute.PlantConditionResource : "res://resources/character_resource/plant_condition/000_common_plant_land.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_011_fume_shroom.tscn"
		},
	PlantType.P012GraveBuster: {
		PlantInfoAttribute.PlantName: "GraveBuster",
		PlantInfoAttribute.CoolTime: 7.5,
		PlantInfoAttribute.SunCost: 75,
		PlantInfoAttribute.PlantConditionResource : "res://resources/character_resource/plant_condition/012_grave_buster.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_012_grave_buster.tscn"
		},
	PlantType.P013HypnoShroom: {
		PlantInfoAttribute.PlantName: "HypnoShroom",
		PlantInfoAttribute.CoolTime: 30.0,
		PlantInfoAttribute.SunCost: 75,
		PlantInfoAttribute.PlantConditionResource : "res://resources/character_resource/plant_condition/000_common_plant_land.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_013_hypno_shroom.tscn"
		},
	PlantType.P014ScaredyShroom: {
		PlantInfoAttribute.PlantName: "ScaredyShroom",
		PlantInfoAttribute.CoolTime: 7.5,
		PlantInfoAttribute.SunCost: 25,
		PlantInfoAttribute.PlantConditionResource : "res://resources/character_resource/plant_condition/000_common_plant_land.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_014_scaredy_shroom.tscn"
		},
	PlantType.P015IceShroom: {
		PlantInfoAttribute.PlantName: "IceShroom",
		PlantInfoAttribute.CoolTime: 50.0,
		PlantInfoAttribute.SunCost: 75,
		PlantInfoAttribute.PlantConditionResource : "res://resources/character_resource/plant_condition/000_common_plant_land.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_015_ice_shroom.tscn"
		},
	PlantType.P016DoomShroom: {
		PlantInfoAttribute.PlantName: "DoomShroom",
		PlantInfoAttribute.CoolTime: 50.0,
		PlantInfoAttribute.SunCost: 125,
		PlantInfoAttribute.PlantConditionResource : "res://resources/character_resource/plant_condition/000_common_plant_land.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_016_doom_shroom.tscn"
		},
	PlantType.P017LilyPad: {
		PlantInfoAttribute.PlantName: "LilyPad",
		PlantInfoAttribute.CoolTime: 7.5,
		PlantInfoAttribute.SunCost: 25,
		PlantInfoAttribute.PlantConditionResource : "res://resources/character_resource/plant_condition/017_lily_pad.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_017_lily_pad.tscn"
		},
	PlantType.P018Squash: {
		PlantInfoAttribute.PlantName: "Squash",
		PlantInfoAttribute.CoolTime: 30.0,
		PlantInfoAttribute.SunCost: 50,
		PlantInfoAttribute.PlantConditionResource : "res://resources/character_resource/plant_condition/000_common_plant_land.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_018_squash.tscn"
		},
	PlantType.P019ThreePeater: {
		PlantInfoAttribute.PlantName: "ThreePeater",
		PlantInfoAttribute.CoolTime: 15.0,
		PlantInfoAttribute.SunCost: 325,
		PlantInfoAttribute.PlantConditionResource : "res://resources/character_resource/plant_condition/000_common_plant_land.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_019_three_peater.tscn"
		},
	PlantType.P020TangleKelp: {
		PlantInfoAttribute.PlantName: "TangleKelp",
		PlantInfoAttribute.CoolTime: 30.0,
		PlantInfoAttribute.SunCost: 25,
		PlantInfoAttribute.PlantConditionResource : "res://resources/character_resource/plant_condition/020_tanglekelp.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_020_tanglekelp.tscn"
		},
	PlantType.P021Jalapeno: {
		PlantInfoAttribute.PlantName: "Jalapeno",
		PlantInfoAttribute.CoolTime: 50.0,
		PlantInfoAttribute.SunCost: 125,
		PlantInfoAttribute.PlantConditionResource : "res://resources/character_resource/plant_condition/000_common_plant_land.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_021_jalapeno.tscn"
		},
	PlantType.P022Caltrop: {
		PlantInfoAttribute.PlantName: "Caltrop",
		PlantInfoAttribute.CoolTime: 7.5,
		PlantInfoAttribute.SunCost: 125,
		PlantInfoAttribute.PlantConditionResource : "res://resources/character_resource/plant_condition/022_caltrop.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_022_caltrop.tscn"
		},
	PlantType.P023TorchWood: {
		PlantInfoAttribute.PlantName: "TorchWood",
		PlantInfoAttribute.CoolTime: 7.5,
		PlantInfoAttribute.SunCost: 175,
		PlantInfoAttribute.PlantConditionResource : "res://resources/character_resource/plant_condition/000_common_plant_land.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_023_torch_wood.tscn"
		},
	PlantType.P024TallNut: {
		PlantInfoAttribute.PlantName: "TallNut",
		PlantInfoAttribute.CoolTime: 30.0,
		PlantInfoAttribute.SunCost: 175,
		PlantInfoAttribute.PlantConditionResource : "res://resources/character_resource/plant_condition/000_common_plant_land.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_024_tall_nut.tscn"
		},

	PlantType.P025SeaShroom: {
		PlantInfoAttribute.PlantName: "SeaShroom",
		PlantInfoAttribute.CoolTime: 30.0,
		PlantInfoAttribute.SunCost: 0,
		PlantInfoAttribute.PlantConditionResource : "res://resources/character_resource/plant_condition/020_tanglekelp.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_025_sea_shroom.tscn"
		},
	PlantType.P026Plantern: {
		PlantInfoAttribute.PlantName: "Plantern",
		PlantInfoAttribute.CoolTime: 30.0,
		PlantInfoAttribute.SunCost: 25,
		PlantInfoAttribute.PlantConditionResource : "res://resources/character_resource/plant_condition/000_common_plant_land.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_026_plantern.tscn"
		},
	PlantType.P027Cactus: {
		PlantInfoAttribute.PlantName: "Cactus",
		PlantInfoAttribute.CoolTime: 7.5,
		PlantInfoAttribute.SunCost: 125,
		PlantInfoAttribute.PlantConditionResource :  "res://resources/character_resource/plant_condition/000_common_plant_land.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_027_cactus.tscn"
		},
	PlantType.P028Blover: {
		PlantInfoAttribute.PlantName: "Blover",
		PlantInfoAttribute.CoolTime: 7.5,
		PlantInfoAttribute.SunCost: 100,
		PlantInfoAttribute.PlantConditionResource :  "res://resources/character_resource/plant_condition/000_common_plant_land.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_028_blover.tscn"
		},
	PlantType.P029SplitPea: {
		PlantInfoAttribute.PlantName: "SplitPea",
		PlantInfoAttribute.CoolTime: 7.5,
		PlantInfoAttribute.SunCost: 125,
		PlantInfoAttribute.PlantConditionResource :  "res://resources/character_resource/plant_condition/000_common_plant_land.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_029_split_pea.tscn"
		},
	PlantType.P030StarFruit: {
		PlantInfoAttribute.PlantName: "StarFruit",
		PlantInfoAttribute.CoolTime: 7.5,
		PlantInfoAttribute.SunCost: 125,
		PlantInfoAttribute.PlantConditionResource :  "res://resources/character_resource/plant_condition/000_common_plant_land.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_030_star_fruit.tscn"
		},
	PlantType.P031Pumpkin: {
		PlantInfoAttribute.PlantName: "Pumpkin",
		PlantInfoAttribute.CoolTime: 30.0,
		PlantInfoAttribute.SunCost: 125,
		PlantInfoAttribute.PlantConditionResource :  "res://resources/character_resource/plant_condition/031_Pumpkin.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_031_pumpkin.tscn"
		},
	PlantType.P032MagnetShroom: {
		PlantInfoAttribute.PlantName: "MagnetShroom",
		PlantInfoAttribute.CoolTime: 7.5,
		PlantInfoAttribute.SunCost: 100,
		PlantInfoAttribute.PlantConditionResource :  "res://resources/character_resource/plant_condition/000_common_plant_land.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_032_magnet_shroom.tscn"
		},

	PlantType.P033CabbagePult: {
		PlantInfoAttribute.PlantName: "CabbagePult",
		PlantInfoAttribute.CoolTime: 7.5,
		PlantInfoAttribute.SunCost: 100,
		PlantInfoAttribute.PlantConditionResource :  "res://resources/character_resource/plant_condition/000_common_plant_land.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_033_cabbage_pult.tscn"
		},
	PlantType.P034FlowerPot: {
		PlantInfoAttribute.PlantName: "FlowerPot",
		PlantInfoAttribute.CoolTime: 7.5,
		PlantInfoAttribute.SunCost: 25,
		PlantInfoAttribute.PlantConditionResource :  "res://resources/character_resource/plant_condition/034_flower_pot.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_034_flower_pot.tscn"
		},
	PlantType.P035CornPult: {
		PlantInfoAttribute.PlantName: "CornPult",
		PlantInfoAttribute.CoolTime: 7.5,
		PlantInfoAttribute.SunCost: 125,
		PlantInfoAttribute.PlantConditionResource :  "res://resources/character_resource/plant_condition/000_common_plant_land.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_035_corn_pult.tscn"
		},
	PlantType.P036CoffeeBean: {
		PlantInfoAttribute.PlantName: "CoffeeBean",
		PlantInfoAttribute.CoolTime: 7.5,
		PlantInfoAttribute.SunCost: 75,
		PlantInfoAttribute.PlantConditionResource :  "res://resources/character_resource/plant_condition/036_coffee_bean.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_036_coffee_bean.tscn"
		},
	PlantType.P037Garlic: {
		PlantInfoAttribute.PlantName: "Garlic",
		PlantInfoAttribute.CoolTime: 7.5,
		PlantInfoAttribute.SunCost: 50,
		PlantInfoAttribute.PlantConditionResource :  "res://resources/character_resource/plant_condition/000_common_plant_land.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_037_garlic.tscn"
		},
	PlantType.P038UmbrellaLeaf: {
		PlantInfoAttribute.PlantName: "UmbrellaLeaf",
		PlantInfoAttribute.CoolTime: 7.5,
		PlantInfoAttribute.SunCost: 100,
		PlantInfoAttribute.PlantConditionResource :  "res://resources/character_resource/plant_condition/000_common_plant_land.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_038_umbrella_leaf.tscn"
		},
	PlantType.P039MariGold: {
		PlantInfoAttribute.PlantName: "MariGold",
		PlantInfoAttribute.CoolTime: 30.0,
		PlantInfoAttribute.SunCost: 50,
		PlantInfoAttribute.PlantConditionResource :  "res://resources/character_resource/plant_condition/000_common_plant_land.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_039_mari_gold.tscn"
		},
	PlantType.P040MelonPult: {
		PlantInfoAttribute.PlantName: "MelonPult",
		PlantInfoAttribute.CoolTime: 15.0,
		PlantInfoAttribute.SunCost: 300,
		PlantInfoAttribute.PlantConditionResource :  "res://resources/character_resource/plant_condition/000_common_plant_land.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_040_melon_pult.tscn"
		},

	PlantType.P041GatlingPea: {
		PlantInfoAttribute.PlantName: "GatlingPea",
		PlantInfoAttribute.CoolTime: 50.0,
		PlantInfoAttribute.SunCost: 250,
		PlantInfoAttribute.PlantConditionResource : "res://resources/character_resource/plant_condition/000_common_purple.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_041_gatling_pea.tscn"
		},

	PlantType.P042TwinSunFlower: {
		PlantInfoAttribute.PlantName: "TwinSunFlower",
		PlantInfoAttribute.CoolTime: 50.0,
		PlantInfoAttribute.SunCost: 150,
		PlantInfoAttribute.PlantConditionResource : "res://resources/character_resource/plant_condition/000_common_purple.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_042_twin_sun_flower.tscn"
		},

	PlantType.P043GloomShroom: {
		PlantInfoAttribute.PlantName: "GloomShroom",
		PlantInfoAttribute.CoolTime: 50.0,
		PlantInfoAttribute.SunCost: 150,
		PlantInfoAttribute.PlantConditionResource : "res://resources/character_resource/plant_condition/000_common_purple.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_043_gloom_shroom.tscn"
		},

	PlantType.P044Cattail: {
		PlantInfoAttribute.PlantName: "Cattail",
		PlantInfoAttribute.CoolTime: 50.0,
		PlantInfoAttribute.SunCost: 225,
		PlantInfoAttribute.PlantConditionResource : "res://resources/character_resource/plant_condition/000_common_purple.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_044_cattail.tscn"
		},

	PlantType.P045WinterMelon: {
		PlantInfoAttribute.PlantName: "WinterMelon",
		PlantInfoAttribute.CoolTime: 50.0,
		PlantInfoAttribute.SunCost: 200,
		PlantInfoAttribute.PlantConditionResource : "res://resources/character_resource/plant_condition/000_common_purple.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_045_winter_melon.tscn"
		},

	PlantType.P046GoldMagnet: {
		PlantInfoAttribute.PlantName: "GoldMagnet",
		PlantInfoAttribute.CoolTime: 50.0,
		PlantInfoAttribute.SunCost: 50,
		PlantInfoAttribute.PlantConditionResource : "res://resources/character_resource/plant_condition/000_common_purple.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_046_gold_magnet.tscn"
		},

	PlantType.P047SpikeRock: {
		PlantInfoAttribute.PlantName: "SpikeRock",
		PlantInfoAttribute.CoolTime: 50.0,
		PlantInfoAttribute.SunCost: 125,
		PlantInfoAttribute.PlantConditionResource : "res://resources/character_resource/plant_condition/000_common_purple.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_047_spike_rock.tscn"
		},

	PlantType.P048CobCannon: {
		PlantInfoAttribute.PlantName: "CobCannon",
		PlantInfoAttribute.CoolTime: 50.0,
		PlantInfoAttribute.SunCost: 500,
		PlantInfoAttribute.PlantConditionResource : "res://resources/character_resource/plant_condition/048_cob_cannon.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_048_cob_cannon.tscn"
		},

	PlantType.P049PeaShooterDoubleReverse: {
		PlantInfoAttribute.PlantName: "PeaShooterDoubleReverse",
		PlantInfoAttribute.CoolTime: 7.5,
		PlantInfoAttribute.SunCost: 200,
		PlantInfoAttribute.PlantConditionResource : "res://resources/character_resource/plant_condition/000_common_plant_land.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_049_pea_shooter_double_reverse.tscn"
		},

	PlantType.P050LightningReed: {
		PlantInfoAttribute.PlantName: "LightningReed",
		PlantInfoAttribute.CoolTime: 5.0,
		PlantInfoAttribute.SunCost: 125,
		PlantInfoAttribute.PlantConditionResource: "res://resources/character_resource/plant_condition/000_common_plant_land.tres",
		PlantInfoAttribute.PlantScenes: "res://scenes/character/plant/plant_050_lightning_reed.tscn",
		},

	PlantType.P051Bloomerang: {
		PlantInfoAttribute.PlantName: "Bloomerang",
		PlantInfoAttribute.CoolTime: 5.0,
		PlantInfoAttribute.SunCost: 175,
		PlantInfoAttribute.PlantConditionResource: "res://resources/character_resource/plant_condition/000_common_plant_land.tres",
		PlantInfoAttribute.PlantScenes: "res://scenes/character/plant/plant_051_bloomerang.tscn",
		},

	PlantType.P052ElectricPeashooter: {
		PlantInfoAttribute.PlantName: "ElectricPeashooter",
		PlantInfoAttribute.CoolTime: 5.0,
		PlantInfoAttribute.SunCost: 200,
		PlantInfoAttribute.PlantConditionResource: "res://resources/character_resource/plant_condition/000_common_plant_land.tres",
		PlantInfoAttribute.PlantScenes: "res://scenes/character/plant/plant_052_electric_peashooter.tscn",
		},

	## 模仿者
	PlantType.P999Imitater:{
		PlantInfoAttribute.PlantName: "Imitater",
		PlantInfoAttribute.CoolTime: 50.0,
		PlantInfoAttribute.SunCost: 0,
		PlantInfoAttribute.PlantConditionResource :  "res://resources/character_resource/plant_condition/999_imitater.tres",
		PlantInfoAttribute.PlantScenes :  "res://scenes/character/plant/plant_999_imitater.tscn"
		},


	## 发芽
	PlantType.P1000Sprout:{
		PlantInfoAttribute.PlantName: "Sprout",
		PlantInfoAttribute.CoolTime: 7.5,
		PlantInfoAttribute.SunCost: 50,
		PlantInfoAttribute.PlantConditionResource :  "res://resources/character_resource/plant_condition/000_common_plant_land.tres",
		PlantInfoAttribute.PlantScenes :  "res://scenes/character/plant/plant_1000_sprout.tscn"
		},

	## 保龄球
	PlantType.P1001WallNutBowling: {
		PlantInfoAttribute.PlantName: "WallNutBowling",
		PlantInfoAttribute.CoolTime: 7.5,
		PlantInfoAttribute.SunCost: 50,
		PlantInfoAttribute.PlantConditionResource :  "res://resources/character_resource/plant_condition/000_common_plant_land.tres",
		PlantInfoAttribute.PlantScenes :  "res://scenes/character/plant/plant_1001_wall_nut_bowling.tscn"
		},
	PlantType.P1002WallNutBowlingBomb: {
		PlantInfoAttribute.PlantName: "WallNutBowlingBomb",
		PlantInfoAttribute.CoolTime: 7.5,
		PlantInfoAttribute.SunCost: 50,
		PlantInfoAttribute.PlantConditionResource :  "res://resources/character_resource/plant_condition/000_common_plant_land.tres",
		PlantInfoAttribute.PlantScenes :  "res://scenes/character/plant/plant_1002_wall_nut_bowling.tscn"
		},
	PlantType.P1003WallNutBowlingBig: {
		PlantInfoAttribute.PlantName: "WallNutBowlingBig",
		PlantInfoAttribute.CoolTime: 7.5,
		PlantInfoAttribute.SunCost: 50,
		PlantInfoAttribute.PlantConditionResource : "res://resources/character_resource/plant_condition/000_common_plant_land.tres",
		PlantInfoAttribute.PlantScenes : "res://scenes/character/plant/plant_1003_wall_nut_bowling.tscn"
		},
}


## Resolve registered plant scenes without exposing the registry's preload map.
func get_plant_scene(plant_type: int) -> PackedScene:
	return get_plant_info(plant_type, PlantInfoAttribute.PlantScenes) as PackedScene

## Public typed resource API stays unchanged; static values never trigger I/O.
func get_plant_info(plant_type: PlantType, info_attribute: PlantInfoAttribute) -> Variant:
	if not PlantInfo.has(plant_type):
		push_warning("Unregistered plant species: %s" % plant_type)
		return null
	return _attribute(PlantInfo[plant_type], info_attribute,
		[PlantInfoAttribute.PlantScenes, PlantInfoAttribute.PlantConditionResource])

#endregion

#region 僵尸
## 僵尸信息
const ZombieInfo = {
	ZombieType.Z001Norm:{
		ZombieInfoAttribute.ZombieName: "ZombieNorm",
		ZombieInfoAttribute.CoolTime: 0.0,
		ZombieInfoAttribute.SunCost: 50,
		ZombieInfoAttribute.ZombieScenes:"res://scenes/character/zombie/zombie_001_norm.tscn",
		ZombieInfoAttribute.ZombieRowType:CharacterRegistry.ZombieRowType.Both
	},
	ZombieType.Z002Flag:{
		ZombieInfoAttribute.ZombieName: "ZombieFlag",
		ZombieInfoAttribute.CoolTime: 0.0,
		ZombieInfoAttribute.SunCost: 50,
		ZombieInfoAttribute.ZombieScenes:"res://scenes/character/zombie/zombie_002_flag.tscn",
		ZombieInfoAttribute.ZombieRowType:CharacterRegistry.ZombieRowType.Both
	},
	ZombieType.Z003Cone:{
		ZombieInfoAttribute.ZombieName: "ZombieCone",
		ZombieInfoAttribute.CoolTime: 0.0,
		ZombieInfoAttribute.SunCost: 75,
		ZombieInfoAttribute.ZombieScenes:"res://scenes/character/zombie/zombie_003_cone.tscn",
		ZombieInfoAttribute.ZombieRowType:CharacterRegistry.ZombieRowType.Both
	},
	ZombieType.Z004PoleVaulter:{
		ZombieInfoAttribute.ZombieName: "ZombiePoleVaulter",
		ZombieInfoAttribute.CoolTime: 0.0,
		ZombieInfoAttribute.SunCost: 75,
		ZombieInfoAttribute.ZombieScenes:"res://scenes/character/zombie/zombie_004_pole_vaulter.tscn",
		ZombieInfoAttribute.ZombieRowType:CharacterRegistry.ZombieRowType.Land
	},
	ZombieType.Z005Bucket:{
		ZombieInfoAttribute.ZombieName: "ZombieBucket",
		ZombieInfoAttribute.CoolTime: 0.0,
		ZombieInfoAttribute.SunCost: 125,
		ZombieInfoAttribute.ZombieScenes:"res://scenes/character/zombie/zombie_005_bucket.tscn",
		ZombieInfoAttribute.ZombieRowType:CharacterRegistry.ZombieRowType.Both
	},

	ZombieType.Z006Paper:{
		ZombieInfoAttribute.ZombieName: "ZombiePaper",
		ZombieInfoAttribute.CoolTime: 0.0,
		ZombieInfoAttribute.SunCost: 125,
		ZombieInfoAttribute.ZombieScenes:"res://scenes/character/zombie/zombie_006_paper.tscn",
		ZombieInfoAttribute.ZombieRowType:CharacterRegistry.ZombieRowType.Land
	},
	ZombieType.Z007ScreenDoor:{
		ZombieInfoAttribute.ZombieName: "ZombieScreenDoor",
		ZombieInfoAttribute.CoolTime: 0.0,
		ZombieInfoAttribute.SunCost: 125,
		ZombieInfoAttribute.ZombieScenes:"res://scenes/character/zombie/zombie_007_screendoor.tscn",
		ZombieInfoAttribute.ZombieRowType:CharacterRegistry.ZombieRowType.Both
	},
	ZombieType.Z008Football:{
		ZombieInfoAttribute.ZombieName: "ZombieFootball",
		ZombieInfoAttribute.CoolTime: 0.0,
		ZombieInfoAttribute.SunCost: 175,
		ZombieInfoAttribute.ZombieScenes: "res://scenes/character/zombie/zombie_008_football.tscn",
		ZombieInfoAttribute.ZombieRowType:CharacterRegistry.ZombieRowType.Land
	},
	ZombieType.Z009Jackson:{
		ZombieInfoAttribute.ZombieName: "ZombieJackson",
		ZombieInfoAttribute.CoolTime: 0.0,
		ZombieInfoAttribute.SunCost: 300,
		ZombieInfoAttribute.ZombieScenes:"res://scenes/character/zombie/zombie_009_jackson.tscn",
		ZombieInfoAttribute.ZombieRowType:CharacterRegistry.ZombieRowType.Land
	},
	ZombieType.Z010Dancer:{
		ZombieInfoAttribute.ZombieName: "ZombieDancer",
		ZombieInfoAttribute.CoolTime: 0.0,
		ZombieInfoAttribute.SunCost: 50,
		ZombieInfoAttribute.ZombieScenes:"res://scenes/character/zombie/zombie_010_dancer.tscn",
		ZombieInfoAttribute.ZombieRowType:CharacterRegistry.ZombieRowType.Land
	},
	ZombieType.Z011Duckytube:{
		ZombieInfoAttribute.ZombieName: "ZombieDuckytube",
		ZombieInfoAttribute.CoolTime: 0.0,
		ZombieInfoAttribute.SunCost: 50,
		ZombieInfoAttribute.ZombieScenes:"res://scenes/character/zombie/zombie_011_duckytube.tscn",
		ZombieInfoAttribute.ZombieRowType:CharacterRegistry.ZombieRowType.Both
	},
	ZombieType.Z012Snorkle:{
		ZombieInfoAttribute.ZombieName: "ZombieSnorkle",
		ZombieInfoAttribute.CoolTime: 0.0,
		ZombieInfoAttribute.SunCost: 75,
		ZombieInfoAttribute.ZombieScenes:"res://scenes/character/zombie/zombie_012_snorkle.tscn",
		ZombieInfoAttribute.ZombieRowType:CharacterRegistry.ZombieRowType.Pool
	},
	ZombieType.Z013Zamboni:{
		ZombieInfoAttribute.ZombieName: "ZombieZamboni",
		ZombieInfoAttribute.CoolTime: 0.0,
		ZombieInfoAttribute.SunCost: 250,
		ZombieInfoAttribute.ZombieScenes:"res://scenes/character/zombie/zombie_013_zamboni.tscn",
		ZombieInfoAttribute.ZombieRowType:CharacterRegistry.ZombieRowType.Land
	},
	ZombieType.Z014Bobsled:{
		ZombieInfoAttribute.ZombieName: "ZombieBobsled",
		ZombieInfoAttribute.CoolTime: 0.0,
		ZombieInfoAttribute.SunCost: 200,
		ZombieInfoAttribute.ZombieScenes:"res://scenes/character/zombie/zombie_014_bobsled.tscn",
		ZombieInfoAttribute.ZombieRowType:CharacterRegistry.ZombieRowType.Land
	},
	ZombieType.Z015Dolphinrider:{
		ZombieInfoAttribute.ZombieName: "ZombieDolphinrider",
		ZombieInfoAttribute.CoolTime: 0.0,
		ZombieInfoAttribute.SunCost: 150,
		ZombieInfoAttribute.ZombieScenes:"res://scenes/character/zombie/zombie_015_dolphinrider.tscn",
		ZombieInfoAttribute.ZombieRowType:CharacterRegistry.ZombieRowType.Pool
	},
	ZombieType.Z016Jackbox:{
		ZombieInfoAttribute.ZombieName: "ZombieJackbox",
		ZombieInfoAttribute.CoolTime: 0.0,
		ZombieInfoAttribute.SunCost: 75,
		ZombieInfoAttribute.ZombieScenes:"res://scenes/character/zombie/zombie_016_jackbox.tscn",
		ZombieInfoAttribute.ZombieRowType:CharacterRegistry.ZombieRowType.Land
	},
	ZombieType.Z017Balloon:{
		ZombieInfoAttribute.ZombieName: "ZombieBallon",
		ZombieInfoAttribute.CoolTime: 0.0,
		ZombieInfoAttribute.SunCost: 75,
		ZombieInfoAttribute.ZombieScenes:"res://scenes/character/zombie/zombie_017_balloon.tscn",
		ZombieInfoAttribute.ZombieRowType:CharacterRegistry.ZombieRowType.Both
	},
	ZombieType.Z018Digger:{
		ZombieInfoAttribute.ZombieName: "ZombieDigger",
		ZombieInfoAttribute.CoolTime: 0.0,
		ZombieInfoAttribute.SunCost: 125,
		ZombieInfoAttribute.ZombieScenes:"res://scenes/character/zombie/zombie_018_digger.tscn",
		ZombieInfoAttribute.ZombieRowType:CharacterRegistry.ZombieRowType.Land
	},
	ZombieType.Z019Pogo:{
		ZombieInfoAttribute.ZombieName: "ZombiePogo",
		ZombieInfoAttribute.CoolTime: 0.0,
		ZombieInfoAttribute.SunCost: 125,
		ZombieInfoAttribute.ZombieScenes:"res://scenes/character/zombie/zombie_019_pogo.tscn",
		ZombieInfoAttribute.ZombieRowType:CharacterRegistry.ZombieRowType.Land
	},
	ZombieType.Z020Yeti:{
		ZombieInfoAttribute.ZombieName: "ZombieYeti",
		ZombieInfoAttribute.CoolTime: 0.0,
		ZombieInfoAttribute.SunCost: 100,
		ZombieInfoAttribute.ZombieScenes:"res://scenes/character/zombie/zombie_020_yeti.tscn",
		ZombieInfoAttribute.ZombieRowType:CharacterRegistry.ZombieRowType.Land
	},
	ZombieType.Z021Bungi:{
		ZombieInfoAttribute.ZombieName: "ZombieBungi",
		ZombieInfoAttribute.CoolTime: 0.0,
		ZombieInfoAttribute.SunCost: 125,
		ZombieInfoAttribute.ZombieScenes:"res://scenes/character/zombie/zombie_021_bungi.tscn",
		ZombieInfoAttribute.ZombieRowType:CharacterRegistry.ZombieRowType.Both
	},
	ZombieType.Z022Ladder:{
		ZombieInfoAttribute.ZombieName: "ZombieLadder",
		ZombieInfoAttribute.CoolTime: 0.0,
		ZombieInfoAttribute.SunCost: 150,
		ZombieInfoAttribute.ZombieScenes:"res://scenes/character/zombie/zombie_022_ladder.tscn",
		ZombieInfoAttribute.ZombieRowType:CharacterRegistry.ZombieRowType.Land
	},
	ZombieType.Z023Catapult:{
		ZombieInfoAttribute.ZombieName: "ZombieCatapult",
		ZombieInfoAttribute.CoolTime: 0.0,
		ZombieInfoAttribute.SunCost: 200,
		ZombieInfoAttribute.ZombieScenes:"res://scenes/character/zombie/zombie_023_catapult.tscn",
		ZombieInfoAttribute.ZombieRowType:CharacterRegistry.ZombieRowType.Land
	},
	ZombieType.Z024Gargantuar:{
		ZombieInfoAttribute.ZombieName: "ZombieGargantuar",
		ZombieInfoAttribute.CoolTime: 0.0,
		ZombieInfoAttribute.SunCost: 300,
		ZombieInfoAttribute.ZombieScenes:"res://scenes/character/zombie/zombie_024_gargantuar.tscn",
		ZombieInfoAttribute.ZombieRowType:CharacterRegistry.ZombieRowType.Land
	},
	ZombieType.Z025Imp:{
		ZombieInfoAttribute.ZombieName: "ZombieImp",
		ZombieInfoAttribute.CoolTime: 0.0,
		ZombieInfoAttribute.SunCost: 50,
		ZombieInfoAttribute.ZombieScenes:"res://scenes/character/zombie/zombie_025_imp.tscn",
		ZombieInfoAttribute.ZombieRowType:CharacterRegistry.ZombieRowType.Land
	},
	ZombieType.Z026AllStar:{
		ZombieInfoAttribute.ZombieName: "ZombieAllStar",
		ZombieInfoAttribute.CoolTime: 0.0,
		ZombieInfoAttribute.SunCost: 250,
		ZombieInfoAttribute.ZombieScenes:"res://scenes/character/zombie/zombie_026_all_star.tscn",
		ZombieInfoAttribute.ZombieRowType:CharacterRegistry.ZombieRowType.Land
	},
	ZombieType.Z027Explorer:{
		ZombieInfoAttribute.ZombieName: "ZombieExplorer",
		ZombieInfoAttribute.CoolTime: 0.0,
		ZombieInfoAttribute.SunCost: 150,
		ZombieInfoAttribute.ZombieScenes:"res://scenes/character/zombie/zombie_027_explorer.tscn",
		ZombieInfoAttribute.ZombieRowType:CharacterRegistry.ZombieRowType.Land
	},

	## 石像本体可在水陆格出现；破壳后沿用普通僵尸的水体适配。
	ZombieType.Z028StoneStatue:{
		ZombieInfoAttribute.ZombieName: "ZombieStoneStatue",
		ZombieInfoAttribute.CoolTime: 0.0,
		ZombieInfoAttribute.SunCost: 200,
		ZombieInfoAttribute.ZombieScenes:"res://scenes/character/zombie/zombie_stone_statue.tscn",
		ZombieInfoAttribute.ZombieRowType:CharacterRegistry.ZombieRowType.Both
	},

	## 陆地滚动的融合体；场景只在正式生成或展示该物种时加载。
	ZombieType.Z029LargeFusion:{
		ZombieInfoAttribute.ZombieName: "ZombieLargeFusion",
		ZombieInfoAttribute.CoolTime: 0.0,
		ZombieInfoAttribute.SunCost: 300,
		ZombieInfoAttribute.ZombieScenes:"res://scenes/character/zombie/zombie_029_large_fusion.tscn",
		ZombieInfoAttribute.ZombieRowType:CharacterRegistry.ZombieRowType.Land
	},

	## 穴居僵尸只在正式生成或预览时解析场景，保持启动期的轻量目录。
	ZombieType.Z030Troglobite:{
		ZombieInfoAttribute.ZombieName: "ZombieTroglobite",
		ZombieInfoAttribute.CoolTime: 0.0,
		ZombieInfoAttribute.SunCost: 200,
		ZombieInfoAttribute.ZombieScenes:"res://scenes/character/zombie/zombie_030_troglobite.tscn",
		ZombieInfoAttribute.ZombieRowType:CharacterRegistry.ZombieRowType.Land
	},

	## 冰壳是穴居僵尸生成小鬼时注入的实例状态，不另设全局资源或物种。
	ZombieType.Z031YetiImp:{
		ZombieInfoAttribute.ZombieName: "ZombieYetiImp",
		ZombieInfoAttribute.CoolTime: 0.0,
		ZombieInfoAttribute.SunCost: 50,
		ZombieInfoAttribute.ZombieScenes:"res://scenes/character/zombie/zombie_031_yeti_imp.tscn",
		ZombieInfoAttribute.ZombieRowType:CharacterRegistry.ZombieRowType.Land
	},

	## 猎人场景沿用惰性字符串路径，只在正式生成或预览时加载。
	ZombieType.Z032Hunter:{
		ZombieInfoAttribute.ZombieName: "ZombieHunter",
		ZombieInfoAttribute.CoolTime: 0.0,
		ZombieInfoAttribute.SunCost: 150,
		ZombieInfoAttribute.ZombieScenes:"res://scenes/character/zombie/zombie_032_hunter.tscn",
		ZombieInfoAttribute.ZombieRowType:CharacterRegistry.ZombieRowType.Land
	},

	## 滑雪场景沿用惰性字符串路径，只在正式生成或预览时加载。
	ZombieType.Z033Ski:{
		ZombieInfoAttribute.ZombieName: "ZombieSki",
		ZombieInfoAttribute.CoolTime: 0.0,
		ZombieInfoAttribute.SunCost: 125,
		ZombieInfoAttribute.ZombieScenes:"res://scenes/character/zombie/zombie_033_ski.tscn",
		ZombieInfoAttribute.ZombieRowType:CharacterRegistry.ZombieRowType.Land
	},

	## 只在指定波次或手动召唤进入战场，避免改变原版随机刷怪池。
	ZombieType.Z034Fighter:{
		ZombieInfoAttribute.ZombieName: "ZombieFighter",
		ZombieInfoAttribute.CoolTime: 0.0,
		ZombieInfoAttribute.SunCost: 250,
		ZombieInfoAttribute.ZombieScenes:"res://scenes/character/zombie/zombie_034_fighter.tscn",
		ZombieInfoAttribute.ZombieRowType:CharacterRegistry.ZombieRowType.Land
	},
	## 巨型三行载具，场景资源通过已有登记门面按需载入。
	ZombieType.Z038ArbiterX:{
		ZombieInfoAttribute.ZombieName: "ZombieArbiterX",
		ZombieInfoAttribute.CoolTime: 0.0,
		ZombieInfoAttribute.SunCost: 400,
		ZombieInfoAttribute.ZombieScenes:"res://scenes/character/zombie/zombie_038_arbiter_x.tscn",
		ZombieInfoAttribute.ZombieRowType:CharacterRegistry.ZombieRowType.Land
	},
	## 导弹炮塔通过现有场景门面按需实例化。
	ZombieType.Z039CannonTurret:{
		ZombieInfoAttribute.ZombieName: "ZombieCannonTurret",
		ZombieInfoAttribute.CoolTime: 0.0,
		ZombieInfoAttribute.SunCost: 350,
		ZombieInfoAttribute.ZombieScenes:"res://scenes/character/zombie/zombie_039_cannon_turret.tscn",
		ZombieInfoAttribute.ZombieRowType:CharacterRegistry.ZombieRowType.Land
	},
	## 悬停载具可在水陆格上方停驻，场景与帧图集由注册表按需加载。
	ZombieType.Z040TransportAirship:{
		ZombieInfoAttribute.ZombieName: "ZombieTransportAirship",
		ZombieInfoAttribute.CoolTime: 0.0,
		ZombieInfoAttribute.SunCost: 500,
		ZombieInfoAttribute.ZombieScenes:"res://scenes/character/zombie/zombie_040_transport_airship.tscn",
		ZombieInfoAttribute.ZombieRowType:CharacterRegistry.ZombieRowType.Both
	},
	## 火箭小鬼按需加载，供显式生成和图鉴展示。
	ZombieType.Z041RocketImp:{
		ZombieInfoAttribute.ZombieName: "ZombieRocketImp",
		ZombieInfoAttribute.CoolTime: 0.0,
		ZombieInfoAttribute.SunCost: 50,
		ZombieInfoAttribute.ZombieScenes:"res://scenes/character/zombie/zombie_041_rocket_imp.tscn",
		ZombieInfoAttribute.ZombieRowType:CharacterRegistry.ZombieRowType.Land
	},
	## 单独雪橇僵尸
	ZombieType.Z1001BobsledSingle:{
		ZombieInfoAttribute.ZombieName: "ZombieBobsledSingle",
		ZombieInfoAttribute.CoolTime: 0.0,
		ZombieInfoAttribute.SunCost: 50,
		ZombieInfoAttribute.ZombieScenes:"res://scenes/character/zombie/zombie_1001_bobsled_signle.tscn",
		ZombieInfoAttribute.ZombieRowType:CharacterRegistry.ZombieRowType.Land
	},
}

## 每种僵尸消耗的出怪战力，供自然波次和僵王放置技能只读访问，无需复制。[br]
## 未列出的类型不能参与按战力预算生成；战力不包含生成后衍生出的其他僵尸。
const ZombieSpawnPower: Dictionary[ZombieType, int] = {
	ZombieType.Z001Norm: 1,		# 普僵战力
	ZombieType.Z002Flag: 1,		# 旗帜战力
	ZombieType.Z003Cone: 2,		# 路障战力
	ZombieType.Z004PoleVaulter: 2,	# 撑杆战力
	ZombieType.Z005Bucket: 4,		# 铁桶战力

	ZombieType.Z006Paper: 2,		# 读报战力
	ZombieType.Z007ScreenDoor: 4,	# 铁门战力
	ZombieType.Z008Football: 7,	# 橄榄球战力
	ZombieType.Z009Jackson: 5,		# 舞王战力
	ZombieType.Z010Dancer: 1,		# 伴舞战力

	ZombieType.Z011Duckytube: 2,	# 鸭子游泳圈
	ZombieType.Z012Snorkle: 3,		# 潜水
	ZombieType.Z013Zamboni: 7,		# 冰车
	ZombieType.Z014Bobsled: 3,		# 滑雪四兄弟
	ZombieType.Z015Dolphinrider: 3,# 海豚僵尸

	ZombieType.Z016Jackbox: 3,		# 小丑
	ZombieType.Z017Balloon: 2,		# 气球
	ZombieType.Z018Digger: 4,		# 矿工
	ZombieType.Z019Pogo: 4,			# 跳跳
	ZombieType.Z020Yeti: 4,			# 雪人

	ZombieType.Z022Ladder: 4,		# 扶梯
	ZombieType.Z023Catapult: 5,		# 投篮
	ZombieType.Z024Gargantuar: 10,	# 伽刚特尔
	ZombieType.Z025Imp: 1,			# 小鬼
	ZombieType.Z026AllStar: 12,		# 全明星冲锋
	ZombieType.Z027Explorer: 3,		# 探险家火把
	ZombieType.Z028StoneStatue: 6,	# 固定石壳与内含普僵共用一个自然出怪名额。
	ZombieType.Z029LargeFusion: 12,	# 本体沿用全明星战力档，分裂出的普僵不追加到本体预算。
	ZombieType.Z030Troglobite: 6,	# 本体与入场携带的三只冰壳小鬼合并计入本次预算。
	ZombieType.Z031YetiImp: 1,		# 独立生成的小鬼沿用普通小鬼战力；随本体入场不重复计费。
	ZombieType.Z032Hunter: 4,		# 千点本体生命与远程冰封合并计入一次生成预算。
	ZombieType.Z033Ski: 3,		# 轻型本体与借冰飞跃共同计入一次生成预算。
	ZombieType.Z034Fighter: 7,	# 连发机枪和死亡自爆共享一份波次预算。
	ZombieType.Z038ArbiterX: 14,	# 三行碾压及后方90%减伤，共享单个敌人预算。
	ZombieType.Z039CannonTurret: 10,	# 炮车生命、四格爆炸和可拦截导弹的整项战力。
	ZombieType.Z040TransportAirship: 14,	# 运输舰本体与持续放飞的综合战力，后代不计入自然波次。
}

## 僵尸初始出怪权重；各出怪系统复制后独立调整，不修改公共基础数据。[br]
## 未列出的类型不参与此权重池，旗帜与小鬼等特殊生成仍由各自逻辑处理。
const ZombieSpawnWeights: Dictionary[ZombieType, int] = {
	ZombieType.Z001Norm: 4000,			# 普僵权重
	ZombieType.Z003Cone: 4000,			# 路障权重
	ZombieType.Z004PoleVaulter: 2000,	# 撑杆权重
	ZombieType.Z005Bucket: 3000,		# 铁桶权重

	ZombieType.Z006Paper: 1000,		# 读报权重
	ZombieType.Z007ScreenDoor: 3500,	# 铁门权重
	ZombieType.Z008Football: 2000,		# 橄榄球权重
	ZombieType.Z009Jackson: 1000,		# 舞王权重
	ZombieType.Z010Dancer: 4000,		# 伴舞权重

	ZombieType.Z012Snorkle: 2000,		# 潜水
	ZombieType.Z013Zamboni: 2000,		# 冰车
	ZombieType.Z014Bobsled: 2000,		# 滑雪四兄弟
	ZombieType.Z015Dolphinrider: 1500,	# 海豚僵尸

	ZombieType.Z016Jackbox: 1000,		# 小丑
	ZombieType.Z017Balloon: 2000,		# 气球
	ZombieType.Z018Digger: 1000,		# 矿工
	ZombieType.Z019Pogo: 1000,			# 跳跳
	ZombieType.Z020Yeti: 1,			# 雪人

	ZombieType.Z022Ladder: 1000,		# 扶梯
	ZombieType.Z023Catapult: 1500,	# 投篮
	ZombieType.Z024Gargantuar: 1500,	# 伽刚特尔
}


## 获取僵尸属性方法
func get_zombie_info(zombie_type: ZombieType, info_attribute: ZombieInfoAttribute) -> Variant:
	if zombie_type == ZombieType.Null or not ZombieInfo.has(zombie_type):
		return null
	return _attribute(ZombieInfo[zombie_type], info_attribute, [ZombieInfoAttribute.ZombieScenes])

#endregion

#region 僵王信息

#region 僵王
## 僵王使用独立类型，不参与普通僵尸的自然刷新列表；新增类型保持已有编号不变。
enum ZombieBossType {
	Null = 0,
	ZB001Doctor = 1,
	ZB002BlackGeneral = 2,
	ZB003WhiteDuke = 3,
	ZB004MingLantern = 4,
	ZB005Savior = 5,
	## 妇人（凯莱赫）的稳定 Boss 编号。
	ZB006Cailleach = 6,
	## 苍穹公爵的稳定 Boss 编号。
	ZB007SkyDuke = 7,
}

## 注册表只保存公共定义，血量和死亡状态由每局生成的僵王实例维护。
enum ZombieBossInfoAttribute {
	BossName,
	BossScenes,
	SunCost, ## 僵王卡每次成功召唤的阳光费用，取非负整数。
	CoolTime, ## 僵王卡每次成功召唤后的冷却时长，单位为游戏秒，0 表示无冷却。
}
#endregion

## 通过 Global.character_registry 查询场景，关卡只需保存 ZombieBossType。
const ZombieBossInfo = {
	ZombieBossType.ZB001Doctor: {
		ZombieBossInfoAttribute.BossName: "ZB001Doctor",
		ZombieBossInfoAttribute.BossScenes: "res://scenes/character/zombie_boss/zombie_boss_001_doctor.tscn",
		ZombieBossInfoAttribute.SunCost: 10000,
		ZombieBossInfoAttribute.CoolTime: 0,
	},
	ZombieBossType.ZB002BlackGeneral: {
		ZombieBossInfoAttribute.BossName: "ZB002BlackGeneral",
		ZombieBossInfoAttribute.BossScenes: "res://scenes/character/zombie_boss/zombie_boss_002_black_general.tscn",
		ZombieBossInfoAttribute.SunCost: 10000,
		ZombieBossInfoAttribute.CoolTime: 0,
	},
	ZombieBossType.ZB003WhiteDuke: {
		ZombieBossInfoAttribute.BossName: "ZB003WhiteDuke",
		ZombieBossInfoAttribute.BossScenes: "res://scenes/character/zombie_boss/zombie_boss_003_white_duke.tscn",
		ZombieBossInfoAttribute.SunCost: 10000,
		ZombieBossInfoAttribute.CoolTime: 0,
	},
	ZombieBossType.ZB004MingLantern: {
		ZombieBossInfoAttribute.BossName: "ZB004MingLantern",
		ZombieBossInfoAttribute.BossScenes: "res://scenes/character/zombie_boss/zombie_boss_004_ming_lantern.tscn",
		ZombieBossInfoAttribute.SunCost: 10000,
		ZombieBossInfoAttribute.CoolTime: 0,
	},
	ZombieBossType.ZB005Savior: {
		ZombieBossInfoAttribute.BossName: "ZB005Savior",
		ZombieBossInfoAttribute.BossScenes: "res://scenes/character/zombie_boss/zombie_boss_005_savior.tscn",
		ZombieBossInfoAttribute.SunCost: 10000,
		ZombieBossInfoAttribute.CoolTime: 0,
	},
	ZombieBossType.ZB006Cailleach: {
		ZombieBossInfoAttribute.BossName: "ZB006Cailleach",
		ZombieBossInfoAttribute.BossScenes: "res://scenes/character/zombie_boss/zombie_boss_006_cailleach.tscn",
		ZombieBossInfoAttribute.SunCost: 10000,
		ZombieBossInfoAttribute.CoolTime: 0,
	},
	ZombieBossType.ZB007SkyDuke: {
		ZombieBossInfoAttribute.BossName: "ZB007SkyDuke",
		ZombieBossInfoAttribute.BossScenes: "res://scenes/character/zombie_boss/zombie_boss_007_sky_duke.tscn",
		ZombieBossInfoAttribute.SunCost: 10000,
		ZombieBossInfoAttribute.CoolTime: 0,
	},
}


## 空类型或未注册类型返回 null，由生成入口决定如何处理，不回退成其他角色。
func get_zombie_boss_info(boss_type: ZombieBossType, info_attribute: ZombieBossInfoAttribute) -> Variant:
	if boss_type == ZombieBossType.Null or not ZombieBossInfo.has(boss_type):
		return null
	return _attribute(ZombieBossInfo[boss_type], info_attribute,
		[ZombieBossInfoAttribute.BossScenes])
#endregion
