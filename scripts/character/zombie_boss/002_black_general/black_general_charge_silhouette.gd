## 二阶段本体冲锋留下的常驻剪影，作为独立设施接受植物攻击。
extends EnemyStructureBase
class_name BlackGeneralChargeSilhouette

## 定格于冲锋途中的角色剪影。
@onready var _pose: BlackGeneralChargeTrail = $Body/Pose
## 缠绕剪影、持续翻卷的黑焰。
@onready var _mist: AnimatedSprite2D = $Body/Mist

## 在出战时登记为可被投手瞄准的设施。
func ready_norm() -> void:
	super.ready_norm()
	add_to_group(&"lobber_secondary_targets")

## 取 [param source] 当前的冲锋姿势，以 [param feet] 为脚下坐标生成飘动的剪影。
func imprint(source: Node2D, feet: Vector2) -> void:
	_pose.capture(source, feet)
	_mist.play(&"loop")
	_mist.frame = absi(roundi(global_position.x)) % _mist.sprite_frames.get_frame_count(&"loop")
	var drift_time: float = 1.05 + 0.06 * _mist.frame # 错开同批剪影的呼吸节奏。
	var drift := create_tween().set_loops().set_parallel(true) # 只移动表现节点，受击范围保持原位。
	drift.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	drift.tween_property(_pose, "position", Vector2(8.0, -15.0), drift_time)
	drift.tween_property(_pose, "modulate:a", 0.48, drift_time)
	drift.chain().tween_property(_pose, "position", Vector2.ZERO, drift_time)
	drift.parallel().tween_property(_pose, "modulate:a", 0.84, drift_time)
