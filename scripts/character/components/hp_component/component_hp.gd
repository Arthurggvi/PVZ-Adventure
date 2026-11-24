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
## 有独立上限的具名劣化；同族来源共用上限，不截断旧的无限叠加通道。
var _capped_degradation: Dictionary[StringName, float] = {}

## [param fraction] 本次非负劣化比例；非有限值与非正数不生效。
## [param stackable] 为 true 时仅累加独立通道，否则保持原有取最强值规则。
## 两种通道均持续至本次角色结束，最终战斗修正相加。
func apply_degradation(fraction: float, stackable: bool = false) -> void:
	if not is_finite(fraction) or fraction <= 0.0 \
			or (is_instance_valid(owner_character) and not owner_character.can_receive_negative_effects()):
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

## 为 [param family] 累加 [param fraction] 点比例，并仅把本族限制在 [param cap]。
## 家族名与正有限数值必须有效；既有不可叠加和无限叠加通道保持原值。
func apply_capped_degradation(fraction: float, cap: float, family: StringName) -> void:
	if family.is_empty() or not is_finite(fraction) or fraction <= 0.0 \
			or not is_finite(cap) or cap <= 0.0 \
			or (is_instance_valid(owner_character) and not owner_character.can_receive_negative_effects()):
		return
	var current: float = _capped_degradation.get(family, 0.0) # 只累计本效果族的贡献。
	_capped_degradation[family] = maxf(current, minf(cap, current + fraction))
	if is_instance_valid(owner_character) and is_instance_valid(owner_character.body):
		owner_character.body.set_other_color(BodyCharacter.E_ChangeColors.Degradation, Color(0.55, 0.57, 0.58))

## 清除所有劣化通道和对应染色，保留其他承伤修正及颜色层。
func clear_degradation() -> void:
	degradation_fraction = 0.0
	stacked_degradation_fraction = 0.0
	_capped_degradation.clear()
	if is_instance_valid(owner_character) and is_instance_valid(owner_character.body):
		owner_character.body.set_other_color(BodyCharacter.E_ChangeColors.Degradation, Color.WHITE)

## 脆弱的最大层数；每层只增加一个百分点的承伤。
const MAX_BRITTLENESS_STACKS: int = 100
## 当前脆弱层数；按实际承伤者结算，任何输出计算都不读取它。
var brittleness_stacks: int = 0
## 创伤每层提供一点随本次攻击进入防御的固定伤害；默认没有创伤。
var cactus_wound_stacks: int = 0

## 增加 [param stacks] 层脆弱。免疫负面状态的角色保持原层数，多个来源共用目标上限。
func add_brittleness(stacks: int) -> void:
	if is_instance_valid(owner_character) and not owner_character.can_receive_negative_effects():
		return
	brittleness_stacks = mini(MAX_BRITTLENESS_STACKS, brittleness_stacks + maxi(0, stacks))

## 返回各独立劣化通道的总比例，仅用于结算和表现，不反写任一通道。
func total_degradation_fraction() -> float:
	var total: float = degradation_fraction + stacked_degradation_fraction # 旧两通道保持原有含义。
	for family: StringName in _capped_degradation: # 按效果族累计，避免为每次承伤创建值数组。
		total += _capped_degradation[family]
	return total

## 清空显式传入的 [param receipt]，并以 [param recipient] 初始化本次命中的回执。
## 省略或传非字典时不保存状态；拒绝伤害也必须返回零，不能沿用调用方的旧值。
static func reset_hit_receipt(receipt: Variant, recipient: Character000Base) -> void:
	if receipt is Dictionary:
		receipt.clear()
		receipt.merge({"recipient": recipient, "actual_loss": 0, "body_loss": 0, "casualty": null})

## 每缺少一个完整的本体生命百分点时的伤害加成；0 保留普通角色的输出。
var missing_health_damage_per_percent: float = 0.0
## 每缺少一个完整的本体生命百分点时的独立免伤与它自身的上限。
var missing_health_reduction_per_percent: float = 0.0
var missing_health_reduction_cap: float = 0.0

## 返回以本体最大生命为基准的完整缺失百分点；防具和额外护甲不计入。
func missing_health_percent() -> int:
	return clampi(floori(100.0 * (max_hp - curr_hp) / max_hp), 0, 100) if max_hp > 0 else 0

## [param amount] 为出手基础伤害。缺失生命只读当前血池，治疗会即时影响下次出手。
func outgoing_damage(amount: int) -> int:
	var multiplier: float = maxf(0.0, 1.0 - total_degradation_fraction()) # 各类劣化依照原有加算顺序。
	if missing_health_damage_per_percent > 0.0:
		multiplier *= 1.0 + missing_health_percent() * missing_health_damage_per_percent
	return maxi(0, roundi(float(amount) * multiplier))

