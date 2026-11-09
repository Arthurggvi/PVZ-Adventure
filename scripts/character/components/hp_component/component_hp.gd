extends Node2D
class_name HpComponent

## 单次伤害的通用固定格挡，普通生命与僵尸护甲共用同一入口。
var damage_block := DamageBlockEffect.new()
## Applied after fixed block and before all armor/HP routing.
var damage_reduction := DamageReductionEffect.new()
## Strongest degradation wins; never add two sources by summation.
var degradation_fraction: float = 0.0

func apply_degradation(fraction: float) -> void:
	var next_value: float = maxf(degradation_fraction, maxf(0.0, fraction))
	if is_equal_approx(next_value, degradation_fraction):
		return
	degradation_fraction = next_value
	if is_instance_valid(owner_character) and is_instance_valid(owner_character.body):
		owner_character.body.set_other_color(BodyCharacter.E_ChangeColors.Degradation,
			Color(0.55, 0.57, 0.58) if next_value > 0.0 else Color.WHITE)

## Damage dealt by a degraded entity. At >=100% reduction, damage is zero.
func outgoing_damage(amount: int) -> int:
	return maxi(0, roundi(float(amount) * maxf(0.0, 1.0 - degradation_fraction)))
## Timed immunity sources coexist with existing scripted invulnerability.
var _immunity_sources: Dictionary[int, bool] = {}
## 角色控制的无敌窗口；直接生命调整仍可通过专用旁路执行。
var damage_immune: bool = false
## 直接处决/存档恢复等非战斗扣血绕过格挡，避免改变原有语义。
var _bypass_damage_block: bool = false

## 所属角色引用，用于按角色类型和初始化模式决定血条显示规则。
@onready var owner_character: Character000Base = owner

## 血量比例进度条；当前值按 curr_hp / max_hp 更新。
@onready var progress_bar_hp: ProgressBar = %ProgressBarHp
## 当前血量的数字标签，与 curr_hp 的写入同步更新。
@onready var label_hp: Label = %LabelHp

## 角色满血值，也是初始化血量和血条比例的分母，场景需配置为正数。
@export var max_hp:int
## 本体受击音效
@export var sfx_be_attack_body :SoundManagerClass.TypeBeAttackSFX= SoundManagerClass.TypeBeAttackSFX.Null

## 是否可以查看血条(norm正常出战角色可以)
var is_can_look_hp:=true
## 角色是否死亡，判断是否发射死亡信号
var is_death := false

## 死亡判定阈值；当前血量不高于该值时首次触发死亡信号，默认 0。
var death_hp:int = 0
## 当前生命值；写入时限制为非负数、刷新 UI，并在达到阈值时触发死亡。
var curr_hp:int:
	# value 是调用方写入该属性的新值，需经过下方处理再更新内部状态。
	set(value):
		value = max(value, 0)
		curr_hp = value
		label_hp.text = str(curr_hp)
		progress_bar_hp.value = float(curr_hp) / max_hp

		## 如果血量小于死亡血量临界值,并且角色还未死亡时
		if value <= death_hp and not is_death:
			is_death = true
			## 角色死亡
			signal_hp_component_death.emit()


## 血量损失信号(curr_hp:当前血量值),给血量变化组件(僵尸\坚果\南瓜)使用
signal signal_hp_loss(curr_hp:int, is_drop:bool)
## 血量组件检测到死亡信号
signal signal_hp_component_death

func _ready() -> void:
	damage_block.changed.connect(_on_damage_block_changed)
	curr_hp = max_hp
	## 出战角色连接信号，显示血量
	if owner_character.character_init_type == Character000Base.E_CharacterInitType.IsNorm:
		if owner_character is Plant000Base:
			visible = Global.config_service.display_plant_HP_label
			Global.config_service.signal_change_display_plant_HP_label.connect(change_display_HP_label)

		elif owner_character is Zombie000Base or owner_character is ZB000Base:
			visible = Global.config_service.display_zombie_HP_label
			Global.config_service.signal_change_display_zombie_HP_label.connect(change_display_HP_label)

		#if self is HpComponentZombie:
			#visible = Global.config_service.display_zombie_HP_label
			#Global.config_service.signal_change_display_zombie_HP_label.connect(change_display_HP_label)
#
		#else:
			#visible = Global.config_service.display_plant_HP_label
			#Global.config_service.signal_change_display_plant_HP_label.connect(change_display_HP_label)
	else:
		is_can_look_hp = false
		visible = false

## [param value] 用户配置中的血条可见开关；角色允许显示血量时才应用。
func change_display_HP_label(value:bool):
	if is_can_look_hp:
		visible = value

