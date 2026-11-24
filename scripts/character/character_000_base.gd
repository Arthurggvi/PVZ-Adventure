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
	Dynasty, ## 皇朝攻速，同一种增益的所有施放共享一个乘数。
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

## 按来源实例 ID 保存独立的行动减速倍率，保留寒冷、眩晕和其他控制的来源。
var _action_slowdowns: Dictionary[int, float] = {}
## 攻击等原生动作期间的独立加速来源，和控制减速同时生效。
var _action_speedups: Dictionary[int, float] = {}
## 独立行动倍率的乘积，未受独立加减速影响时为 1。
var _action_rate := 1.0
## 只跟随独立行动倍率的补间。新建和变速时移除已完成的引用。
var _action_tweens: Array[Tween] = []

## 速度改变信号 speed_factor_product: 速度系数乘积
signal signal_update_speed(speed_factor_product:float)
## 自行推进动作的组件可用该信号同步独立行动倍率。
signal signal_action_rate_changed(rate: float)
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

## 返回原有速度来源的乘积；普通与抗火寒冷重叠时仍为同一种减速强度。
func intrinsic_speed_product() -> float:
	var cold_overlap: bool = influence_speed_factors.get(E_Influence_Speed_Factor.IceDecelerateSpeed, 1.0) < 1.0 \
		and influence_speed_factors.get(E_Influence_Speed_Factor.DeepColdSlow, 1.0) < 1.0 # 两种寒冷的标准减速均为半速。
	return GlobalUtils.get_dic_product(influence_speed_factors) * (2.0 if cold_overlap else 1.0)

## 返回包含独立行动减速的角色合成速度。
func speed_factor_product() -> float:
	return intrinsic_speed_product() * _action_rate

## 当前独立行动倍率，用于原本按固定速度驱动的动作；已消费 [signal signal_update_speed] 的路径不再乘一次。
func action_rate() -> float:
	return _action_rate

## [param source_id] 是效果实例身份。[param rate] 在 (0, 1] 间，1 仅撤销该来源。
## [param allow_stop] 仅供有完整零速支持的动作使用，允许该来源降至 0。
## 只有活动且可受控的角色接收新效果；免控仍允许解除来源，死亡时已有来源会全部释放。
func set_action_slowdown(source_id: int, rate: float, allow_stop: bool = false) -> void:
	if rate == 1.0 or can_receive_control_effects():
		_set_action_slowdown(source_id, rate, allow_stop)

## [param source_id] 标识一次钟表匠施放。[param rate] 为正行动倍率，1 撤销这次施放的倍率。
## TMC-112 使用自己的目标资格，并与其他独立行动倍率相乘。
func set_clockmaker_slowdown(source_id: int, rate: float) -> void:
	if rate == 1.0 or can_receive_clockmaker_slowdown():
		_set_action_slowdown(source_id, rate, false)

## [param source_id] 标识已通过资格检查的来源。[param rate] 为来源倍率，1 撤销来源。
## [param allow_stop] 允许零速。拒绝给已死亡或待释放的角色登记倍率。
func _set_action_slowdown(source_id: int, rate: float, allow_stop: bool) -> void:
	if rate == 1.0:
		if not _action_slowdowns.erase(source_id):
			return
	elif is_death or is_queued_for_deletion() or not is_finite(rate) or rate < 0.0 or rate > 1.0 \
			or (rate == 0.0 and not allow_stop):
		return
	else:
		_action_slowdowns[source_id] = rate
	_refresh_action_rate()

## [param source_id] 标识加速来源；[param rate] 大于1时加速，等于1时撤销。
func set_action_speedup(source_id: int, rate: float) -> void:
	if not is_finite(rate) or rate < 1.0 or (is_death and rate > 1.0):
		return
	if is_equal_approx(_action_speedups.get(source_id, 1.0), rate):
		return
	if rate == 1.0:
		_action_speedups.erase(source_id)
	else:
		_action_speedups[source_id] = rate
	_refresh_action_rate()

## 创建受独立行动倍率驱动的补间，随 [param host] 暂停和离树。既可在变速前创建也可在变速后创建。
func create_action_tween(host: Node) -> Tween:
	_sync_action_tweens()
	var tween: Tween = host.create_tween().set_speed_scale(_action_rate) # 补间时长始终按正常动作秒编写。
	_action_tweens.append(tween)
	return tween

## 传播新的合成倍率且保留所有计时器、动画和补间的既有进度。
func _refresh_action_rate() -> void:
	_action_rate = GlobalUtils.get_dic_product(_action_slowdowns) * GlobalUtils.get_dic_product(_action_speedups)
	if not is_inside_tree() or is_queued_for_deletion():
		return
	_sync_action_tweens()
	signal_action_rate_changed.emit(_action_rate)
	_publish_action_speed()

## 发布最终速度。舞团等共享速度的角色可先同步所属编组。
func _publish_action_speed() -> void:
	signal_update_speed.emit(speed_factor_product())

