extends AttackComponentBase
class_name AttackComponentZombieGargantuar
"""
攻击动画开始时,获取攻击对象
攻击造成伤害时,判断攻击对象是否死亡,若死亡,则攻击空气
若没死亡:
	攻击植物时,该植物格子所有植物被压扁
	攻击僵尸时,该僵尸受穿透伤害1800
"""
## 攻击动画开始时检测敌人
var enemy:Character000Base
## 攻击罐子
var pot:ScaryPot
## 攻击脑子
var brain:BrainOnZombieMode
signal signal_smash_completed(hit_target: Character000Base)

## 动画开始时,获取攻击对象
func anim_start():
	enemy = detect_component.enemy_can_be_attacked
	if is_instance_valid(detect_component.pot):
		pot = detect_component.pot
	elif is_instance_valid(detect_component.brain):
		brain = detect_component.brain

## 攻击一次，动画调用
func attack_once():
	if owner.is_action_suspended():
		return
	# 出手前锁定的植株可能在挥锤中途冻住，此时不结算下砸与命中衍生效果。
	if is_instance_valid(enemy) and enemy is Plant000Base and enemy.is_cold_frozen():
		return
	_attack_once_native()
	signal_smash_completed.emit(enemy)

func _attack_once_native() -> void:
	if is_instance_valid(pot):
		pot.open_pot_be_gargantuar()
		SoundManager.play_character_SFX("gargantuar_thump")
		return
	elif is_instance_valid(brain):
		brain.be_flattened()
		SoundManager.play_character_SFX("gargantuar_thump")
		return
	if is_instance_valid(enemy) and not owner.is_death:
		if enemy is Plant000Base:
			enemy.plant_cell.be_gargantuar_attack(owner)
		elif enemy is FriendlyBattleBarrier:
			enemy.be_zombie_eat(1800, owner)
		elif enemy is Zombie000Base:
			if owner.is_hypno:
				(owner as Zombie000Base).hit_as_hypnotized(enemy, 1800, true, true)
			else:
				enemy.be_attacked_bullet(1800,BulletRegistry.AttackMode.Penetration, true, true)

		SoundManager.play_character_SFX("gargantuar_thump")


## 修改速度
func owner_update_speed(_speed_product:float):
	pass
