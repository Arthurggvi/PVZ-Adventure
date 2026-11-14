extends Node2D
class_name Character000Base

#region 子节点
## 角色身体表现节点，负责染色、受击闪光和压扁等视觉效果。
@onready var body: BodyCharacter = %Body
## 角色必备组件(受击盒子组件、血量组件)
## 角色受击组件，统一控制检测区域与实际命中区域的可用性。
@onready var hurt_box_component:HurtBoxComponent = %HurtBoxComponent

## 角色生命组件，负责扣血、死亡判定及血条显示。
@onready var hp_component: HpComponent = %HpComponent
## 角色动画组件接口，接收速度变化并转发到具体动画播放器。
@onready var anim_component: AnimComponentBase = %AnimComponent

## 角色脚下阴影精灵，供子类调整位置、方向和可见性。
@onready var shadow: Sprite2D = %Shadow

## 计时器种类
enum E_TimerType{
	IceDecelerate,	## 冰冻减速
	IceFreeze,		## 冰冻停滞
	Butter,			## 黄油
	Stun,			## 眩晕
	IceChargeRecovery, ## 真实冰冻结束后一秒的冻结值保护期。
}
## 减速相关计时器(第一次使用时创建)
var all_timer:Dictionary[E_TimerType, Timer] = {
	E_TimerType.IceDecelerate:null,
	E_TimerType.IceFreeze:null,
	E_TimerType.Butter:null,
	E_TimerType.Stun:null,
	E_TimerType.IceChargeRecovery:null,
}
#endregion

#region 基础属性

## 角色实际方向改变时,body方向为角色实际方向基础的body方向
@export_group("角色方向")
## 角色实际方向(1为默认方向,-1为反方向)被魅惑时改变方向
@export var direction_x_root := 1
## 不改变方向的节点(睡眠组件\血条显示),当角色实际方向改变时,将该组件方向修改回来
@export var node_no_change_direction:Array[Node2D]
## body方向(1为默认方向,-1为反方向)[舞王\花园使用]
@export var direction_x_body := 1
## 跟随body方向的节点(body\影子\灰烬)
@export var node_follow_body_direction:Array[Node2D]
## 是否为我是僵尸模式
var is_zombie_mode:=false

@export_group("角色速度")
## 初始速度倍率的随机范围；x 为下限、y 为上限，1 表示正常速度。
@export var random_speed_range :Vector2 = Vector2(0.9, 1.1)
## 角色所在行的索引；-1 表示尚未分配行号。
var lane:int = -1
## 各影响因素的速度倍率字典；最终速度取乘积，1 不改变速度、0 使动作停滞。
var influence_speed_factors :Dictionary[E_Influence_Speed_Factor, float]= {
}
enum E_Influence_Speed_Factor{
	InitRandomSpeed,	## 角色初始化时选定的随机速度倍率。
	IceDecelerateSpeed,	## 冰冻减速倍率，解除减速后恢复为 1。
	IceFreezeSpeed,	## 完全冰冻倍率，冻结时为 0，解除后恢复为 1。
	HammerZombieSpeed,	## 锤僵尸模式修改速度
	ZamboniHp,		## 冰车僵尸血量变化时
	Butter,			## 黄油
	EatGarlic,		## 啃食大蒜后短时间停止
	OutBattlefield,	## 宽屏战场外僵尸移动加速
	AdventureTierBoost,	## 冒险专属等阶的临时加速，独立于其他速度因子
	AdventureTierStance, ## Permanent pole carrying / exhausted movement factor
	AdventurePromotionAttackRate, ## 冒险转职攻速倍率，动画与发射计时共用。
	Stun, ## 眩晕的独立速度因子，停止行动时为 0。
	ForcedAirborne, ## 被抛起时暂停动作，落地后恢复此通道。
	DeepColdSlow, ## 独立于原生冰的抗火减速；与原生寒冷减速取较强值。
	DeepColdFreeze, ## 独立于原生冰的抗火冻结；两个来源均解除才真正解冻。
}
## 是否被魅惑
var is_hypno:bool = false
## 真实冰冻结束后禁止施加冻结值的战斗秒数。
const ICE_CHARGE_RECOVERY_SECONDS: float = 1.0
## 冰冻结束后的减速持续秒数，每次被冰冻时由传入参数更新。
var time_ice_end_decelerate := 5.0
## 冰冻特效
var ice_effect:IceEffect

## 是否可以触发亡语(爆炸\大嘴花\铲子不可以触发)
var is_can_death_language:=true

