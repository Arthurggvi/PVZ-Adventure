## SceneRegistry 原有属性接口的唯一延迟加载目录；本层只持有路径和缓存。
## 所有资源通过公共属性按需获得，不复制战场或花园节点。
extends Node

## 固定身份到资源路径的只读映射，查询元数据不加载场景。
const PATHS := {
	&"PLANT_CELL_GARDEN": "res://scenes/garden/plant_cell_garden.tscn",
	&"GARDEN_SPEECH_BUBBLE": "res://scenes/garden/garden_speech_bubble.tscn",
	&"GARDEN_FLOWER_POT": "res://scenes/garden/garden_flower_pot.tscn",
	&"CRAZY_DAVE": "res://scenes/crazy_dave/crazy_dave.tscn",
	&"REMINDER_INFORMATION": "res://scenes/ui/reminder_information.tscn",
	&"COIN_DIAMOND": "res://scenes/item/game_scenes_item/drop/coin_diamond.tscn",
	&"COIN_GOLD": "res://scenes/item/game_scenes_item/drop/coin_gold.tscn",
	&"COIN_SILVER": "res://scenes/item/game_scenes_item/drop/coin_silver.tscn",
	&"PRESENT": "res://scenes/item/game_scenes_item/drop/present.tscn",
	&"CARD_CANDIDATE_CONTAINER": "res://scenes/ui/all_cards/card_candidate_container.tscn",
	&"PLANT_START_EFFECT": "res://scenes/item/game_scenes_item/plant_effect/plant_start_effect.tscn",
	&"PLANT_START_EFFECT_WATER": "res://scenes/item/game_scenes_item/plant_effect/plant_start_effect_water.tscn",
	&"DOOM_SHROOM_CRATER": "res://scenes/fx/doom_shroom_crater.tscn",
	&"TOMBSTONE": "res://scenes/item/game_scenes_item/tombstone.tscn",
	&"JACKSON_MANAGER": "res://scenes/character/components/jackson_manager.tscn",
	&"TROPHY": "res://scenes/item/game_scenes_item/trophy.tscn",
	&"ICE_EFFECT": "res://scenes/fx/ice_effect.tscn",
	&"SPLASH": "res://scenes/item/game_scenes_item/splash.tscn",
	&"FIRE": "res://scenes/fx/fire.tscn",
	&"BUTTER_SPLAT": "res://scenes/fx/butter_splat.tscn",
	&"SUN": "res://scenes/item/game_scenes_item/sun.tscn",
	&"DIRT_RISE_EFFECT": "res://scenes/character/item/dirt_rise_effect.tscn",
	&"LADDER": "res://scenes/item/game_scenes_item/ladder.tscn",
}
## 与角色注册表共用战斗租约协议，战外只由实际使用者持有场景。
const BattleScope = preload("res://scripts/autoload/global/battle_resource_scope.gd")
## 本注册表独立的战斗资源租约。
var _battle_scope := BattleScope.new()

## [param key] 为历史资源名称；无注册或解析失败返回 null。
func _scene(key: StringName) -> PackedScene:
	var path: String = PATHS.get(key, "") # 原有路径表仍是唯一身份来源。
	if path.is_empty():
		push_error("SceneRegistry: unregistered scene: " + str(key))
		return null
	var global_node: Node = get_node_or_null("/root/Global") # 允许启动期独立查询。
	var owner: Node = global_node.get("main_game") if global_node != null else null # 当前真实战斗根。
	var resource: PackedScene = _battle_scope.resolve(owner, path) as PackedScene # 共享现有资源。
	if resource == null:
		push_error("SceneRegistry: resource not found: " + path)
	return resource

## 花园植物格子：保留原属性名称，首次使用时解析对应资源。
var PLANT_CELL_GARDEN: PackedScene:
	get: return _scene(&"PLANT_CELL_GARDEN")

