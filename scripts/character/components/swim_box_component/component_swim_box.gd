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

## 水线相对僵尸脚点的局部 Y，按该物种的泳池分件定位。
@export var waterline_offset: float = 2.0
## 水中死亡时仍完整绘制的白浪部件，拖入水中时与身体一起裁切。
@export var whitewater: Array[CanvasItem] = []

## 死亡或被水草抓住后，停止切换出入水姿态。
var swim_pose_locked: bool = false

## 改变游泳状态信号
signal signal_change_is_swimming(is_swimming:bool)

func _ready() -> void:
	water_contact_area.water_contact_changed.connect(_update_water_contact)

## 保留当前水体表现，拒绝后续出入水事件。普通游泳组件也会停止身体过渡。
func lock_swim_pose() -> void:
	swim_pose_locked = true

## 按僵尸脚点裁切身体。[param keep_whitewater] 为 true 时白浪保持在水面上绘制。
func clip_at_waterline(keep_whitewater: bool) -> void:
	# 水线从与身体同级的脚点取值；动画和补间只改变身体姿态。
	var waterline_y: float = shadow.to_global(Vector2(0, waterline_offset)).y
	if keep_whitewater:
		body.body_mask_start(waterline_y, whitewater)
	else:
		body.body_mask_start(waterline_y)

## 将已死亡的游泳僵尸切入 [param state]，按 [param frame_rate] 帧每秒播放 12 帧素材。
func play_water_death(state: StringName, frame_rate: float) -> void:
	var zombie: Zombie000Base = owner as Zombie000Base # 调用方使用共用的僵尸动画树结构。
	var animator: AnimComponentNorm = zombie.anim_component as AnimComponentNorm # 播放物种已有的死亡状态。
	var playback: AnimationNodeStateMachinePlayback = animator.animation_tree.get("parameters/StateMachine/playback") # 从当前姿态过渡到死亡。
	var clip_speed_path: String = "parameters/StateMachine/%s/TimeScale/scale" % state # 倍率只应用到死亡片段。
	zombie.move_component.update_move_factor(true, MoveComponent.E_MoveFactor.IsDeath)
	zombie.shadow.hide()
	clip_at_waterline(true)
	if zombie.signal_update_speed.is_connected(animator.owner_update_speed):
		zombie.signal_update_speed.disconnect(animator.owner_update_speed)
	animator.update_anim_speed_scale(1.0) # 初代的 0.2 秒过渡由外层时间推进。
	animator.animation_tree.set(clip_speed_path, frame_rate / 12.0)
	playback.travel(state)

## 仍存活时将聚合后的水体接触状态 [param swimming] 交给具体游泳表现。
func _update_water_contact(swimming: bool) -> void:
	if not swim_pose_locked:
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