## 返回用于复制的持久战斗效果，避免新实例持有旧实例的可变字典。
func copy_persistent_health_effects() -> Dictionary:
	return {"degradation": degradation_fraction, "stacked": stacked_degradation_fraction,
		"capped": _capped_degradation.duplicate(), "brittleness": brittleness_stacks, "cactus_wound": cactus_wound_stacks}

## 恢复 [param effects] 中已在旧个体结算的持久效果；不会施加新的伤害。
func restore_persistent_health_effects(effects: Dictionary) -> void:
	cactus_wound_stacks = int(effects.get("cactus_wound", 0))
	degradation_fraction = float(effects["degradation"])
	stacked_degradation_fraction = float(effects["stacked"])
	_capped_degradation = effects["capped"].duplicate()
	brittleness_stacks = int(effects["brittleness"])
	owner_character.body.set_other_color(BodyCharacter.E_ChangeColors.Degradation,
		Color(0.55, 0.57, 0.58) if total_degradation_fraction() > 0.0 else Color.WHITE)
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
## 数字血量标签，仅在血条可见时更新。
@onready var label_hp: Label = %LabelHp
## 隐藏血条期间收到的本体数值变化，重新显示时刷新。
var _body_display_dirty: bool = false

## 角色满血值，也是初始化血量和血条比例的分母，场景需配置为正数。
@export var max_hp:int
## 本体受击音效
@export var sfx_be_attack_body :SoundManagerClass.TypeBeAttackSFX= SoundManagerClass.TypeBeAttackSFX.Null

## 是否可以查看血条(norm正常出战角色可以)
var is_can_look_hp:=true
## 角色是否死亡，判断是否发射死亡信号
var is_death := false
## 只在同步本体扣血期间设置；嵌套扣血结束后恢复，非致死命中不留下死因。
var _body_loss_cause: CombatHitScope.DeathCause = CombatHitScope.DeathCause.NORMAL
## 第一次达到死亡阈值时冻结的死因，尸体后续扣血不能改写。
var death_cause: CombatHitScope.DeathCause = CombatHitScope.DeathCause.NORMAL

## 死亡判定阈值；当前血量不高于该值时首次触发死亡信号，默认 0。
var death_hp:int = 0
## 魅惑升阶是否同比缩放死亡阈值；固定生命点数的物种可以关闭。
var scale_death_hp_on_promotion: bool = true
## 战斗攻击不能把本体生命降到此值以下；直接处决和存档恢复不受限。
var combat_minimum_hp: int = 0
## 当前生命值；写入时限制为非负数、刷新可见血条，并在达到阈值时触发死亡。
var curr_hp:int:
	# value 是调用方写入该属性的新值，需经过下方处理再更新内部状态。
	set(value):
		value = max(value, 0)
		curr_hp = value
		_body_display_dirty = true
		if is_visible_in_tree():
			_flush_body_display()

		## 如果血量小于死亡血量临界值,并且角色还未死亡时
		if value <= death_hp and not is_death:
			is_death = true
			death_cause = _body_loss_cause
			before_death.emit(death_cause)
			## 角色死亡
			signal_hp_component_death.emit()


## 血量损失信号(curr_hp:当前血量值),给血量变化组件(僵尸\坚果\南瓜)使用
signal signal_hp_loss(curr_hp:int, is_drop:bool)
## 血量组件检测到死亡信号
signal signal_hp_component_death
## 第一次确认死亡后、角色死亡与掉落信号前的只读观察口；[param cause] 是冻结的真实伤害来源。
signal before_death(cause: CombatHitScope.DeathCause)
## 本次确实收到的战斗攻击，含被护甲吸收部分；不包括脚本强制处决。
signal combat_attack_received(raw_damage: int)
## 本次真实损失的本体生命，已扣除减伤、护甲和单次伤害上限。
signal combat_hp_damaged(amount: int)
## 本次真实战斗损失的全部可消耗血池，含临时护甲；排除过量伤害与脚本强制操作。
signal combat_health_lost(amount: int)

func _ready() -> void:
	damage_block.changed.connect(_on_damage_block_changed)
	# 所属角色就绪后才能使用其 Body 引用，补同步入树前设置的无敌状态。
	owner_character.ready.connect(_update_damage_immunity_tint, CONNECT_ONE_SHOT)
	owner_character.signal_character_death.connect(_update_damage_immunity_tint)
	visibility_changed.connect(_flush_body_display)
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

