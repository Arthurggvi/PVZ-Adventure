## 原版泳池节点：保留昼夜素材、雨滴和粒子，水波改由通用 WaterSurfaceController 驱动。
extends Node2D
class_name Pool

## 原版水面雨滴图层。
@onready var pool_drop: ColorRect = $Pool/PoolDrop
## 池底精灵。
@onready var pool_base: Sprite2D = $PoolBase
## 池面精灵。
@onready var pool: Sprite2D = $Pool

## 白天池底贴图。
const POOL_BASE = preload("res://assets/image/background/pool_base.jpg")
## 白天水面贴图。
const POOL = preload("res://assets/image/background/pool.jpg")
## 夜间池底贴图。
const POOL_BASE_NIGHT = preload("res://assets/image/background/pool_base_night.jpg")
## 夜间水面贴图。
const POOL_NIGHT = preload("res://assets/image/background/pool_night.jpg")
## 原版白天水面参数。
const DAY_WATER_PROFILE = preload("res://resources/water/pool_day.tres")
## 原版夜间水面参数。
const NIGHT_WATER_PROFILE = preload("res://resources/water/pool_night.tres")

## 每场战斗持有一个水面控制器，不重复创建材质或叠加动画。
var water_surface: WaterSurfaceController

## 根据原版背景枚举选择素材与水面预设。
## [param game_para] 本局环境和下雨标记。
func init_pool(game_para: ResourceLevelData) -> void:
	var profile: WaterSurfaceProfile = DAY_WATER_PROFILE # 与当前昼夜背景配套的水面预设
	match game_para.game_BG:
		ConstLevelData.GameBg.Pool:
			pool_base.texture = POOL_BASE
			pool.texture = POOL
		ConstLevelData.GameBg.Fog:
			pool_base.texture = POOL_BASE_NIGHT
			pool.texture = POOL_NIGHT
			profile = NIGHT_WATER_PROFILE
	if not is_instance_valid(water_surface):
		water_surface = WaterSurfaceController.new()
		water_surface.name = "WaterSurface"
		add_child(water_surface)
	water_surface.configure_sprite(pool, profile)
	pool_drop.visible = game_para.is_rain
	if game_para.is_rain:
		var material: ShaderMaterial = pool_drop.material as ShaderMaterial # 原版雨滴 Shader
		if game_para.game_BG == ConstLevelData.GameBg.Pool:
			material.set_shader_parameter("drop_color", Color(0.0, 0.914, 0.941, 1.0))
		else:
			material.set_shader_parameter("drop_color", Color(0.0, 0.502, 0.773, 1.0))
