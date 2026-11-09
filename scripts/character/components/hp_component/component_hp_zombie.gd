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

## Returns unmitigated overflow after a specific gear pool is consumed.
## The gear absorbs raw attack capacity according to its own reduction.
func _hit_armor2(raw: int) -> int:
	if raw <= 0 or curr_hp_armor2 <= 0:
		return maxi(0, raw)
	var before: int = curr_hp_armor2
	var mitigated: int = raw if _bypass_damage_block else armor2_reduction.reduce_gear(raw)
	if mitigated < before:
		curr_hp_armor2 = before - mitigated
		return 0
	curr_hp_armor2 = 0
	var retained: float = 1.0 if _bypass_damage_block else 1.0 - armor2_reduction.raw_reduction()
	return 0 if retained <= 0.0 else maxi(0, raw - ceili(float(before) / retained))

func _hit_armor1(raw: int) -> int:
	if raw <= 0 or curr_hp_armor1 <= 0:
		return maxi(0, raw)
	if armor1_fixed_damage_per_hit > 0 and not _bypass_damage_block:
		curr_hp_armor1 = maxi(0, curr_hp_armor1 - armor1_fixed_damage_per_hit)
		return 0 # The balloon absorbs the entire projectile even when it pops.
	var before: int = curr_hp_armor1
	var mitigated: int = raw if _bypass_damage_block else armor1_reduction.reduce_gear(raw)
	if mitigated < before:
		curr_hp_armor1 = before - mitigated
		return 0
	curr_hp_armor1 = 0
	var retained: float = 1.0 if _bypass_damage_block else 1.0 - armor1_reduction.raw_reduction()
	return 0 if retained <= 0.0 else maxi(0, raw - ceili(float(before) / retained))
var _handling_transferred_hit := false
var _resolving_hit := false
var _armor_granted_in_hit := 0

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

## A redirected hit goes through the protector's complete mitigation and armor routing.
func accept_transferred_hit(amount: int, mode: BulletRegistry.AttackMode,
		drop: bool, sfx: bool, extra_drop: bool) -> void:
	_handling_transferred_hit = true
	Hp_loss(amount, mode, drop, sfx, extra_drop)
	_handling_transferred_hit = false

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

## Forced elimination bypasses bonuses but must not leave a dead entity with
## phantom HP. Partial scripted gear removal still preserves the bonus pool.
func apply_unblocked_loss(amount: int,
		mode: BulletRegistry.AttackMode = BulletRegistry.AttackMode.Norm,
		drop: bool = true, sfx: bool = true, extra_drop: bool = true) -> void:
	if amount >= get_all_hp() and bonus_armor > 0:
		bonus_armor = 0
		bonus_armor_changed.emit(0)
	super.apply_unblocked_loss(amount, mode, drop, sfx, extra_drop)


## [attack_value:int] 掉血的值
## [bullet_mode:AttackMode]: 伤害类型
## [is_drop_on_death:bool] 死亡时是否有掉落
## [trigger_be_attack_SFX:bool]:是否触发受击音效
## [is_drop_2:bool] 是否有掉落额外条件
## return bool: 返回是否死亡
func Hp_loss(attack_value:int, bullet_mode :BulletRegistry.AttackMode =BulletRegistry.AttackMode.Norm, is_drop_on_death=true, trigger_be_attack_SFX:=true, is_drop_2:=true):
	# A protector receives the raw hit and re-runs its own block -> DR -> armor.
	# Scripted forced loss and nested transfers never redirect.
	if not _bypass_damage_block and not _handling_transferred_hit and not is_damage_immune() \
			and owner_character is Zombie000Base:
		var protector: Zombie000Base = damage_transfer.select_protector(owner_character)
		if protector != null:
			var protector_hp: HpComponentZombie = protector.hp_component as HpComponentZombie
			protector_hp.accept_transferred_hit(attack_value, bullet_mode,
					is_drop_on_death, trigger_be_attack_SFX, is_drop_2)
			return
	# Ordinary hits are mitigated once before any health-pool routing.
	var ori_hp = get_all_hp()
	_resolving_hit = true
	_armor_granted_in_hit = 0
	# Balloons count actual projectile impacts, even when ordinary flat
	# block or damage reduction would round a positive impact to zero.
	# Immunity and a separate temporary shield still take precedence.
	var fragile_hit: bool = armor1_fixed_damage_per_hit > 0 \
			and curr_hp_armor1 > 0 and attack_value > 0 \
			and not is_damage_immune() and not _bypass_damage_block
	if bullet_mode not in [BulletRegistry.AttackMode.BowlingFront,
			BulletRegistry.AttackMode.BowlingSide, BulletRegistry.AttackMode.Hammer]:
		var resolved: int = resolve_damage(attack_value)
		if fragile_hit:
			resolved = maxi(1, resolved)
		attack_value = _absorb_bonus_armor(resolved)
	## 掉血标志, 1:本体 2:一类防具 4:二类防具
	var flag_loss: int = ZombieDamageRouter.route(self, bullet_mode, attack_value)

	var res_hp = get_all_hp()
	# A gear-loss trigger can award armor in this impact. The received-hit
	# signal reports damage suffered, not net resource gain.
	var loss_hp: int = maxi(0, ori_hp - res_hp + _armor_granted_in_hit)
	_resolving_hit = false
	_armor_granted_in_hit = 0

	var is_drop = not (owner.is_death and not is_drop_on_death) and is_drop_2

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

## 小僵尸大麻烦更新僵尸血量
func update_mini_zombie_hp():
	max_hp /= 2
	max_hp_armor1 /= 2
	max_hp_armor2 /= 2

	curr_hp = max_hp
	curr_hp_armor1 = max_hp_armor1
	curr_hp_armor2 = max_hp_armor2

