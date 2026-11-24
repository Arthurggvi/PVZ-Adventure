extends AttackComponentBulletBase
class_name AttackComponentBulletPultBase
## 投手类子弹攻击组件

## 最后一个目标敌人位置
var last_target_enemy_global_pos :Vector2
## 起手锁定的敌方进攻线；蓄力期间浮台可能已经带着投手进入另一行。
var _aimed_lane: int = -1
var last_target_enemy:Character000Base
## Optional cross-lane targeting strategy; default retains native detection.
var target_override: Callable
## 每次攻击时,先更新最前面敌人
## 攻击间隔后触发执行攻击
func _on_bullet_attack_cd_timer_timeout() -> void:
	last_target_enemy = _choose_pult_target()
	#print(last_target_enemy)
	if is_instance_valid(last_target_enemy):
		last_target_enemy_global_pos = last_target_enemy.hurt_box_component.global_position
		_aimed_lane = last_target_enemy.lane if last_target_enemy.lane >= 0 else owner.lane
		# 在这里调用实际攻击逻辑
		animation_tree.set(attack_para, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## 投手优先越过普通障碍攻击有效敌人；只有无其他目标时才清理墓碑。
func _choose_pult_target() -> Character000Base:
	if target_override.is_valid():
		return target_override.call() as Character000Base
	var best: Character000Base = null
	for target in detect_component.get_all_enemy_can_be_attacked():
		if target.is_in_group(&"lobber_secondary_targets"):
			continue
		if best == null or target.hurt_box_component.global_position.x < best.hurt_box_component.global_position.x:
			best = target
	return best if is_instance_valid(best) else detect_component.update_first_enemy()

func get_bullet_paras(marker_2d_bullet_glo_pos:Vector2, ray_direction:Vector2) -> Dictionary[Bullet000NormBase.E_InitParasAttr,Variant]:
	var bullet_paras = super(marker_2d_bullet_glo_pos, ray_direction)
	if is_instance_valid(last_target_enemy):
		bullet_paras[Bullet000NormBase.E_InitParasAttr.Enemy] = last_target_enemy
	if owner is Plant000Base and _aimed_lane >= 0:
		# 抛物线飞向锁定目标，炮口仍取发射帧的真实坐标；目标消失时飞向最后一次瞄准点。
		bullet_paras[Bullet000NormBase.E_InitParasAttr.BulletLane] = last_target_enemy.lane \
			if is_instance_valid(last_target_enemy) and last_target_enemy.lane >= 0 else _aimed_lane
	bullet_paras[Bullet000NormBase.E_InitParasAttr.EnemyGloPos] = last_target_enemy_global_pos
	return bullet_paras
