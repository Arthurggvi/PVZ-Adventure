extends HpComponent
class_name HpComponentZombie
## 僵尸血量组件
## Extra hit points from abilities are an independent pool, not a helmet.
var bonus_armor: int = 0
signal bonus_armor_changed(remaining: int)
var damage_transfer := DamageTransferEffect.new()
## Armor-only DR is applied after shared block/DR, and never on body/bonus armor.
var armor1_reduction := DamageReductionEffect.new()
## Fragile equipment (balloons) takes exactly one hit per received attack,
## regardless of attack power. Forced scripted removal retains native behavior.
var armor1_fixed_damage_per_hit := 0

func configure_fragile_armor1(hit_count: int) -> void:
	if hit_count <= 0:
		push_error("Fragile armor needs a positive hit count")
		return
	max_hp_armor1 = hit_count
	curr_hp_armor1 = hit_count
	armor1_fixed_damage_per_hit = 1
var armor2_reduction := DamageReductionEffect.new()

## [param raw] 是进入防具前的伤害容量，[param armor_multiplier] 仅放大防具损伤。
## 返回未放大的剩余容量，防具减伤与破甲增伤不会污染向内层溢出的伤害。
func _hit_armor2(raw: int, armor_multiplier: float = 1.0) -> int:
	if raw <= 0 or curr_hp_armor2 <= 0:
		return maxi(0, raw)
	var before: int = curr_hp_armor2 # 防具破坏前的实际生命池。
	var factor: float = _equipment_hit_factor(armor_multiplier) # 强制卸甲保留原生的一倍容量。
	var mitigated: int = raw if _bypass_damage_block else armor2_reduction.reduce_gear(roundi(float(raw) * factor)) # 仅本层消耗翻倍。
	if mitigated < before:
		curr_hp_armor2 = before - mitigated
		return 0
	curr_hp_armor2 = 0
	var retained: float = 1.0 if _bypass_damage_block else (1.0 - armor2_reduction.raw_reduction()) * factor # 每点原始容量能消耗的防具生命。
	return 0 if retained <= 0.0 else maxi(0, raw - ceili(float(before) / retained))

## [param raw] 与 [param armor_multiplier] 沿用二类防具的容量单位；气球固定命中次数不变。
func _hit_armor1(raw: int, armor_multiplier: float = 1.0) -> int:
	if raw <= 0 or curr_hp_armor1 <= 0:
		return maxi(0, raw)
	if armor1_fixed_damage_per_hit > 0 and not _bypass_damage_block:
		curr_hp_armor1 = maxi(0, curr_hp_armor1 - armor1_fixed_damage_per_hit)
		return 0 # The balloon absorbs the entire projectile even when it pops.
	var before: int = curr_hp_armor1 # 一类防具破坏前的实际生命。
	var factor: float = _equipment_hit_factor(armor_multiplier) # 仅数值防具接受额外消耗倍率。
	var mitigated: int = raw if _bypass_damage_block else armor1_reduction.reduce_gear(roundi(float(raw) * factor)) # 本体不接收该倍率。
	if mitigated < before:
		curr_hp_armor1 = before - mitigated
		return 0
	curr_hp_armor1 = 0
	var retained: float = 1.0 if _bypass_damage_block else (1.0 - armor1_reduction.raw_reduction()) * factor # 溢出仍以原始伤害容量计算。
	return 0 if retained <= 0.0 else maxi(0, raw - ceili(float(before) / retained))

## [param multiplier] 是战斗攻击携带的防具增伤；脚本强制操作与非法数值均回退一倍。
func _equipment_hit_factor(multiplier: float) -> float:
	return 1.0 if _bypass_damage_block or not is_finite(multiplier) else maxf(1.0, multiplier)

var _handling_transferred_hit := false
var _resolving_hit := false
var _armor_granted_in_hit := 0
## One positive attack attempt; emitted before reductions/shield routing.
signal received_attack(raw_damage: int)

func grant_bonus_armor(amount: int) -> void:
	if amount <= 0 or is_death:
		return
	bonus_armor += amount
	if _resolving_hit:
		_armor_granted_in_hit += amount
	bonus_armor_changed.emit(bonus_armor)

func _absorb_bonus_armor(amount: int) -> int:
	# Direct gear removal and forced HP loss must bypass temporary shields.
	if _bypass_damage_block:
		return maxi(0, amount)
	var absorbed: int = mini(bonus_armor, maxi(0, amount))
	if absorbed > 0:
		bonus_armor -= absorbed
		bonus_armor_changed.emit(bonus_armor)
	return maxi(0, amount - absorbed)