## 速度改变信号 speed_factor_product: 速度系数乘积
signal signal_update_speed(speed_factor_product:float)
## 普通和抗火冻结全部解除时发出，火焰提前解除仅处理普通冻结。
signal signal_ice_freeze_ended()

@export_group("动画状态")
## 角色逻辑死亡标记；进入死亡流程时置为 true，供行为和受击逻辑拒绝后续操作。
@export var is_death:=false
## 是否处于待机姿态；由角色或状态机更新，供动画与行为逻辑读取。
@export var is_idle := true
## 是否为展示\花园状态
@export var is_show := false

## 角色死亡信号
signal signal_character_death()
## 角色被魅惑信号
signal signal_character_be_hypno()
## 角色方向更新信号，被魅惑时发出，血条、睡觉显示方向修改
signal signal_direction_x_root_update(direction_x:int)
## body方向更新信号
signal signal_direction_x_body_update(direction_x:int)
#region 更新角色方向
## 更新角色本体方向
## [param direction_x] 目标横向方向，1 为默认方向，-1 为反方向。
func update_direction_x_root(direction_x:int):
	direction_x_root = direction_x
	scale.x = abs(scale.x) * sign(direction_x)
	signal_direction_x_root_update.emit(direction_x_root)

## 更新角色body方向
## [param direction_x] 目标横向方向，1 为默认方向，-1 为反方向。
func update_direction_x_body(direction_x:int):
	direction_x_body = direction_x
	signal_direction_x_body_update.emit(direction_x_body)
#endregion

#region 展示show角色相关
@export_group("初始化类型相关")
enum E_CharacterInitType{
	IsNorm,		## 普通出战
	IsShow,		## 展示状态（关卡前展示、图鉴）
	IsGarden,	## 花园状态
}

## 角色初始化类型
@export var character_init_type :E_CharacterInitType = E_CharacterInitType.IsNorm
@export_group("斜面(屋顶)相关")
## 斜面移动的检测层面的组件(受击框,检测组件或非检测组件下的检测框)
@export var node2d_detect_in_slope:Array[Node2D]
#endregion

#endregion
func _ready() -> void:
	match character_init_type:
		E_CharacterInitType.IsNorm:
			ready_norm()
		E_CharacterInitType.IsShow:
			ready_show()
		E_CharacterInitType.IsGarden:
			ready_garden()

## 初始化正常出战角色信号连接
func ready_norm_signal_connect():
	## 角色根改变方向（修改为同样的值,方向不变）
	# 当前需要随方向信号调整横向缩放的节点；闭包只修改这一节点。
	for node2d:Node2D in node_no_change_direction:
		# dir_x 是根节点方向信号给出的目标符号，用于抵消父级翻转。
		signal_direction_x_root_update.connect(func(dir_x:int): node2d.scale.x = abs(node2d.scale.x) * sign(dir_x))

	## 角色body改变方向（修改为同样的值,保持和body方向一致）
	# 当前需要随方向信号调整横向缩放的节点；闭包只修改这一节点。
	for node2d:Node2D in node_follow_body_direction:
		# dir_x 是身体方向信号给出的目标符号，使该节点与身体朝向一致。
		signal_direction_x_body_update.connect(func(dir_x:int): node2d.scale.x = abs(node2d.scale.x) * sign(dir_x))

	## 速度修改信号连接动画速度
	signal_update_speed.connect(anim_component.owner_update_speed)

	## 血量组件发射死亡信号
	hp_component.signal_hp_component_death.connect(character_death)

	## 被魅惑
	signal_character_be_hypno.connect(body.owner_be_hypno)

## 初始化正常出战角色
func ready_norm():
	ready_norm_signal_connect()
	is_show = false
	is_idle = false
	## 我是僵尸模式，随机速度变量为1
	if is_zombie_mode:
		random_speed_range = Vector2(1,1)
	## 舞王重写该方法，要在帧末尾调用，不然会报错
	call_deferred("init_random_speed")

## 初始化展示角色
func ready_show():
	is_show = true
	is_idle = true
	hurt_box_component.disable_component(ComponentNormBase.E_IsEnableFactor.InitType)
	## 禁用生产阳光组件
	# 展示角色可能具有的阳光生产组件；不存在时为 null，不执行禁用操作。
	var create_sun_component: CreateSunComponent = get_node_or_null("CreateSunComponent")
	if is_instance_valid(create_sun_component):
		create_sun_component.disable_component(ComponentNormBase.E_IsEnableFactor.InitType)
	## 禁用攻击组件
	# 展示角色可能具有的攻击组件；存在时按初始化类型关闭攻击。
	var attack_component: AttackComponentBase = get_node_or_null("AttackComponent")
	if is_instance_valid(attack_component):
		attack_component.disable_component(ComponentNormBase.E_IsEnableFactor.InitType)


