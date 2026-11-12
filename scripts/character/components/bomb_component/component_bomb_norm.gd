extends BombComponentBase
class_name BombComponentNorm
## 普通炸弹使用爆炸组件

## 爆炸表现，与伤害筛选独立触发。
@onready var bomb_effect: BombEffectBase = $BombEffect
## 冒险技能的可选结算入口；不设置时保留所有原版范围与伤害逻辑。
var damage_resolver: Callable

## 爆炸特效
func _start_bomb_fx():
	bomb_effect.activate_bomb_effect()

## 将原版区域交给通用植物爆炸结算，转职可接管几何范围和后续效果。
func _bomb_all_enemy():
	if damage_resolver.is_valid():
		damage_resolver.call()
		return
	CombatExplosion.resolve_plant_blast(area_2d_bomb.get_overlapping_areas(), owner.lane,
		bomb_lane, can_attack_zombie_status, resolved_damage(), is_cherry_bomb)