## 保护者对 [param amount] 点转移伤害独立结算减伤与护甲。[param mode] 为伤害类型。
## [param drop]、[param sfx] 和 [param extra_drop] 保留原伤害的表现开关。
## [param armor_multiplier] 同原始攻击传给保护者；返回本次实际击杀的僵尸。
## [param bonus_damage] 保留原目标命中前冻结的附伤；[param bonus_cap] 上限交给实际承伤者结算，-1 不限制。
## [param receipt] 可选回执字典，沿同一转移链报告保护者的实际损失。
## [param hit_scope] 原样传递结算群组，只在最终承伤者处消费资格。
func accept_transferred_hit(amount: int, mode: BulletRegistry.AttackMode,
		drop: bool, sfx: bool, extra_drop: bool, armor_multiplier: float = 1.0,
		bonus_damage: int = 0, bonus_cap: int = -1, receipt: Variant = null,
		hit_scope: CombatHitScope = null) -> Zombie000Base:
	var previous: bool = _handling_transferred_hit # 内层伤害不能提前解除外层保护者的转移锁。
	_handling_transferred_hit = true
	# 主伤与附伤作为同一个转移命中结算，不能重新采样保护者的已损生命。
	var casualty: Zombie000Base = apply_hit(amount, mode, drop, sfx, extra_drop, armor_multiplier, bonus_damage, bonus_cap, receipt, hit_scope)
	_handling_transferred_hit = previous
	return casualty

@onready var progress_bar_hp_armor_2: ProgressBar = %ProgressBarHpArmor2
@onready var label_hp_armor_2: Label = %LabelHpArmor2
@onready var progress_bar_hp_armor_1: ProgressBar = %ProgressBarHpArmor1
@onready var label_hp_armor_1: Label = %LabelHpArmor1

@onready var armor_2_control: Control = %Armor2Control
@onready var armor_1_control: Control = %Armor1Control
@onready var hp_control: Control = %HpControl

@export_group("防具血量")
@export var max_hp_armor1:int
var curr_hp_armor1:int:
	set(value):
		value = max(value, 0)
		curr_hp_armor1 = value

		label_hp_armor_1.text = str(curr_hp_armor1)
		if max_hp_armor1 == 0:
			progress_bar_hp_armor_1.value = 0
		else:
			progress_bar_hp_armor_1.value = float(curr_hp_armor1) / max_hp_armor1

		if value == 0:
			armor_1_control.visible = false
			signal_armor1_death.emit()


@export var max_hp_armor2:int
var curr_hp_armor2:int:
	set(value):
		value = max(value, 0)
		curr_hp_armor2 = value

		## 血量ui显示
		label_hp_armor_2.text = str(curr_hp_armor2)
		if max_hp_armor2 == 0:
			progress_bar_hp_armor_2.value = 0
		else:
			progress_bar_hp_armor_2.value = float(curr_hp_armor2) / max_hp_armor2
		if value == 0:
			armor_2_control.visible = false
			signal_armor2_death.emit()

## 一类防具受击音效
@export var sfx_be_attack_armor1 := SoundManagerClass.TypeBeAttackSFX.Null
## 二类防具受击音效
@export var sfx_be_attack_armor2 := SoundManagerClass.TypeBeAttackSFX.Null

## 临界值状态（0为满血状态，每次到下一个状态 +1）
var curr_hp_stage:= 0
var curr_hp_stage_armor1:= 0
var curr_hp_stage_armor2:= 0

## 死亡后每4帧掉一次血
var num_frame := 0

signal signal_hp_armor1_loss(curr_hp_armor1:int, curr_hp:int, is_no_drop:bool)
signal signal_hp_armor2_loss(curr_hp_armor2:int, curr_hp:int, is_no_drop:bool)

## 一类防具死亡（掉落）信号
signal signal_armor1_death
## 二类防具死亡（掉落）信号
signal signal_armor2_death

## 僵尸掉血信号（只有僵尸使用）,参数为损失的血量值
signal signal_zombie_hp_loss(all_loss_hp:int)

func _ready() -> void:
	super()
	self.curr_hp_armor1 = max_hp_armor1
	self.curr_hp_armor2 = max_hp_armor2

func _physics_process(delta: float) -> void:
	if owner_character.is_death and curr_hp != 0:
		num_frame = wrapi(num_frame + 1, 0, 4)
		if num_frame == 0:
			curr_hp -= max(int(delta * 50 * 4), 1)