## [param new_death_hp] 新的死亡血量阈值，达到或低于该值时触发死亡判定。
func set_death_hp(new_death_hp:int):
	self.death_hp = new_death_hp

## Fresh combat-instance maximum health; does not change persistent plant data.
func set_spawn_max_health(new_max: int) -> void:
	if new_max <= 0:
		push_error("Combat health maximum must be positive")
		return
	max_hp = new_max
	# Before scene-tree entry, _ready initializes current HP and its UI.
	if is_node_ready():
		curr_hp = new_max

func get_all_hp():
	return curr_hp

## Reusable HP restoration: clamp to the active combat maximum and notify
## observers without inventing damage or allowing resurrection.
func heal(amount: int) -> int:
	if amount <= 0 or is_death or owner_character.is_death:
		return 0
	var before: int = curr_hp
	curr_hp = mini(max_hp, curr_hp + amount)
	var restored: int = curr_hp - before
	if restored > 0:
		signal_hp_loss.emit(curr_hp, false)
	return restored

## attack_value(int): 掉血的值
## bullet_mode(AttackMode): 伤害类型
## trigger_be_attack_SFX:=true:是否触发受击音效
## [is_drop_on_death:bool] 死亡时是否有掉落
## [is_drop_2:bool] 是否有掉落额外条件
## return bool: 返回是否死亡
## [param attack_value] 本次攻击扣除的生命值，具体伤害规则由生命组件处理。
## [param _bullet_mode] 攻击类型参数；当前基础生命组件直接扣血，未按类型分支处理。
## [param is_drop_on_death] 本次伤害导致死亡时是否允许掉落表现。
## [param trigger_be_attack_SFX] 是否播放本次受击音效，false 时只处理扣血及相关信号。
## [param is_drop_2] 掉落的额外允许条件，需与死亡掉落选项同时满足。
func Hp_loss(attack_value:int, _bullet_mode:BulletRegistry.AttackMode =BulletRegistry.AttackMode.Norm, is_drop_on_death=true, trigger_be_attack_SFX:=true, is_drop_2:=true):
	attack_value = resolve_damage(attack_value)
	curr_hp -= attack_value
	# 本次血量变化是否允许触发掉落表现，由死亡掉落选项和额外条件共同决定。
	var is_drop = not (owner.is_death and not is_drop_on_death) and is_drop_2
	signal_hp_loss.emit(curr_hp, is_drop)

	## 如果有受击音效并且触发受击音效
	if sfx_be_attack_body != SoundManager.TypeBeAttackSFX.Null and trigger_be_attack_SFX:
		SoundManager.play_be_attack_SFX(sfx_be_attack_body)

	return curr_hp == 0

## 掉血死亡
##[is_drop:bool]是否有掉落body
## [param is_drop] 是否允许本次伤害触发掉落表现。
func Hp_loss_death(is_drop:=true):
	apply_unblocked_loss(get_all_hp(), BulletRegistry.AttackMode.Norm, is_drop, false)


## 非战斗生命调整，供卸甲、处决和存档恢复使用；保留护甲分流及原有死亡/掉落信号。
## [param amount] 调整量；[param mode] 分流类型；[param drop] 致死掉落；[param sfx] 音效；[param extra_drop] 额外掉落开关。
func apply_unblocked_loss(amount: int, mode: BulletRegistry.AttackMode = BulletRegistry.AttackMode.Norm,
		drop: bool = true, sfx: bool = true, extra_drop: bool = true) -> void:
	var previous: bool = _bypass_damage_block # 保存嵌套调用前的状态，避免回调覆盖外层上下文。
	_bypass_damage_block = true
	Hp_loss(amount, mode, drop, sfx, extra_drop)
	_bypass_damage_block = previous


## [param damage] 原始伤害；普通生命与护甲子类分别在各自分流前调用一次。
func resolve_damage(damage: int) -> int:
	if _bypass_damage_block:
		return maxi(0, damage)
	if is_damage_immune():
		return 0
	return damage_reduction.reduce(damage_block.reduce(maxi(0, roundi(float(damage) * (1.0 + degradation_fraction)))))

func set_immunity_source(source_id: int, enabled: bool) -> void:
	if enabled:
		_immunity_sources[source_id] = true
	else:
		_immunity_sources.erase(source_id)

func is_damage_immune() -> bool:
	return damage_immune or not _immunity_sources.is_empty()


## [param amount] 有效格挡；独立染色通道避免与冰冻、受击和阶段颜色互相覆盖。
func _on_damage_block_changed(amount: int) -> void:
	if is_instance_valid(owner_character) and is_instance_valid(owner_character.body):
		owner_character.body.set_other_color(BodyCharacter.E_ChangeColors.DamageBlock,
			Color(0.72, 1.0, 0.96) if amount > 0 else Color.WHITE)
