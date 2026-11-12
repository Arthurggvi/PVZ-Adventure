extends Plant000Base
class_name Plant001PeaShooterSingle

## 豌豆射手在战场、图鉴和卡面共用的转职外观。
const PromotionArt = preload("res://scripts/adventure/plant_art/adventure_peashooter_promotion_art.gd")

## 驱动原版射击和冷却的组件。
@onready var attack_component: AttackComponentBulletBase = $AttackComponent


## 用冻结的出战快照决定本株的外观，未转职时继续使用原始分件。
func _ready() -> void:
	super()
	if plant_type != CharacterRegistry.PlantType.P001PeaShooterSingle or plant_spawn_profile == null:
		return
	# 转职次数加一即显示阶级，星级与技能分支不参与换装。
	var rank: int = plant_spawn_profile.promotion_tier()
	if rank > 0:
		PromotionArt.apply_to_body($Body/BodyCorrect, rank)


## 初始化正常出战角色信号连接
func ready_norm_signal_connect():
	super()
	signal_update_speed.connect(attack_component.owner_update_speed)
