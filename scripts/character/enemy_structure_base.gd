## 可被植物攻击的敌方设施；独立于僵尸/Boss 登记、自然波次计数与奖励。
extends Character000Base
class_name EnemyStructureBase

## 场内设施组，全场攻击通过所属关卡过滤，避免跨场景伤害。
const GROUP: StringName = &"enemy_structures"

## 正常设施参与碰撞索敌，但不参与自然波次或僵尸掉落。
func ready_norm() -> void:
	super.ready_norm()
	add_to_group(GROUP)
	Global.config_service.signal_change_display_zombie_HP_label.connect(hp_component.change_display_HP_label)
	hp_component.change_display_HP_label(Global.config_service.display_zombie_HP_label)

## [param damage] 伤害值；[param mode] 伤害类型；[param drop] 掉落表现；[param sfx] 受击音效开关。
## [param bonus_damage] 同击附伤；[param bonus_cap] 为劣化放大后的附伤上限，-1 不限制。
func be_attacked_bullet(damage: int, mode: BulletRegistry.AttackMode = BulletRegistry.AttackMode.Norm,
		drop: bool = true, sfx: bool = true, bonus_damage: int = 0, bonus_cap: int = -1) -> void:
	if is_death or is_queued_for_deletion() or not hurt_box_component.is_enabling:
		return
	super.be_attacked_bullet(damage, mode, drop, sfx, bonus_damage, bonus_cap)

## 幂等死亡，先关闭受击并通知效果移除，再释放设施。
func character_death() -> void:
	if is_death:
		return
	hurt_box_component.disable_component(ComponentNormBase.E_IsEnableFactor.Death)
	super.character_death()
	queue_free()
