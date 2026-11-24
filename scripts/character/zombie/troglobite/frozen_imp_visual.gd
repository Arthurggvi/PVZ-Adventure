## 只拼合原图的后冰层、小鬼静帧与前冰层；六阶段随实际冰甲损失切换。
extends Node2D
class_name FrozenImpVisual

## 完整冰壳贴图以脚点为中心的横向半宽，单位为角色缩放前的像素。
const ICE_HALF_WIDTH: float = 40.0
## 各损伤阶段在基础六百点冰甲上的累计损伤阈值。
const DAMAGE_STAGES: Array[int] = [0, 120, 240, 360, 450, 540]
## 原图半尺寸前层，完整保留对应阶段像素。
const FRONT_IMAGES: Array[Texture2D] = [
	preload("res://assets/adventure/zombies/troglobite/ice_blocks/front_0.png"),
	preload("res://assets/adventure/zombies/troglobite/ice_blocks/front_1.png"),
	preload("res://assets/adventure/zombies/troglobite/ice_blocks/front_2.png"),
	preload("res://assets/adventure/zombies/troglobite/ice_blocks/front_3.png"),
	preload("res://assets/adventure/zombies/troglobite/ice_blocks/front_4.png"),
	preload("res://assets/adventure/zombies/troglobite/ice_blocks/front_5.png")]
## 原图半尺寸后层；按共同原图脚点保持右下对齐。
const BACK_IMAGES: Array[Texture2D] = [
	preload("res://assets/adventure/zombies/troglobite/ice_blocks/back_0.png"),
	preload("res://assets/adventure/zombies/troglobite/ice_blocks/back_1.png"),
	preload("res://assets/adventure/zombies/troglobite/ice_blocks/back_2.png"),
	preload("res://assets/adventure/zombies/troglobite/ice_blocks/back_3.png"),
	preload("res://assets/adventure/zombies/troglobite/ice_blocks/back_4.png"),
	preload("res://assets/adventure/zombies/troglobite/ice_blocks/back_5.png")]
## 后层各阶段相对脚点的原图左上角偏移，单位显示像素。
const BACK_OFFSETS: Array[Vector2] = [Vector2(-51, -160), Vector2(-51, -158),
	Vector2(-51, -158), Vector2(-51, -158), Vector2(-34, -158), Vector2(-22, -158)]
## 所有前层共用的底部中心脚点偏移。
const FRONT_OFFSET: Vector2 = Vector2(-49, -156)
## 绘制顺序中的背部冰层。
@onready var _back: Sprite2D = $BackIce
## 复用原待机首帧的小鬼，位于两层冰之间。
@onready var _imp: Sprite2D = $FrozenImp
## 绘制顺序中的透明前冰层。
@onready var _front: Sprite2D = $FrontIce
## 当前显示的阶段；-1 表示尚未安装任何冰壳。
var _stage: int = -1

## [param health] 提供实际冰甲比例，[param source] 提供同一小鬼的原图待机首帧和对齐。
func show_armor(health: HpComponentZombie, source: AnimatedSprite2D) -> void:
	_imp.texture = source.sprite_frames.get_frame_texture(&"frozen", 0)
	_imp.transform = source.transform
	_imp.centered = source.centered
	_imp.offset = source.offset
	_imp.flip_h = source.flip_h
	_imp.flip_v = source.flip_v
	source.hide()
	show()
	refresh_armor(health)

## [param health] 的等阶冰甲按比例映射到原始六百点阶段，零甲由根节点负责破冰。
func refresh_armor(health: HpComponentZombie) -> void:
	var damage: int = maxi(0, health.max_hp_armor1 - health.curr_hp_armor1) # 实际损失，避免比例浮点误差错过整点阈值。
	var stage: int = 0 # 尚未跨过任何损伤阈值时使用完整冰壳。
	for index: int in range(1, DAMAGE_STAGES.size()): # 每次受击可跨过多个阶段，直接显示实际剩余阶段。
		var threshold: int = roundi(float(DAMAGE_STAGES[index]) * float(health.max_hp_armor1) / 600.0) # 仅映射当前等阶护甲。
		if damage >= threshold:
			stage = index
	if stage == _stage:
		return
	_stage = stage
	_back.texture = BACK_IMAGES[stage]
	_back.offset = BACK_OFFSETS[stage]
	_front.texture = FRONT_IMAGES[stage]
	_front.offset = FRONT_OFFSET

## 隐藏整个冰壳，恢复 [param source]；不创建新角色，也不修改原动作或生命状态。
func hide_armor(source: AnimatedSprite2D) -> void:
	hide()
	source.show()