## 初始化花园角色
func ready_garden():
	is_show = true
	is_idle = true
	hurt_box_component.disable_component(ComponentNormBase.E_IsEnableFactor.InitType)

## 随机初始化角色速度
func init_random_speed():
	#print("随机初始化角色速度")
	## 初始化角色速度
	update_speed_factor(randf_range(random_speed_range.x, random_speed_range.y), E_Influence_Speed_Factor.InitRandomSpeed)

## 修改速度，发射信号
## [param value] 当前影响因素的新速度倍率；1 不改变速度，0 使动作停滞。
## [param influent_speed_factor] 本次更新的速度影响因素，最终速度由所有因素相乘得到。
func update_speed_factor(value: float, influent_speed_factor:E_Influence_Speed_Factor) -> void:
	influence_speed_factors[influent_speed_factor] = value
	signal_update_speed.emit(speed_factor_product())

## 返回角色合成速度；普通与抗火寒冷重叠时仍为同一种减速强度。
func speed_factor_product() -> float:
	var cold_overlap: bool = influence_speed_factors.get(E_Influence_Speed_Factor.IceDecelerateSpeed, 1.0) < 1.0 \
		and influence_speed_factors.get(E_Influence_Speed_Factor.DeepColdSlow, 1.0) < 1.0 # 两种寒冷的标准减速均为半速。
	return GlobalUtils.get_dic_product(influence_speed_factors) * (2.0 if cold_overlap else 1.0)

#region 死亡、受击相关
## 亡语
func death_language():
	pass

## 角色死亡,子类继承重写
func character_death():
	is_death = true
	signal_character_death.emit()
	#call_deferred("emit_signal", "signal_character_death")
	if is_can_death_language:
		death_language()

## 被攻击至死亡(大保龄球)
## [param trigger_be_attack_SFX] 是否播放本次受击音效，false 时只处理扣血及相关信号。
func be_attack_to_death(trigger_be_attack_SFX:=true):
	hp_component.apply_unblocked_loss(hp_component.get_all_hp(), BulletRegistry.AttackMode.Norm, true, trigger_be_attack_SFX)

## 死亡不消失(海草\被碾压)
func character_death_not_disappear():
	pass

## 死亡直接消失
func character_death_disappear():
	hp_component.Hp_loss_death(false)
	queue_free()

## 被子弹攻击
## [param attack_value] 本次攻击扣除的生命值，具体伤害规则由生命组件处理。
## [param bullet_mode] 传给生命组件的攻击类型，用于区分普通、穿透等攻击规则。
## [param is_drop] 是否允许本次伤害触发掉落表现。
## [param trigger_be_attack_SFX] 是否播放本次受击音效，false 时只处理扣血及相关信号。
## [param bonus_damage] 同次命中的附伤；[param bonus_cap] 为劣化放大后的附伤上限，-1 不限制。
## [param receipt] 可选实际伤害回执，省略时沿用原有受击路径。
## [param hit_scope] 可选结算群组，由生命组件在实际承伤位置消费。
func be_attacked_bullet(attack_value:int, bullet_mode:BulletRegistry.AttackMode=BulletRegistry.AttackMode.Norm,
		is_drop:bool=true, trigger_be_attack_SFX:=true, bonus_damage: int = 0, bonus_cap: int = -1,
		receipt: Variant = null, hit_scope: CombatHitScope = null):
	HpComponent.reset_hit_receipt(receipt, self)
	hp_component.Hp_loss(attack_value, bullet_mode, is_drop, trigger_be_attack_SFX, true, bonus_damage, bonus_cap, receipt, hit_scope)
	body.body_light()

## 被锤子攻击(伤害值不生效)
## [param attack_value] 本次攻击扣除的生命值，具体伤害规则由生命组件处理。
func be_attacked_hammer(attack_value:int):
	hp_component.Hp_loss(attack_value,BulletRegistry.AttackMode.Hammer, true, true)
	body.body_light()
	return is_death


