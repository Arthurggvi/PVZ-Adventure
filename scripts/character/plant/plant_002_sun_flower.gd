extends Plant000Base
class_name Plant002SunFlower

## 生产和掉落阳光的共享组件。
@onready var create_sun_component: CreateSunComponent = $CreateSunComponent
## 向日葵本体与阳光共用的外观定义。
const PromotionArt = preload("res://scripts/adventure/plant_art/adventure_sunflower_promotion_art.gd")

## 为本株设置本体和产出阳光共用的转职外观。
func _ready() -> void:
	super()
	var tier: int = PromotionArt.apply(self) # 只使用成功应用到本体的转职次数。
	create_sun_component.sun_visual_material = PromotionArt.sun_material_for_tier(tier)

func ready_norm() -> void:
	super()
	if is_zombie_mode:
		create_sun_component.disable_component(ComponentNormBase.E_IsEnableFactor.GameMode)

## 初始化正常出战角色信号连接
func ready_norm_signal_connect():
	super()
	signal_update_speed.connect(create_sun_component.owner_update_speed)


## 被僵尸啃食一次特殊效果,魅惑\大蒜\我是僵尸生产阳光
func _be_zombie_eat_once_special(_attack_zombie:Zombie000Base):
	if is_zombie_mode:
		create_sun_component._on_be_eat_once()

## 植物死亡
func character_death():
	if is_zombie_mode:
		create_sun_component._on_character_death()
	super()