func get_all_hp():
	return bonus_armor + curr_hp_armor1 + curr_hp_armor2 + curr_hp

## [param amount] 为强制调整量；[param mode] 决定分流，[param drop]、[param sfx]、[param extra_drop] 保留表现开关。
## 全量强制致死清除旧护甲及破甲回调中新授的护甲；部分卸甲和未死亡者保留原有护甲规则。
func apply_unblocked_loss(amount: int,
		mode: BulletRegistry.AttackMode = BulletRegistry.AttackMode.Norm,
		drop: bool = true, sfx: bool = true, extra_drop: bool = true) -> void:
	var full_elimination: bool = amount >= get_all_hp() # 必须在回调授甲前冻结本次是否请求清空全部血池。
	if full_elimination and bonus_armor > 0:
		bonus_armor = 0
		bonus_armor_changed.emit(0)
	super.apply_unblocked_loss(amount, mode, drop, sfx, extra_drop)
	if full_elimination and is_death and bonus_armor > 0:
		bonus_armor = 0 # 报纸破损可能在本次旁路中授甲；死亡后不能留下幽灵生命池。
		bonus_armor_changed.emit(0)


## [attack_value:int] 掉血的值
## [bullet_mode:AttackMode]: 伤害类型
## [is_drop_on_death:bool] 死亡时是否有掉落
## [trigger_be_attack_SFX:bool]:是否触发受击音效
## [is_drop_2:bool] 是否有掉落额外条件
## [param attack_value] 主伤；[param bullet_mode] 分流模式；[param is_drop_on_death] 致死掉落开关。
## [param trigger_be_attack_SFX] 受击音效；[param is_drop_2] 额外掉落条件。
## [param bonus_damage] 同击附伤；[param bonus_cap] 为劣化放大后的附伤上限，-1 不限制。
## [param receipt] 可选本次伤害回执，不持久保存到生命组件。
## [param hit_scope] 可选结算群组；没有传入时保持原有逐击行为。
func Hp_loss(attack_value:int, bullet_mode :BulletRegistry.AttackMode =BulletRegistry.AttackMode.Norm,
		is_drop_on_death=true, trigger_be_attack_SFX:=true, is_drop_2:=true,
		bonus_damage: int = 0, bonus_cap: int = -1, receipt: Variant = null,
		hit_scope: CombatHitScope = null):
	apply_hit(attack_value, bullet_mode, is_drop_on_death, trigger_be_attack_SFX, is_drop_2, 1.0, bonus_damage, bonus_cap, receipt, hit_scope)

