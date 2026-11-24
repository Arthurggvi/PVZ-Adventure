## 一名救主的地表与空中表现。场景实例化时创建本轨独占的可写资源。
extends Node2D

## 疯狂的柱身材质和灯源池。
const Madness = preload("res://scripts/fx/savior_madness_effects.gd")
## 绝望的真实落点、流光和吸收余晕。
const Despair = preload("res://scripts/fx/savior_despair_effects.gd")
## 轨道的石面接触、冷却与裂隙。
const Ground = preload("res://scripts/fx/savior_madness_ground.gd")
## 战斗现有的共用光场。
const LightField = preload("res://scripts/battle/environment/battle_visibility_light_field.gd")

## 空中的六柱效果。
@onready var madness: Madness = $SaviorMadness
## 空中的四束流光。
@onready var despair: Despair = $SaviorDespair
## 地表与柱身在此场景内共享同一份 MultiMesh。
@onready var _ground: Ground = $MadnessContact

## [param battle] 和可空 [param field] 提供世界坐标与灯光；[param floor_layer] 在所有角色下方绘制接触面。
## [param base_track] 保留原场景地面层的绘制顺序；临时分身依原顺序追加。
func configure(battle: MainGameManager, field: LightField, floor_layer: CanvasLayer, base_track: bool) -> void:
	_ground.reparent(floor_layer, false)
	if base_track:
		floor_layer.move_child(_ground, 0)
	madness.ground = _ground
	madness.configure(battle, field)
	despair.configure(battle, field)

## 清空本次施法的灯与网格，使保留的首条轨道能再次被借用。
func clear() -> void:
	if not is_inside_tree():
		return # 已退出的轨道已从各效果自己的离树入口归还外部资源。
	if is_instance_valid(_ground) and is_instance_valid(madness):
		madness.clear()
	if is_instance_valid(despair):
		despair.clear()

## 地表挂在共用画布，删除轨道时由原持有者收回。
func _exit_tree() -> void:
	if is_instance_valid(_ground) and _ground.get_parent() != self:
		_ground.queue_free()
