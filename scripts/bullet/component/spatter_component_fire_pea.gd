extends SpatterComponent
## 火豌豆实际造成的溅射伤害也能点燃探险家的火把。


## [param enemy] 溅射命中的有效目标。
## [param damage_per_enemy] 本次分摊的溅射伤害。
func attack_enemy(enemy: Character000Base, damage_per_enemy: int) -> void:
	# 实际扣血量用于区分有效火伤和免疫、格挡。
	var hp_before: int = enemy.hp_component.get_all_hp()
	enemy.be_attacked_bullet(damage_per_enemy, BulletRegistry.AttackMode.Penetration, true, false,
		0, -1, null, CombatHitScope.for_cause(CombatHitScope.DeathCause.FIRE))
	if is_instance_valid(enemy) and enemy is Zombie027Explorer \
		and enemy.hp_component.get_all_hp() < hp_before:
		enemy.relight_from_fire()
