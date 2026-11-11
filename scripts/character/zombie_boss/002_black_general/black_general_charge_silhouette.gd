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
	var ink := BlackGeneralChargeTrail.make_ink(1.20, feet.x) # 轮廓先在黑焰中聚拢。
	_pose.material = ink
	ink.set_shader_parameter(&"dissolve", 0.68)
	var form := create_tween() # 短促成形后保留原有的飘动节奏。
	form.tween_method(BlackGeneralChargeTrail.set_dissolve.bind(ink), 0.68, 0.0, 0.32) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_mist.play(&"loop")
	_mist.frame = absi(roundi(global_position.x)) % _mist.sprite_frames.get_frame_count(&"loop")
	var drift_time: float = 1.05 + 0.06 * _mist.frame # 错开同批剪影的呼吸节奏。
	var drift := create_tween().set_loops().set_parallel(true) # 只移动表现节点，受击范围保持原位。
	drift.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	drift.tween_property(_pose, "position", Vector2(8.0, -15.0), drift_time)
	drift.tween_property(_pose, "modulate:a", 0.48, drift_time)
	drift.chain().tween_property(_pose, "position", Vector2.ZERO, drift_time)
	drift.parallel().tween_property(_pose, "modulate:a", 0.84, drift_time)

## 击破时立即按设施规则退出索敌，冻结姿势和冲击圈交由关卡继续播放。
func character_death() -> void:
	if is_death:
		return
	var battlefield := get_parent() as Node2D # 剪影根节点移除后仍持有演出。
	if is_instance_valid(battlefield) and not battlefield.is_queued_for_deletion():
		_pose.shed(battlefield, z_index + 1)
		BlackGeneralShadowBurst.erupt(battlefield, global_position, z_index + 2, 1.14)
	hide()
	super.character_death()