## 同步仍活动的动作补间并释放已结束的引用。
func _sync_action_tweens() -> void:
	for index: int in range(_action_tweens.size() - 1, -1, -1): # 倒序回收以保留其他索引。
		var tween: Tween = _action_tweens[index] # 只调整有效补间的推进倍率。
		if tween.is_valid():
			tween.set_speed_scale(_action_rate)
		else:
			_action_tweens.remove_at(index)

## 从 [param speed_product] 移除皇朝攻速，保留生产与成长原有的速度来源。
func production_speed_product(speed_product: float) -> float:
	return speed_product / influence_speed_factors.get(E_Influence_Speed_Factor.Dynasty, 1.0)

#region 死亡、受击相关
## 亡语
func death_language():
	pass

## 角色死亡,子类继承重写
func character_death():
	is_death = true
	if not _action_slowdowns.is_empty() or not _action_speedups.is_empty():
		_action_slowdowns.clear()
		_action_speedups.clear()
		_refresh_action_rate()
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

## 返回同一击的实际承伤身份；通常是自身，附属受击代理可返回其所属角色。
## 双阵营范围伤害先按此身份去重，避免同时击中代理和本体时重复消耗同一血池。
## 此查询不改变阵营、索敌或普通子弹的伤害路由；已经失去所属角色的代理可返回 null。
func combat_hit_owner() -> Character000Base:
	return self

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
	if receipt is Dictionary:
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
	if not can_receive_control_effects():
		return
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
## 返回角色是否接受战斗负面状态。僵王与敌方设施等免疫角色覆盖为 false。
func can_receive_negative_effects() -> bool:
	return true

## 返回是否接受外部行动控制；物种可单独免控，持续伤害、劣化和脆弱仍沿用负面状态资格。
func can_receive_control_effects() -> bool:
	return can_receive_negative_effects()

## 返回钟表匠 TMC-112 的受效资格。普通角色沿用自身免控规则。
func can_receive_clockmaker_slowdown() -> bool:
	return can_receive_control_effects()

## 返回物种是否接受寒冷；默认遵守免控能力，原生寒冷免疫和冻结值共同读取此资格。
func can_receive_cold() -> bool:
	return can_receive_control_effects()

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
## [param time] 为有限正减速秒数；零、负数或非有限值不写入速度状态。
func be_ice_decelerate(time: float) -> void:
	if not is_finite(time) or time <= 0.0 or not can_receive_control_effects() or not can_receive_cold():
		return
	update_speed_factor(0.5, E_Influence_Speed_Factor.IceDecelerateSpeed)
	_refresh_ice_color()
	if not is_instance_valid(all_timer[E_TimerType.IceDecelerate]):
		all_timer[E_TimerType.IceDecelerate] = GlobalUtils.create_new_timer_once(self, _on_ice_decelerate_timer_timeout)
	if all_timer[E_TimerType.IceDecelerate].time_left < time:
		all_timer[E_TimerType.IceDecelerate].start(time)

## 冰冻减速计时器结束
func _on_ice_decelerate_timer_timeout() -> void:
	update_speed_factor(1.0, E_Influence_Speed_Factor.IceDecelerateSpeed)
	_refresh_ice_color()

## 普通冻结与普通减速共用染色；其中一个到期时，另一个仍生效便保留寒冷颜色。
func _refresh_ice_color() -> void:
	if not is_instance_valid(body):
		return
	var ordinary_cold: bool = influence_speed_factors.get(E_Influence_Speed_Factor.IceFreezeSpeed, 1.0) <= 0.0 \
		or influence_speed_factors.get(E_Influence_Speed_Factor.IceDecelerateSpeed, 1.0) < 1.0 # 深寒使用自身独立颜色通道。
	body.set_other_color(BodyCharacter.E_ChangeColors.IceColor, Color(0.5, 1, 1) if ordinary_cold else Color.WHITE)

## 被冰冻控制
## [param time] 本次完全冰冻持续时间，单位为秒。
## [param new_time_ice_end_decelerate] 冰冻解除后继续减速的时长，单位为秒。
## [param hit_scope] 可观察实际附伤结算，缺省仍是原生冰冻伤害。
func be_ice_freeze(time: float, new_time_ice_end_decelerate: float, hit_scope: CombatHitScope = null) -> void:
	hp_component.Hp_loss(20, BulletRegistry.AttackMode.Real, true, false, true, 0, -1, null, hit_scope)
	apply_ice_freeze_control(time, new_time_ice_end_decelerate)

