## 唯一的火爆辣椒引爆入口，转职只接管原有伤害与表现派发。
extends BombComponentBase
class_name BombComponentJalapeno

## 拥有本组件的真实火爆辣椒。
var owner_plant: Plant021Jalapeno

## 缓存宿主；出生派发已在入树前保存转职。
func _ready() -> void:
	owner_plant = owner as Plant021Jalapeno

## 主爆瞬间产生一次以纵向为主的短震；普通整行火焰在此播放，转职火焰由结算派发。
func _start_bomb_fx():
	EventBus.push_event(MainGameCamera.SHAKE_EVENT, [Vector2(4.0, 7.0), 0.22])
	if owner_plant.promotion_rules.is_empty():
		_play_native_lane()

## 保留普通辣椒的整行范围；缺少正式地格时仍沿用事件入口。
func _play_native_lane() -> void:
	var cell: PlantCell = owner_plant.plant_cell # 世界地格仅提供视觉位置，不参与本函数的伤害结算。
	if is_instance_valid(cell) and cell.board != null:
		for lane_cell: PlantCell in cell.board.row_cells(owner_plant.lane): # 稀疏行只显示实际存在的地块。
			JalapenoFireVisual.spawn_cell(lane_cell, owner_plant.row_col.y)
	else:
		EventBus.push_event("jalapeno_bomb_effect", [owner_plant.lane])

## 在原生引信内结算一次。战局条件不成立时沿用原版三事件。
func _bomb_all_enemy():
	if not owner_plant.promotion_rules.is_empty():
		if AdventureJalapenoBlast.try_detonate(owner_plant, can_attack_zombie_status):
			return
		_play_native_lane()
	EventBus.push_event("jalapeno_bomb_lane_zombie", [owner_plant.lane, resolved_damage(), boss_blast_damage_cap()])
	EventBus.push_event("jalapeno_bomb_item_lane", [owner_plant.lane])