## 被僵尸啃食
## attack_value:伤害
## attack_zombie:攻击的僵尸
## [param attack_value] 本次攻击扣除的生命值，具体伤害规则由生命组件处理。
## [param _attack_zombie] 发起啃食的僵尸引用；当前基类只处理通用受击，不读取攻击者信息。
func be_zombie_eat(attack_value:int, _attack_zombie:Zombie000Base):
	hp_component.Hp_loss(attack_value,BulletRegistry.AttackMode.Penetration, true, false)

## 被僵尸啃食一次发光
## [param _attack_zombie] 发起啃食的僵尸引用；当前基类只处理通用受击，不读取攻击者信息。
func be_zombie_eat_once(_attack_zombie:Zombie000Base):
	body.body_light()

## 被魅惑
func be_hypno():
	is_hypno = true
	signal_character_be_hypno.emit()
	update_direction_x_root(-1)

	#hurt_box_component.disable_component(ComponentNormBase.E_IsEnableFactor.Hypno)
	#hurt_box_component.enable_component(ComponentNormBase.E_IsEnableFactor.Hypno)

## 被压扁
## [character:Character000Base] 发动攻击的角色
## [param _character] 发起压扁攻击的角色引用；当前通用压扁逻辑不区分攻击者。
func be_flattened_from_enemy(_character:Character000Base):
	be_flattened()

## 植物被压扁，无敌人(罐子压扁)
func be_flattened():
	body.be_flattened_body()
	## 角色死亡消失
	character_death_disappear()

#endregion


#region 速度修改相关
## 返回角色是否属于可受负面状态的实体；敌方设施统一覆盖为 false。
func can_receive_negative_effects() -> bool:
	return true

## 返回物种是否接受寒冷；原生免疫物种覆盖此能力，冻结值不得绕过它。
func can_receive_cold() -> bool:
	return true

## 返回物种当前能否完全冻结；有条件抵抗的僵尸继续只受减速。
func can_cold_freeze() -> bool:
	return can_receive_cold()

## 返回命中前是否已处在任一种寒冷减速、完全冻结或冻结值减速中。
func is_cold_slowed() -> bool:
	return is_cold_frozen() or influence_speed_factors.get(E_Influence_Speed_Factor.IceDecelerateSpeed, 1.0) < 1.0 \
		or influence_speed_factors.get(E_Influence_Speed_Factor.DeepColdSlow, 1.0) < 1.0 \
		or AdventureFreezeChargeEffect.has_points(self)

## 返回是否仍有任一寒冷冻结来源。
func is_cold_frozen() -> bool:
	return influence_speed_factors.get(E_Influence_Speed_Factor.IceFreezeSpeed, 1.0) <= 0.0 \
		or influence_speed_factors.get(E_Influence_Speed_Factor.DeepColdFreeze, 1.0) <= 0.0

## 返回当前是否冻住或处于真实解冻后一秒保护期；尚无冻结值节点时也生效。
func is_ice_charge_blocked() -> bool:
	var recovery: Timer = all_timer.get(E_TimerType.IceChargeRecovery) as Timer # 所有冻结共用的恢复窗口。
	return is_cold_frozen() or (is_instance_valid(recovery) and recovery.time_left > 0.0)

## 被冰冻减速
## [param time] 本次冰冻减速持续时间，单位为秒。
func be_ice_decelerate(time:float):
	update_speed_factor(0.5, E_Influence_Speed_Factor.IceDecelerateSpeed)
	body.set_other_color(BodyCharacter.E_ChangeColors.IceColor, Color(0.5, 1, 1))
	if not is_instance_valid(all_timer[E_TimerType.IceDecelerate]):
		all_timer[E_TimerType.IceDecelerate] = GlobalUtils.create_new_timer_once(self, _on_ice_decelerate_timer_timeout)
	if all_timer[E_TimerType.IceDecelerate].time_left < time:
		all_timer[E_TimerType.IceDecelerate].start(time)

## 冰冻减速计时器结束
func _on_ice_decelerate_timer_timeout() -> void:
	update_speed_factor(1.0, E_Influence_Speed_Factor.IceDecelerateSpeed)
	body.set_other_color(BodyCharacter.E_ChangeColors.IceColor, Color(1, 1, 1))

## 被冰冻控制
## [param time] 本次完全冰冻持续时间，单位为秒。
## [param new_time_ice_end_decelerate] 冰冻解除后继续减速的时长，单位为秒。
## [param hit_scope] 可观察实际附伤结算，缺省仍是原生冰冻伤害。
func be_ice_freeze(time: float, new_time_ice_end_decelerate: float, hit_scope: CombatHitScope = null) -> void:
	hp_component.Hp_loss(20, BulletRegistry.AttackMode.Real, true, false, true, 0, -1, null, hit_scope)
	apply_ice_freeze_control(time, new_time_ice_end_decelerate)

