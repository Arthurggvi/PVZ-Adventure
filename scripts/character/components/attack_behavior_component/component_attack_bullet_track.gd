extends AttackComponentBulletBase
class_name AttackComponentBulletTrack
## 追踪子弹攻击行为

"""
全屏攻击植物攻击时
if 前面 200 有敌人:
	攻击前面最靠近自身敌人
else:
	攻击全局检测组件的敌人
"""

var detect_component_global:DetectComponent


## 全局攻击组件不与自身的检测组件信号连接,与全局攻击信号连接
func detect_component_init():
	if is_instance_valid(Global.main_game):
		bullets = Global.main_game.bullets
		detect_component_global = Global.main_game.detect_component_global
		detect_component_global.signal_can_attack.connect(update_is_attack_factors.bind(true, E_IsAttackFactors.RayEnemy))
		detect_component_global.signal_not_can_attack.connect(update_is_attack_factors.bind(false, E_IsAttackFactors.RayEnemy))

		## 每次启用组件,重新检测是否有需要攻击的敌人
		detect_component_global.enable_component(ComponentNormBase.E_IsEnableFactor.Global)


func get_bullet_paras(marker_2d_bullet_glo_pos:Vector2, ray_direction:Vector2) -> Dictionary[Bullet000NormBase.E_InitParasAttr,Variant]:
	var bullet_paras = super(marker_2d_bullet_glo_pos, ray_direction)
	bullet_paras[Bullet000NormBase.E_InitParasAttr.Enemy] = get_enemy()
	return bullet_paras

## 生成子弹时优先返回前方目标，找不到时使用全局选敌。两处都无有效目标时返回 null。
func get_enemy()->Character000Base:
	var local_target: Character000Base = detect_component.update_first_enemy() # 前方只执行一次排序。
	if is_instance_valid(local_target):
		return local_target
	if not is_instance_valid(detect_component_global):
		return null
	var global_target: Character000Base = detect_component_global.update_enemy_track_bullet() # 沿用全局检测组件的锁定规则。
	return global_target if is_instance_valid(global_target) else null
