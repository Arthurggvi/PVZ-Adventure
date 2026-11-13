## The only authority for zombie damage-mode routing. Calling HpComponentZombie
## resolves block/DR/shields once before entering; bowling/hammer specify their
## own impact payload. Effect-trigger callbacks can grant armor mid-hit.
extends RefCounted
class_name ZombieDamageRouter

## 对 [param hp] 按 [param bullet_mode] 分流 [param attack_value]；返回本体、一类、二类受击位标志。
## [param armor_multiplier] 只传给装备防具，保留穿透、背击与脚本强制扣血规则。
## [param receipt] 为可选本击回执，扣本体前记录实际容量，不受随后回调的治疗影响。
static func route(hp: HpComponentZombie, bullet_mode: BulletRegistry.AttackMode,
        attack_value: int, armor_multiplier: float = 1.0, receipt: Variant = null) -> int:
	var flag_loss: int = 0
	match bullet_mode:
		## 普通子弹
		BulletRegistry.AttackMode.Norm:
			if hp.curr_hp_armor2 > 0 and attack_value > 0:
				attack_value = hp._hit_armor2(attack_value, armor_multiplier)
				flag_loss |= 4
				if hp.is_damage_immune() and not hp._bypass_damage_block:
					attack_value = 0
				else:
					attack_value = hp._absorb_bonus_armor(attack_value)
			if hp.curr_hp_armor1 > 0 and attack_value > 0:
				attack_value = hp._hit_armor1(attack_value, armor_multiplier)
				flag_loss |= 2
				attack_value = hp._absorb_bonus_armor(attack_value)
			if hp.curr_hp > 0 and attack_value > 0:
				_lose_body(hp, attack_value, receipt)
				flag_loss |= 1

		## Penetration hits outer armor separately and preserves its original
		## inner-armor/body behavior; only the outer pool receives gear-specific DR.
		BulletRegistry.AttackMode.Penetration:
			if hp.curr_hp_armor2 > 0 and attack_value > 0:
				hp._hit_armor2(attack_value, armor_multiplier)
				flag_loss |= 4
				if hp.is_damage_immune() and not hp._bypass_damage_block:
					attack_value = 0
				else:
					attack_value = hp._absorb_bonus_armor(attack_value)
			if hp.curr_hp_armor1 > 0 and attack_value > 0:
				attack_value = hp._hit_armor1(attack_value, armor_multiplier)
				flag_loss |= 2
				attack_value = hp._absorb_bonus_armor(attack_value)
			if hp.curr_hp > 0 and attack_value > 0:
				_lose_body(hp, attack_value, receipt)
				flag_loss |= 1

		BulletRegistry.AttackMode.Real:
			if hp.curr_hp_armor1 > 0 and attack_value > 0:
				attack_value = hp._hit_armor1(attack_value, armor_multiplier)
				flag_loss |= 2
				attack_value = hp._absorb_bonus_armor(attack_value)
			if hp.curr_hp > 0 and attack_value > 0:
				_lose_body(hp, attack_value, receipt)
				flag_loss |= 1

		## Front/side bowling and hammer use one resolved payload per impact.
		## This avoids double block/DR on a hit that crosses multiple pools.
		BulletRegistry.AttackMode.BowlingFront:
			var front_amount := 1800
			if hp.curr_hp_armor2 > 0:
				front_amount = 400
			elif hp.curr_hp_armor1 > 0:
				front_amount = 800
			var front_damage := hp._absorb_bonus_armor(hp.resolve_damage(front_amount))
			if front_damage > 0:
				if hp.curr_hp_armor2 > 0:
					hp._hit_armor2(front_damage, armor_multiplier)
					flag_loss |= 4
				elif hp.curr_hp_armor1 > 0:
					hp._hit_armor1(front_damage, armor_multiplier)
					flag_loss |= 2
				else:
					_lose_body(hp, front_damage, receipt)
					flag_loss |= 1

		BulletRegistry.AttackMode.BowlingSide:
			var side_amount := 1800
			if hp.curr_hp_armor2 <= 0 and hp.curr_hp_armor1 > 0:
				side_amount = 800
			var side_damage := hp._absorb_bonus_armor(hp.resolve_damage(side_amount))
			if side_damage > 0:
				if hp.curr_hp_armor2 > 0:
					hp._hit_armor2(side_damage, armor_multiplier)
					flag_loss |= 4
				elif hp.curr_hp_armor1 > 0:
					hp._hit_armor1(side_damage, armor_multiplier)
					flag_loss |= 2
				else:
					_lose_body(hp, side_damage, receipt)
					flag_loss |= 1

		BulletRegistry.AttackMode.Hammer:
			var hammer_amount := 900 if hp.curr_hp_armor1 > 0 else hp.curr_hp
			var hammer_damage := hp._absorb_bonus_armor(hp.resolve_damage(hammer_amount))
			if hammer_damage > 0:
				if hp.curr_hp_armor1 > 0:
					hp._hit_armor1(hammer_damage, armor_multiplier)
					flag_loss |= 2
				elif hp.curr_hp > 0:
					_lose_body(hp, hammer_damage, receipt)
					flag_loss |= 1

	return flag_loss

## 从 [param hp] 本体扣除 [param amount]；[param receipt] 只记录本击真实可消耗的生命。
## 在生命属性发出死亡信号前冻结损失量，保留原有扣血与死亡顺序。
static func _lose_body(hp: HpComponentZombie, amount: int, receipt: Variant) -> void:
	if receipt is Dictionary:
		receipt["body_loss"] = int(receipt.get("body_loss", 0)) + mini(maxi(0, amount), hp.curr_hp)
	hp.curr_hp -= amount