## 花园需求气泡：保留原属性名称，首次使用时解析对应资源。
var GARDEN_SPEECH_BUBBLE: PackedScene:
	get: return _scene(&"GARDEN_SPEECH_BUBBLE")

## 花园花盆：保留原属性名称，首次使用时解析对应资源。
var GARDEN_FLOWER_POT: PackedScene:
	get: return _scene(&"GARDEN_FLOWER_POT")

## 戴夫角色：保留原属性名称，首次使用时解析对应资源。
var CRAZY_DAVE: PackedScene:
	get: return _scene(&"CRAZY_DAVE")

## 提示弹窗：保留原属性名称，首次使用时解析对应资源。
var REMINDER_INFORMATION: PackedScene:
	get: return _scene(&"REMINDER_INFORMATION")

## 钻石实体：保留原属性名称，首次使用时解析对应资源。
var COIN_DIAMOND: PackedScene:
	get: return _scene(&"COIN_DIAMOND")

## 金币实体：保留原属性名称，首次使用时解析对应资源。
var COIN_GOLD: PackedScene:
	get: return _scene(&"COIN_GOLD")

## 银币实体：保留原属性名称，首次使用时解析对应资源。
var COIN_SILVER: PackedScene:
	get: return _scene(&"COIN_SILVER")

## 礼物实体：保留原属性名称，首次使用时解析对应资源。
var PRESENT: PackedScene:
	get: return _scene(&"PRESENT")

## 候选卡槽：保留原属性名称，首次使用时解析对应资源。
var CARD_CANDIDATE_CONTAINER: PackedScene:
	get: return _scene(&"CARD_CANDIDATE_CONTAINER")

## 陆地种植特效：保留原属性名称，首次使用时解析对应资源。
var PLANT_START_EFFECT: PackedScene:
	get: return _scene(&"PLANT_START_EFFECT")

## 水路种植特效：保留原属性名称，首次使用时解析对应资源。
var PLANT_START_EFFECT_WATER: PackedScene:
	get: return _scene(&"PLANT_START_EFFECT_WATER")

## 毁灭菇坑洞：保留原属性名称，首次使用时解析对应资源。
var DOOM_SHROOM_CRATER: PackedScene:
	get: return _scene(&"DOOM_SHROOM_CRATER")

## 原版墓碑：保留原属性名称，首次使用时解析对应资源。
var TOMBSTONE: PackedScene:
	get: return _scene(&"TOMBSTONE")

## 伴舞管理器：保留原属性名称，首次使用时解析对应资源。
var JACKSON_MANAGER: PackedScene:
	get: return _scene(&"JACKSON_MANAGER")

## 奖杯实体：保留原属性名称，首次使用时解析对应资源。
var TROPHY: PackedScene:
	get: return _scene(&"TROPHY")

## 冰冻特效：保留原属性名称，首次使用时解析对应资源。
var ICE_EFFECT: PackedScene:
	get: return _scene(&"ICE_EFFECT")

## 水花特效：保留原属性名称，首次使用时解析对应资源。
var SPLASH: PackedScene:
	get: return _scene(&"SPLASH")

## 火焰特效：保留原属性名称，首次使用时解析对应资源。
var FIRE: PackedScene:
	get: return _scene(&"FIRE")

## 黄油效果：保留原属性名称，首次使用时解析对应资源。
var BUTTER_SPLAT: PackedScene:
	get: return _scene(&"BUTTER_SPLAT")

## 阳光实体：保留原属性名称，首次使用时解析对应资源。
var SUN: PackedScene:
	get: return _scene(&"SUN")

## 出土特效：保留原属性名称，首次使用时解析对应资源。
var DIRT_RISE_EFFECT: PackedScene:
	get: return _scene(&"DIRT_RISE_EFFECT")

## 梯子实体：保留原属性名称，首次使用时解析对应资源。
var LADDER: PackedScene:
	get: return _scene(&"LADDER")
