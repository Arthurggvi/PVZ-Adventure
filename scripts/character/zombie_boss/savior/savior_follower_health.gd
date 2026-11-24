## 救主随从的生命组件；黑影只因接触植物或战场清理离场，所有生命伤害入口均拒绝扣血。
extends HpComponentZombie


## 保留普通血量组件的接口，隐藏黑影的血条并停用尸体扣血计时。
func _ready() -> void:
	super()
	is_can_look_hp = false
	hide()
	set_physics_process(false)


## 总是报告伤害免疫，保护与转伤等战斗机制可据此判断。
func is_damage_immune() -> bool:
	return true


## 拒绝僵尸伤害分流中的普通、穿透、保龄球和锤击等命中，返回空击杀者。
## [param _attack_value]、[param _bullet_mode] 与 [param _armor_multiplier] 为命中伤害参数。
## [param _is_drop_on_death]、[param _trigger_be_attack_SFX]、[param _is_drop_2] 为原命中表现选项。
## [param _bonus_damage] 与 [param _bonus_cap] 为同击附伤；[param _hit_scope] 不消耗实际命中资格。
## [param receipt] 在传入字典时写入零损失回执，供弹道和附带效果检查。
## [param _pre_resolved_damage] 供签名兼容，黑影仍免疫所有命中伤害。
func apply_hit(_attack_value: int, _bullet_mode: BulletRegistry.AttackMode,
		_is_drop_on_death: bool, _trigger_be_attack_SFX: bool, _is_drop_2: bool = true,
		_armor_multiplier: float = 1.0, _bonus_damage: int = 0, _bonus_cap: int = -1,
		receipt: Variant = null, _hit_scope: CombatHitScope = null, _pre_resolved_damage: int = -1) -> Zombie000Base:
	reset_hit_receipt(receipt, owner_character)
	return null


## 拒绝绕过普通格挡的处决与强制扣血。
## [param _amount]、[param _mode] 为请求的扣血量与分流模式。
## [param _drop]、[param _sfx]、[param _extra_drop] 为命中表现选项；[param _hit_scope] 为处决来源。
func apply_unblocked_loss(_amount: int, _mode: BulletRegistry.AttackMode = BulletRegistry.AttackMode.Norm,
		_drop: bool = true, _sfx: bool = true, _extra_drop: bool = true, _hit_scope: CombatHitScope = null) -> void:
	pass


## 拒绝直接扣除本体生命的 [param _amount] 及其 [param _cause]。
func apply_body_loss(_amount: int, _cause: CombatHitScope.DeathCause = CombatHitScope.DeathCause.NORMAL) -> void:
	pass
