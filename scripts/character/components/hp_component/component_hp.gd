extends Node2D
class_name HpComponent

## 单次伤害的通用固定格挡，普通生命与僵尸护甲共用同一入口。
var damage_block := DamageBlockEffect.new()
## Applied after fixed block and before all armor/HP routing.
var damage_reduction := DamageReductionEffect.new()
## 原有不可叠加劣化的最强强度；永久保留，0.05 表示增伤及减攻各 5%。
var degradation_fraction: float = 0.0
## 可叠加劣化的独立累计强度；不改写或被原有不可叠加通道覆盖。
var stacked_degradation_fraction: float = 0.0

## [param fraction] 本次非负劣化比例；非有限值与非正数不生效。
## [param stackable] 为 true 时仅累加独立通道，否则保持原有取最强值规则。
## 两种通道均持续至本次角色结束，最终战斗修正相加。
func apply_degradation(fraction: float, stackable: bool = false) -> void:
	if not is_finite(fraction) or fraction <= 0.0:
		return
	# 当前请求只读取所选通道，旧劣化与叠加劣化不会互相吞掉。
	var current: float = stacked_degradation_fraction if stackable else degradation_fraction
	# 叠加按百分点相加；不可叠加效果仍只接受更强的来源。
	var next_value: float = current + fraction if stackable else maxf(current, fraction)
	if not is_finite(next_value) or is_equal_approx(next_value, current):
		return
	if stackable:
		stacked_degradation_fraction = next_value
	else:
		degradation_fraction = next_value
	if is_instance_valid(owner_character) and is_instance_valid(owner_character.body):
		owner_character.body.set_other_color(BodyCharacter.E_ChangeColors.Degradation,
			Color(0.55, 0.57, 0.58) if total_degradation_fraction() > 0.0 else Color.WHITE)

## 返回两种独立劣化通道共同产生的比例，仅用于结算和表现，不反写任一通道。
func total_degradation_fraction() -> float:
	return degradation_fraction + stacked_degradation_fraction

## [param amount] 修正前的输出伤害；总劣化达到 100% 时输出降至零，永不产生负伤害。
func outgoing_damage(amount: int) -> int:
	return maxi(0, roundi(float(amount) * maxf(0.0, 1.0 - total_degradation_fraction())))
## 当前生效的限时无敌来源，按来源 ID 记录，可与脚本无敌叠加。
var _immunity_sources: Dictionary[int, bool] = {}
## 角色控制的无敌窗口；直接生命调整仍可通过专用旁路执行。
var damage_immune: bool = false:
	set(value): # value 为脚本设置的无敌开关。
		damage_immune = value
		_update_damage_immunity_tint()
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
## 本次确实收到的战斗攻击，含被护甲吸收部分；不包括脚本强制处决。
signal combat_attack_received(raw_damage: int)
## 本次真实损失的本体生命，已扣除减伤、护甲和单次伤害上限。
signal combat_hp_damaged(amount: int)

func _ready() -> void:
	damage_block.changed.connect(_on_damage_block_changed)
	# 所属角色就绪后才能使用其 Body 引用，补同步入树前设置的无敌状态。
	owner_character.ready.connect(_update_damage_immunity_tint, CONNECT_ONE_SHOT)
	owner_character.signal_character_death.connect(_update_damage_immunity_tint)
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
	# 保留原始攻击事件，护甲和格挡不能将“正在被攻击”伪装成脱战。
	var combat: bool = attack_value > 0 and not _bypass_damage_block and not is_damage_immune()
	if combat:
		combat_attack_received.emit(attack_value)
	attack_value = resolve_damage(attack_value)
	if combat:
		attack_value = absorb_temporary_armor(attack_value)
		if attack_value > 0:
			combat_hp_damaged.emit(mini(attack_value, curr_hp))
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


## 可消耗临时护甲的扩展入口；没有护甲的角色保持原伤害数值。
## [param damage] 已完成减伤结算的非负伤害，返回进入本体生命的剩余量。
func absorb_temporary_armor(damage: int) -> int:
	return damage

## [param damage] 原始伤害；普通生命与护甲子类分别在各自分流前调用一次。
func resolve_damage(damage: int) -> int:
	if _bypass_damage_block:
		return maxi(0, damage)
	if is_damage_immune():
		return 0
	return damage_reduction.reduce(damage_block.reduce(maxi(0, roundi(float(damage) * (1.0 + total_degradation_fraction())))))

## [param source_id] 无敌效果的来源 ID；[param enabled] 为 true 时添加该来源，为 false 时移除。
func set_immunity_source(source_id: int, enabled: bool) -> void:
	if enabled:
		_immunity_sources[source_id] = true
	else:
		_immunity_sources.erase(source_id)
	_update_damage_immunity_tint()

## 返回脚本无敌或任一限时无敌来源是否仍然生效。
func is_damage_immune() -> bool:
	return damage_immune or not _immunity_sources.is_empty()


## 按角色的实际无敌状态同步本体滤镜，死亡时移除滤镜。
func _update_damage_immunity_tint() -> void:
	if not is_instance_valid(owner_character) or not is_instance_valid(owner_character.body):
		return
	owner_character.body.set_damage_immunity_tint(is_damage_immune() and not owner_character.is_death)


## [param amount] 有效格挡；独立染色通道避免与冰冻、受击和阶段颜色互相覆盖。
func _on_damage_block_changed(amount: int) -> void:
	if is_instance_valid(owner_character) and is_instance_valid(owner_character.body):
		owner_character.body.set_other_color(BodyCharacter.E_ChangeColors.DamageBlock,
			Color(0.72, 1.0, 0.96) if amount > 0 else Color.WHITE)