## 结算 [param attack_value] 点伤害和 [param bullet_mode] 分流。
## [param is_drop_on_death]、[param trigger_be_attack_SFX] 和 [param is_drop_2] 沿用普通命中表现。
## [param armor_multiplier] 仅放大装备防具损伤，默认一倍；临时生命池与本体沿用原伤害。
## [param bonus_damage] 普通、穿透或背击携带的同击附伤；[param bonus_cap] 为放大后上限，-1 不限制。
## [param receipt] 可选字典，报告实际承伤者及损失；无敌、旧尸体和强制生命调整均记零战斗损失。
## [param hit_scope] 在保护者转移完成后、发出受击事件前消费，重复承伤回报零损失。
## 返回本次从存活变死亡的实际受击者；转移伤害时可返回保护者。
func apply_hit(attack_value: int, bullet_mode: BulletRegistry.AttackMode,
		is_drop_on_death: bool, trigger_be_attack_SFX: bool, is_drop_2: bool = true,
		armor_multiplier: float = 1.0, bonus_damage: int = 0, bonus_cap: int = -1,
		receipt: Variant = null, hit_scope: CombatHitScope = null) -> Zombie000Base:
	reset_hit_receipt(receipt, owner_character)
	# A protector receives the raw hit and re-runs its own block -> DR -> armor.
	# Scripted forced loss and nested transfers never redirect.
	if not _bypass_damage_block and not _handling_transferred_hit and not is_damage_immune() \
			and owner_character is Zombie000Base:
		var protector: Zombie000Base = damage_transfer.select_protector(owner_character)
		if protector != null:
			var protector_hp: HpComponentZombie = protector.hp_component as HpComponentZombie
			return protector_hp.accept_transferred_hit(attack_value, bullet_mode,
					is_drop_on_death, trigger_be_attack_SFX, is_drop_2, armor_multiplier, bonus_damage, bonus_cap, receipt, hit_scope)
	# 转移先决定真正承伤者；不能在原接触目标提前占用资格。
	if hit_scope != null and not hit_scope.try_claim(owner_character):
		return null
	# 只有本次受击产生的状态变化算击杀，已死亡的角色不重复回报。
	var was_alive: bool = not is_death
	var raw_damage: int = attack_value + maxi(0, bonus_damage) # 附伤不另发攻击事件，也不另扣一次脆弱防具。
	var combat_loss: bool = was_alive and raw_damage > 0 and not _bypass_damage_block # 只允许实际战斗血池损失产光，卸甲与处决不算。
	# Ordinary hits are mitigated once before any health-pool routing.
	if raw_damage > 0 and not is_death and not _bypass_damage_block:
		received_attack.emit(raw_damage)
	var ori_hp = get_all_hp()
	_resolving_hit = true
	_armor_granted_in_hit = 0
	# Balloons count actual projectile impacts, even when ordinary flat
	# block or damage reduction would round a positive impact to zero.
	# Immunity and a separate temporary shield still take precedence.
	var fragile_hit: bool = armor1_fixed_damage_per_hit > 0 \
			and curr_hp_armor1 > 0 and raw_damage > 0 \
			and not is_damage_immune() and not _bypass_damage_block
	if bullet_mode not in [BulletRegistry.AttackMode.BowlingFront,
			BulletRegistry.AttackMode.BowlingSide, BulletRegistry.AttackMode.Hammer]:
		var resolved: int = resolve_damage(attack_value, bonus_damage, bonus_cap) # 两部分共享一次减伤与护甲容量。
		if fragile_hit:
			resolved = maxi(1, resolved)
		attack_value = _absorb_bonus_armor(resolved)
	## 掉血标志, 1:本体 2:一类防具 4:二类防具
	var flag_loss: int = ZombieDamageRouter.route(self, bullet_mode, attack_value, armor_multiplier, receipt)

	var res_hp = get_all_hp()
	# A gear-loss trigger can award armor in this impact. The received-hit
	# signal reports damage suffered, not net resource gain.
	var loss_hp: int = maxi(0, ori_hp - res_hp + _armor_granted_in_hit)
	_resolving_hit = false
	_armor_granted_in_hit = 0
	if receipt is Dictionary:
		receipt["actual_loss"] = loss_hp if combat_loss else 0
		receipt["body_loss"] = int(receipt.get("body_loss", 0)) if combat_loss else 0
		receipt["casualty"] = owner_character if was_alive and is_death else null

	var is_drop = not (owner.is_death and not is_drop_on_death) and is_drop_2

	if combat_loss and loss_hp > 0:
		combat_health_lost.emit(loss_hp) # 已扣除减伤、过量伤害并补回本击新授护甲，保护者在自己的组件报告。
	## 组件发射掉血信号,僵尸发射僵尸掉血信号给僵尸管理器处理残半刷新
	signal_zombie_hp_loss.emit(loss_hp)
	if flag_loss & 1:
		signal_hp_loss.emit(curr_hp, is_drop)
		## 如果有受击音效并且触发受击音效
		if sfx_be_attack_body != SoundManager.TypeBeAttackSFX.Null and trigger_be_attack_SFX:
			SoundManager.play_be_attack_SFX(sfx_be_attack_body)

	if flag_loss & 2:
		signal_hp_armor1_loss.emit(curr_hp_armor1, curr_hp, is_drop)
		## 如果有受击音效并且触发受击音效
		if sfx_be_attack_armor1 != SoundManager.TypeBeAttackSFX.Null and trigger_be_attack_SFX:
			SoundManager.play_be_attack_SFX(sfx_be_attack_armor1)

	if flag_loss & 4:
		signal_hp_armor2_loss.emit(curr_hp_armor2, curr_hp, is_drop)
		## 如果有受击音效并且触发受击音效
		if sfx_be_attack_armor2 != SoundManager.TypeBeAttackSFX.Null and trigger_be_attack_SFX:
			SoundManager.play_be_attack_SFX(sfx_be_attack_armor2)
	return owner_character as Zombie000Base if was_alive and is_death else null

## 小僵尸大麻烦更新僵尸血量
func update_mini_zombie_hp():
	max_hp /= 2
	max_hp_armor1 /= 2
	max_hp_armor2 /= 2

	curr_hp = max_hp
	curr_hp_armor1 = max_hp_armor1
	curr_hp_armor2 = max_hp_armor2

