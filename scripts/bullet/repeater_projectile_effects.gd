## 双发命中附加效果；伤害由原生弹体先结算，状态统一经过负面注册入口。
extends RefCounted
class_name RepeaterProjectileEffects

## 震撼弹的轻微击退距离，按发射地块横向间距的五分之一计算。
const SHOCK_CELLS: float = 0.2

## [param kind] 为变种；[param target] 为直击目标，可为空；[param position] 为世界命中点。
## [param shot] 是冻结来源；[param block_knockback] 是命中前尚存二类防具的快照。
static func impact(kind: StringName, target: Character000Base, position: Vector2,
		shot: RepeaterShotContext, block_knockback: bool = false) -> void:
	if shot == null or not shot.is_active() or not is_instance_valid(target):
		return
	match kind:
		&"frost":
			AdventurePlantNegativeEffects.apply(target, AdventurePlantNegativeEffects.Kind.FREEZE_CHARGE,
				shot.source_id, 1.0)
			AdventurePlantNegativeEffects.apply(target, AdventurePlantNegativeEffects.Kind.ICE_SLOW,
				shot.source_id, 5.0)
		&"ember":
			burn(target, shot)
		&"shock":
			AdventurePlantNegativeEffects.apply(target, AdventurePlantNegativeEffects.Kind.STUN,
				shot.source_id, 0.2)
			if not block_knockback and target is Zombie000Base and not target.is_death \
					and not target.is_hypno and not target.is_queued_for_deletion():
				(target as Zombie000Base).apply_projectile_knockback(shot.cell_pitch.x * SHOCK_CELLS)
		&"detonation":
			AdventurePlantNegativeEffects.apply(target, AdventurePlantNegativeEffects.Kind.DEGRADATION,
				shot.source_id, 0.1, 0.0, {"stackable": true, "family": &"repeater_detonation", "cap": 0.5})
			AdventurePlantNegativeEffects.apply(target, AdventurePlantNegativeEffects.Kind.DETONATION_CHARGE,
				shot.source_id, 1.0, 0.0, {"on_detonate": RepeaterAreaEffects.detonate.bind(shot)})
		&"hell", &"kaguya", &"hades":
			RepeaterAreaEffects.impact(kind, position, shot.lane, shot)

## [param target] 为火豆直击或实际溅射对象；[param shot] 提供独立于弹体寿命的来源。
static func burn(target: Character000Base, shot: RepeaterShotContext) -> void:
	if shot != null and shot.is_active():
		AdventurePlantNegativeEffects.apply(target, AdventurePlantNegativeEffects.Kind.BURN,
			shot.source_id, 1.0, 0.0, {"on_kill": _resolve_kill.bind(shot)})

## [param casualty] 为持续伤害实际死者；[param shot] 由绑定参数保留到状态结束。
static func _resolve_kill(casualty: Character000Base, shot: RepeaterShotContext) -> void:
	if shot != null:
		shot.on_kill(casualty)