## 施加 [param time] 秒原生冻结，并安排 [param followup] 秒后续减速。
## 冰痕满冻结值时使用此纯控制入口；保留物种只减速的原生资格。
func apply_ice_freeze_control(time: float, followup: float) -> void:
	if is_death or is_queued_for_deletion() or not can_receive_cold():
		return
	if not can_cold_freeze():
		be_ice_decelerate(time + followup)
		return
	on_cold_control()
	self.time_ice_end_decelerate = followup
	update_speed_factor(0.0, E_Influence_Speed_Factor.IceFreezeSpeed)
	body.set_other_color(BodyCharacter.E_ChangeColors.IceColor, Color(0.5, 1, 1))
	if not is_instance_valid(all_timer[E_TimerType.IceFreeze]):
		all_timer[E_TimerType.IceFreeze] = GlobalUtils.create_new_timer_once(self, _on_ice_freeze_timer_timeout)

	if all_timer[E_TimerType.IceFreeze].time_left < time:
		all_timer[E_TimerType.IceFreeze].start(time)

	## 冰冻特效
	if is_instance_valid(ice_effect):
		ice_effect.queue_free()
	## 冰冻效果
	ice_effect = SceneRegistry.ICE_EFFECT.instantiate()
	add_child(ice_effect)
	ice_effect.global_position = shadow.global_position
	ice_effect.start_ice_effect(all_timer[E_TimerType.IceFreeze].time_left)

## 原生到期与提前解冻共用结束口；只在真实离开冻结状态时开始一秒恢复窗口。
func _on_ice_freeze_timer_timeout() -> void:
	var was_frozen: bool = influence_speed_factors.get(E_Influence_Speed_Factor.IceFreezeSpeed, 1.0) <= 0.0 # 防止重复结束通知刷新保护期。
	update_speed_factor(1.0, E_Influence_Speed_Factor.IceFreezeSpeed)
	if is_death or is_queued_for_deletion():
		return
	be_ice_decelerate(time_ice_end_decelerate)
	if was_frozen:
		notify_cold_thaw()

## 任一冰冻来源退出时检查是否真正解冻；阶段清理不调用此入口。
func notify_cold_thaw() -> void:
	if is_death or is_queued_for_deletion() or is_cold_frozen():
		return
	if not is_instance_valid(all_timer[E_TimerType.IceChargeRecovery]):
		var recovery: Timer = Timer.new() # 即使尚未被施加冻结值，所有原生冰冻结束都登记保护期。
		recovery.one_shot = true
		add_child(recovery)
		all_timer[E_TimerType.IceChargeRecovery] = recovery
	all_timer[E_TimerType.IceChargeRecovery].start(ICE_CHARGE_RECOVERY_SECONDS)
	signal_ice_freeze_ended.emit()

## 寒冷控制实际施加时的物种行为；普通角色没有额外反应。
func on_cold_control() -> void:
	pass

## 取消冰冻减速(火焰豌豆\辣椒)
func cancel_ice():
	if is_instance_valid(all_timer[E_TimerType.IceFreeze]) and all_timer[E_TimerType.IceFreeze].time_left != 0:
		all_timer[E_TimerType.IceFreeze].stop()
		_on_ice_freeze_timer_timeout()
		if is_instance_valid(ice_effect):
			ice_effect.queue_free()
	if is_instance_valid(all_timer[E_TimerType.IceDecelerate]) and all_timer[E_TimerType.IceDecelerate].time_left != 0:
		all_timer[E_TimerType.IceDecelerate].stop()
		_on_ice_decelerate_timer_timeout()

## 净化原生冻结和减速，不安排冻后减速，也不启动解冻保护期。
func clear_cold() -> void:
	if not is_cold_slowed():
		return
	for kind: E_TimerType in [E_TimerType.IceFreeze, E_TimerType.IceDecelerate]: # 只终止寒冷控制计时。
		var timer: Timer = all_timer.get(kind) # 从未受过对应状态时没有计时器。
		if is_instance_valid(timer):
			timer.stop()
	if is_instance_valid(ice_effect):
		ice_effect.queue_free()
	ice_effect = null
	time_ice_end_decelerate = 0.0
	if is_cold_frozen():
		update_speed_factor(1.0, E_Influence_Speed_Factor.IceFreezeSpeed)
	_on_ice_decelerate_timer_timeout()

#endregion
