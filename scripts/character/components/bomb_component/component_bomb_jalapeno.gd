## 唯一的火爆辣椒引爆入口，转职只接管原有伤害与表现派发。
extends BombComponentBase
class_name BombComponentJalapeno

## 拥有本组件的真实火爆辣椒。
var owner_plant: Plant021Jalapeno

## 缓存宿主；出生派发已在入树前保存转职。
func _ready() -> void:
	owner_plant = owner as Plant021Jalapeno

## 原版在此播放整行火焰；转职范围和表现由同一次结算派发。
func _start_bomb_fx():
	if owner_plant.promotion_rules.is_empty():
		EventBus.push_event("jalapeno_bomb_effect", [owner_plant.row_col.x])

## 在原生引信内结算一次。战局条件不成立时沿用原版三事件。
func _bomb_all_enemy():
	if not owner_plant.promotion_rules.is_empty():
		if AdventureJalapenoBlast.try_detonate(owner_plant, can_attack_zombie_status):
			return
		EventBus.push_event("jalapeno_bomb_effect", [owner_plant.row_col.x])
	EventBus.push_event("jalapeno_bomb_lane_zombie", [owner_plant.row_col.x, resolved_damage()])
	EventBus.push_event("jalapeno_bomb_item_lane", [owner_plant.row_col.x])

