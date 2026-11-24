## 冰壳设施的生命适配器；所有可消耗耐久委托给同一 PlantIceShell。
## 继承的 curr_hp 只作查询镜像，玩家攻击的溢出绝不进入植物本体或技能护甲。
extends HpComponent
class_name HpComponentIceShell

## 由代理在入树前显式绑定的唯一冰壳，不创建独立恢复或续时状态。
var _shell: PlantIceShell

## 绑定 [param shell] 的耐久通知；调用发生在场景入树前，生命面板仍由植物持有。
func bind_shell(shell: PlantIceShell) -> void:
	_shell = shell
	_shell.durability_changed.connect(_sync_current_hp)

## 补齐原生生命组件契约，但隐藏代理面板，避免同株出现两份冰壳数字。
func _ready() -> void:
	max_hp = PlantIceShell.MAX_HP
	is_can_look_hp = false
	hide()
	super()
	if _shell != null:
		curr_hp = _shell.current_hp()

## [param amount] 是唯一冰壳发布的耐久；同步查询镜像，不反向授予或恢复冰壳。
func _sync_current_hp(amount: int) -> void:
	if is_node_ready() and not owner_character.is_death:
		curr_hp = maxi(0, amount)

## 任何查询都读取唯一耐久；已退场代理即使后来重新冰封，也不能引用新壳参与战斗。
func get_all_hp() -> int:
	return _shell.current_hp() if _shell != null and not owner_character.is_death else 0

## 只报告冰壳自身的剩余比例，不使用植物本体或额外护甲。
func living_health_fraction() -> float:
	return float(get_all_hp()) / float(PlantIceShell.MAX_HP)

## [param amount] 为待结算伤害；返回当前冰壳是否会被击破。
func would_die_from_damage(amount: int) -> bool:
	return amount > 0 and get_all_hp() > 0 and amount >= get_all_hp()

## 冰壳不接受 [param _amount] 点治疗；重打雪球也不能借此恢复耐久。
func heal(_amount: int) -> int:
	return 0

## [param attack_value] 与 [param bonus_damage] 沿用统一减伤；[param bonus_cap] 限制附伤。
## [param _bullet_mode]、[param _is_drop_on_death]、[param _trigger_be_attack_SFX]、[param _is_drop_2] 保留父接口参数但不产生设施掉落。
## [param receipt] 只报告实际壳损失，本体损失恒为零且没有击杀；[param hit_scope] 按所属植物去重。
## 返回代理是否已结束；脚本处决仍沿用父类旁路，但只能清壳。
func Hp_loss(attack_value: int, _bullet_mode: BulletRegistry.AttackMode = BulletRegistry.AttackMode.Norm,
		_is_drop_on_death: Variant = true, _trigger_be_attack_SFX: bool = true, _is_drop_2: bool = true,
		bonus_damage: int = 0, bonus_cap: int = -1, receipt: Variant = null,
		hit_scope: CombatHitScope = null) -> bool:
	reset_hit_receipt(receipt, owner_character)
	if _shell == null or not _shell.is_active() or owner_character.is_death or owner_character.is_queued_for_deletion():
		return false
	var actual_owner: Character000Base = owner_character.combat_hit_owner() # 同一击不能同时扣宿主和代理这两个身份。
	if actual_owner == null:
		return false
	if hit_scope != null and not hit_scope.try_claim(actual_owner):
		if receipt is Dictionary:
			receipt["duplicate_hit"] = true
		return false
	if hit_scope != null and hit_scope.death_cause == CombatHitScope.DeathCause.FIRE:
		owner_character.cancel_ice()
		return owner_character.is_death
	var raw_damage: int = attack_value + maxi(0, bonus_damage) # 原始攻击事件只属于设施，不触发植物受击技能。
	var combat: bool = raw_damage > 0 and not _bypass_damage_block and not is_damage_immune() # 脚本处决不作为真实战斗损失。
	if combat:
		combat_attack_received.emit(raw_damage)
	var resolved: int = resolve_damage(attack_value, bonus_damage, bonus_cap) # 设施使用原生统一减伤规则，独立于植物技能护甲。
	var consumed: int = resolved - _shell.absorb(resolved) # 只记录壳实际消耗；余量在此终止，绝不调用植物 Hp_loss。
	if combat and consumed > 0:
		combat_health_lost.emit(consumed)
	if receipt is Dictionary:
		receipt["actual_loss"] = consumed if combat else 0
	signal_hp_loss.emit(get_all_hp(), false)
	return owner_character.is_death

## 直接生命调整也只能作用于冰壳。[param amount] 为损失，[param cause] 指定火焰时执行融冰。
## 不写植物生命、不伪造本体伤害事件，也不处理余量。
func apply_body_loss(amount: int, cause: CombatHitScope.DeathCause = CombatHitScope.DeathCause.NORMAL) -> void:
	if _shell == null or not _shell.is_active() or owner_character.is_death or owner_character.is_queued_for_deletion():
		return
	if cause == CombatHitScope.DeathCause.FIRE:
		owner_character.cancel_ice()
	else:
		_shell.absorb(maxi(0, amount))
