## 临时友方障碍，复用角色受击框和生命组件。障碍跨行，不占种植格。
extends Character000Base
class_name FriendlyBattleBarrier

## 活动障碍登记。僵尸检测只在有障碍时检查拦截顺序。
const GROUP: StringName = &"friendly_battle_barriers"

## 返回障碍是否仍可挡路和承伤。死亡事件发出时已停止拦截。
func is_intercepting() -> bool:
	return not is_death and not is_queued_for_deletion() and hurt_box_component.is_enabling

## [param zombie] 必须是由外向内接近这道障碍的地面敌人。
func can_intercept(zombie: Zombie000Base) -> bool:
	return is_intercepting() and not zombie.is_hypno and not zombie.is_death \
		and zombie.curr_be_attack_status == Zombie000Base.E_BeAttackStatusZombie.IsNorm \
		and not zombie.move_component.is_forced_airborne() \
		and zombie.global_position.x >= global_position.x - 8.0

## [param _world_y] 是本次碰撞在世界空间的纵坐标，可供派生障碍定位受击表现。
func note_contact(_world_y: float) -> void:
	pass

## 将 [param attack_value] 点啃食或撞击交给共享生命池；[param attacker] 提供接触位置。
func be_zombie_eat(attack_value: int, attacker: Zombie000Base):
	if can_intercept(attacker):
		note_contact(attacker.hurt_box_component.global_position.y - 30.0)
		hp_component.Hp_loss(attack_value, BulletRegistry.AttackMode.Penetration, false, false)

## 将 [param attack_value] 与可选的 [param bonus_damage] 点 [param bullet_mode] 伤害交给共享生命池。
## [param bonus_cap] 为附伤上限。[param receipt] 返回真实损失，[param hit_scope] 携带攻击范围和死因。
## [param _is_drop] 和 [param _trigger_be_attack_sfx] 在障碍上无效；障碍由自身演出提供反馈。
func be_attacked_bullet(attack_value: int, bullet_mode: BulletRegistry.AttackMode = BulletRegistry.AttackMode.Norm,
		_is_drop: bool = true, _trigger_be_attack_sfx: bool = true, bonus_damage: int = 0, bonus_cap: int = -1,
		receipt: Variant = null, hit_scope: CombatHitScope = null):
	HpComponent.reset_hit_receipt(receipt, self)
	if is_intercepting():
		hp_component.Hp_loss(attack_value, bullet_mode, false, false, false, bonus_damage, bonus_cap, receipt, hit_scope)

## [param _attacker] 的每次实际伤害由生命组件提供反馈；障碍没有普通角色的身体贴图。
func be_zombie_eat_once(_attacker: Zombie000Base):
	pass