## 同步可见血条的本体数值。隐藏期间保留脏标记，公开血量与战斗信号仍同步更新。
func _flush_body_display() -> void:
	if _body_display_dirty and is_visible_in_tree():
		_body_display_dirty = false
		label_hp.text = str(curr_hp)
		progress_bar_hp.value = float(curr_hp) / max_hp


## [param value] 用户配置中的血条可见开关；角色允许显示血量时才应用。
func change_display_HP_label(value:bool):
	if is_can_look_hp:
		visible = value

## [param new_death_hp] 新的死亡血量阈值，达到或低于该值时触发死亡判定。
func set_death_hp(new_death_hp:int):
	self.death_hp = new_death_hp

## 返回 [param amount] 点本体伤害是否跨越真实死亡阈值；可转换的生命壳可覆写观察资格。
## 只供伤害前观察使用，不接管实际扣血、死亡信号或掉落。
func would_die_from_damage(amount: int) -> bool:
	return amount > 0 and curr_hp > death_hp and curr_hp - amount <= death_hp

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

## 返回距原生死亡阈值的剩余生命比例，范围0至1；不含防具或临时护甲。
## 默认零阈值与普通生命比例一致，头部掉落即判死的僵尸仍拥有可达的处决区间。
func living_health_fraction() -> float:
	var living_max: int = maxi(0, max_hp - death_hp) # 扣除不能继续存活的原生保留血量。
	return clampf(float(curr_hp - death_hp) / float(living_max), 0.0, 1.0) if living_max > 0 else 0.0

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
## [param bonus_damage] 同一次命中的非负附伤；[param bonus_cap] 限制劣化放大后的附伤，-1 不限制。
## [param receipt] 可选字典，报告本次实际受击者、全部血池/本体损失和实际死者；默认不记录。
## [param hit_scope] 可选群组命中资格；同一实际受击者重复命中在伤害事件前拒绝。
func Hp_loss(attack_value:int, _bullet_mode:BulletRegistry.AttackMode =BulletRegistry.AttackMode.Norm,
		is_drop_on_death=true, trigger_be_attack_SFX:=true, is_drop_2:=true,
		bonus_damage: int = 0, bonus_cap: int = -1, receipt: Variant = null,
		hit_scope: CombatHitScope = null):
	reset_hit_receipt(receipt, owner_character)
	if hit_scope != null and not hit_scope.try_claim(owner_character):
		return false
	var actual_loss: int = 0 # 只记录本次攻击真实消耗的血池，脚本生命调整不计入。
	var body_loss: int = 0 # 在扣血前采样，后续死亡/治疗回调不能改写本击损失。
	var was_alive: bool = not is_death # 尸体后续扣血不能重复触发战斗损失收益。
	var raw_damage: int = attack_value + maxi(0, bonus_damage) # 主伤与附伤只发出一次原始攻击事件。
	# 保留原始攻击事件，护甲和格挡不能将“正在被攻击”伪装成脱战。
	var combat: bool = raw_damage > 0 and not _bypass_damage_block and not is_damage_immune()
	if combat:
		combat_attack_received.emit(raw_damage)
	attack_value = resolve_damage(attack_value, bonus_damage, bonus_cap)
	if hit_scope != null and hit_scope.boss_damage_cap >= 0 and owner_character is ZB000Base:
		attack_value = mini(attack_value, hit_scope.boss_damage_cap)
	if combat:
		var before_armor: int = attack_value # 已减伤但尚未被临时护甲吸收的本次容量。
		attack_value = absorb_temporary_armor(attack_value)
		if combat_minimum_hp > 0:
			attack_value = mini(attack_value, maxi(0, curr_hp - combat_minimum_hp))
		body_loss = mini(attack_value, curr_hp) if was_alive else 0
		if attack_value > 0:
			combat_hp_damaged.emit(mini(attack_value, curr_hp))
		actual_loss = maxi(0, before_armor - attack_value) + mini(attack_value, curr_hp) if was_alive else 0
		if was_alive and actual_loss > 0:
			combat_health_lost.emit(actual_loss)
	apply_body_loss(attack_value, hit_scope.death_cause if hit_scope != null else CombatHitScope.DeathCause.NORMAL)
	if receipt is Dictionary:
		receipt["actual_loss"] = actual_loss
		receipt["body_loss"] = body_loss
		receipt["casualty"] = owner_character if was_alive and is_death else null
	# 本次血量变化是否允许触发掉落表现，由死亡掉落选项和额外条件共同决定。
	var is_drop = not (owner.is_death and not is_drop_on_death) and is_drop_2
	signal_hp_loss.emit(curr_hp, is_drop)

	## 如果有受击音效并且触发受击音效
	if sfx_be_attack_body != SoundManager.TypeBeAttackSFX.Null and trigger_be_attack_SFX:
		_play_hit_sound(sfx_be_attack_body)

	return curr_hp == 0

