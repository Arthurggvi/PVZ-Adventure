## 导弹耐久沿用僵尸受击入口，每次有效命中最多扣一点。
extends HpComponentZombie

## [param damage] 为本击主伤，[param bonus_damage] 为同击附伤。
## [param bonus_cap] 限制放大后的附伤，负值表示不限。强制扣血沿用原生处决规则。
func resolve_damage(damage: int, bonus_damage: int = 0, bonus_cap: int = -1) -> int:
	var resolved: int = super(damage, bonus_damage, bonus_cap) # 先沿用格挡、减伤和免疫判定。
	return resolved if _bypass_damage_block else mini(resolved, 1)