## 施加 [param time] 秒原生冻结，并安排 [param followup] 秒后续减速。
## 冰痕满冻结值使用此纯控制入口；只接受有限正冻结时长，负后续减速视为零。
func apply_ice_freeze_control(time: float, followup: float) -> void:
	if not is_finite(time) or time <= 0.0 or not is_finite(followup) \
			or is_death or is_queued_for_deletion() or not can_receive_control_effects() or not can_receive_cold():
		return
	followup = maxf(0.0, followup)
	if not can_cold_freeze():
		be_ice_decelerate(time + followup)
		return
	on_cold_control()
	self.time_ice_end_decelerate = followup
	if not is_instance_valid(all_timer[E_TimerType.IceFreeze]):
		all_timer[E_TimerType.IceFreeze] = GlobalUtils.create_new_timer_once(self, _on_ice_freeze_timer_timeout)
	if all_timer[E_TimerType.IceFreeze].time_left < time:
		all_timer[E_TimerType.IceFreeze].start(time)
	_begin_ice_freeze_control()
	ice_effect.start_ice_effect(all_timer[E_TimerType.IceFreeze].time_left)

## 已通过资格检查的冻结共用原生零速、染色与冰块；此入口本身不安排任何到期。
## 定时冻结由调用方启动融化，猎人冰壳保留未启动计时的同一特效实例。
func _begin_ice_freeze_control() -> void:
	update_speed_factor(0.0, E_Influence_Speed_Factor.IceFreezeSpeed)
	_refresh_ice_color()
	if is_instance_valid(ice_effect):
		ice_effect.queue_free()
	ice_effect = _create_ice_effect()
	add_child(ice_effect)
	ice_effect.global_position = shadow.global_position

## 创建尚未入树的冰效；子类只替换美术，计时、破壳和清寒仍由本类统一持有。
func _create_ice_effect() -> IceEffect:
	return SceneRegistry.ICE_EFFECT.instantiate() as IceEffect

## 原生到期与提前解冻共用结束口；只在真实离开冻结状态时开始一秒恢复窗口。
func _on_ice_freeze_timer_timeout() -> void:
	var was_frozen: bool = influence_speed_factors.get(E_Influence_Speed_Factor.IceFreezeSpeed, 1.0) <= 0.0 # 防止重复结束通知刷新保护期。
	update_speed_factor(1.0, E_Influence_Speed_Factor.IceFreezeSpeed)
	_refresh_ice_color()
	if is_death or is_queued_for_deletion():
		return
	if time_ice_end_decelerate > 0.0:
		be_ice_decelerate(time_ice_end_decelerate)
	if was_frozen:
		notify_cold_thaw()

## 提前结束普通冻结并停止原计时，保留仍有效的旧减速及其他独立控制。
## [param play_break_effect] 仅用于尚未启动融化计时的持久冰块，启动一次既有碎冰粒子。
## 不安排冻后减速；死亡或退场清理应使用无恢复窗口的 [method clear_cold]。
func end_ice_freeze_control(play_break_effect: bool = false) -> void:
	var freeze_timer: Timer = all_timer.get(E_TimerType.IceFreeze) as Timer # 持久冻结没有对应计时器也能解除。
	if is_instance_valid(freeze_timer):
		freeze_timer.stop()
	var thaw_effect: IceEffect = ice_effect # 先转移旧特效引用，新冰封不会误删尚在播放的碎冰粒子。
	ice_effect = null
	if is_instance_valid(thaw_effect):
		if play_break_effect:
			thaw_effect.start_ice_effect(0.0)
		else:
			thaw_effect.queue_free()
	time_ice_end_decelerate = 0.0
	_on_ice_freeze_timer_timeout()

## 任一冰冻来源退出时检查是否真正解冻；阶段清理不调用此入口。
func notify_cold_thaw() -> void:
	if is_death or is_queued_for_deletion() or is_cold_frozen():
		return
	restore_ice_charge_recovery(ICE_CHARGE_RECOVERY_SECONDS)
	signal_ice_freeze_ended.emit()

## 保留 [param duration] 秒冻结值保护期；复制只还原时钟，无须广播一次新的解冻。
func restore_ice_charge_recovery(duration: float) -> void:
	if duration <= 0.0:
		return
	if not is_instance_valid(all_timer[E_TimerType.IceChargeRecovery]):
		var recovery: Timer = Timer.new()
		recovery.one_shot = true
		add_child(recovery)
		all_timer[E_TimerType.IceChargeRecovery] = recovery
	all_timer[E_TimerType.IceChargeRecovery].start(duration)

## 寒冷控制实际施加时的物种行为；普通角色没有额外反应。
func on_cold_control() -> void:
	pass

## 火焰清除普通冻结与减速；持久冰壳没有计时器时同样沿用原生解冻通知。
func cancel_ice() -> void:
	if influence_speed_factors.get(E_Influence_Speed_Factor.IceFreezeSpeed, 1.0) <= 0.0:
		end_ice_freeze_control()
	var slow_timer: Timer = all_timer.get(E_TimerType.IceDecelerate) as Timer # 只清普通减速，不覆盖深寒等独立来源。
	if is_instance_valid(slow_timer):
		slow_timer.stop()
	if influence_speed_factors.get(E_Influence_Speed_Factor.IceDecelerateSpeed, 1.0) < 1.0:
		_on_ice_decelerate_timer_timeout()
	else:
		_refresh_ice_color()

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