## 播放 [param kind] 的受击声，锚定本体真实受击框。原版战场仍使用同一音效池。
func _play_hit_sound(kind: SoundManagerClass.TypeBeAttackSFX) -> void:
	var anchor: Node = owner_character.hurt_box_component if is_instance_valid(owner_character) else self # 命中组件代表可见接触面。
	SoundManager.play_be_attack_SFX(kind, anchor)

## 掉血死亡
##[is_drop:bool]是否有掉落body
## [param is_drop] 是否允许本次伤害触发掉落表现。
func Hp_loss_death(is_drop:=true):
	apply_unblocked_loss(get_all_hp(), BulletRegistry.AttackMode.Norm, is_drop, false)


## 非战斗生命调整，供卸甲、处决和存档恢复使用；保留护甲分流及原有死亡/掉落信号。
## [param amount] 调整量；[param mode] 分流类型；[param drop] 致死掉落；[param sfx] 音效；[param extra_drop] 额外掉落开关。
## [param hit_scope] 供明确的处决来源携带死因，缺省保持普通强制死亡。
func apply_unblocked_loss(amount: int, mode: BulletRegistry.AttackMode = BulletRegistry.AttackMode.Norm,
		drop: bool = true, sfx: bool = true, extra_drop: bool = true, hit_scope: CombatHitScope = null) -> void:
	var previous: bool = _bypass_damage_block # 保存嵌套调用前的状态，避免回调覆盖外层上下文。
	_bypass_damage_block = true
	Hp_loss(amount, mode, drop, sfx, extra_drop, 0, -1, null, hit_scope)
	_bypass_damage_block = previous

## 扣除 [param amount] 点本体生命，并仅在本次同步写入期间携带 [param cause]。
## 不替换死亡判定、掉落或受击信号；直接脚本写血仍默认普通死亡。
func apply_body_loss(amount: int, cause: CombatHitScope.DeathCause = CombatHitScope.DeathCause.NORMAL) -> void:
	var previous: CombatHitScope.DeathCause = _body_loss_cause # 死亡观察可能嵌套另一笔伤害，退出时恢复外层来源。
	_body_loss_cause = cause
	curr_hp -= amount
	_body_loss_cause = previous


## 可消耗临时护甲的扩展入口；没有护甲的角色保持原伤害数值。
## [param damage] 已完成减伤结算的非负伤害，返回进入本体生命的剩余量。
func absorb_temporary_armor(damage: int) -> int:
	return damage

## [param damage] 主伤害；[param bonus_damage] 同击附伤，负值按零处理。
## [param bonus_cap] 为易伤放大后的附伤上限，-1 不限制；随后统一结算一次格挡和减伤。
## 用总伤与主伤的整数差限制附伤，保留原有取整；后续减伤、护甲只会继续降低伤害。
func resolve_damage(damage: int, bonus_damage: int = 0, bonus_cap: int = -1) -> int:
	var bonus: int = maxi(0, bonus_damage) # 附伤不能抵消主伤或产生治疗。
	if _bypass_damage_block:
		return maxi(0, damage + (mini(bonus, bonus_cap) if bonus_cap >= 0 else bonus))
	if is_damage_immune():
		return 0
	var degradation: float = (degradation_fraction + stacked_degradation_fraction
		if _capped_degradation.is_empty() else total_degradation_fraction()) # 有具名效果时按原顺序合成。
	var amplification: float = 1.0 + degradation + brittleness_stacks * 0.01 # 两项独立，只在承伤放大前合计。
	var amplified: int = maxi(0, roundi(float(damage + bonus) * amplification)) # 无附伤时逐值沿用旧计算。
	if bonus > 0 and bonus_cap >= 0:
		var primary: int = maxi(0, roundi(float(damage) * amplification)) # 本次主伤独立保留，不受附伤上限削减。
		amplified = primary + mini(bonus_cap, maxi(0, amplified - primary))
	if cactus_wound_stacks > 0 and (damage > 0 or bonus > 0):
		amplified += cactus_wound_stacks # 创伤不另发受击，也不改变原有附伤的上限。
	var unblocked: int = damage_block.reduce(amplified) if damage_block.value != 0 else amplified # 零格挡保留非负伤害。
	if unblocked <= 0:
		return 0
	var independent_reduction: float = 0.0 # 没入疯狂按本次受击前的生命独立计算，80% 时保留实际两成承伤。
	if missing_health_reduction_per_percent > 0.0:
		independent_reduction = minf(missing_health_reduction_cap,
			missing_health_percent() * missing_health_reduction_per_percent)
	return damage_reduction.reduce(unblocked, independent_reduction)

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
