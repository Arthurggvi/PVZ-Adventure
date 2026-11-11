extends Node2D
class_name SwimBoxComponent
## 僵尸游泳组件基类

@onready var shadow: Sprite2D = %Shadow
@onready var body: BodyCharacter = %Body
## 负责物理水域接触和相邻水域聚合的探测器。
@onready var water_contact_area: WaterContactArea = $Area2D

## 游泳时body变化
@export var body_change_swim:ResourceBodyChange

## 特殊水花位置(普通水花位置跟影子重叠,海豚僵尸使用)
@export var special_splash_pos_node:Node2D

## 所属僵尸死亡后停止触发新的游泳表现。
var owner_is_death := false

## 改变游泳状态信号
signal signal_change_is_swimming(is_swimming:bool)

func _ready() -> void:
	water_contact_area.water_contact_changed.connect(_update_water_contact)

func _on_owner_is_death():
	owner_is_death = true

## 仍存活时将聚合后的水体接触状态 [param swimming] 交给具体游泳表现。
func _update_water_contact(swimming: bool) -> void:
	if not owner_is_death:
		_on_water_contact_changed(swimming)


## 出现水花
func appear_splash():
	## 水花
	var splash = SceneRegistry.SPLASH.instantiate()
	splash.position = shadow.global_position - owner.get_parent().global_position + Vector2(0, 15)
	owner.get_parent().add_child.call_deferred(splash)

## 特殊位置水花
func appear_splash_special_pos():
	## 水花
	var splash = SceneRegistry.SPLASH.instantiate()
	splash.position = special_splash_pos_node.global_position - owner.get_parent().global_position + Vector2(0, 15)

	owner.get_parent().add_child.call_deferred(splash)


## 派生表现只处理聚合后的 [param swimming] 变化，禁止重写接触计数协议。
func _on_water_contact_changed(swimming: bool) -> void:
	signal_change_is_swimming.emit(swimming)
