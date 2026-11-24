## 战斗负面状态入口，统一判定目标类型与免疫，并派发给角色自身。
## 各状态自身仍持有其生命周期；新负面类型必须先在这里登记。
extends RefCounted
class_name AdventurePlantNegativeEffects

## 妇人的悲寒从首次命中才加载颜色材质。
const CailleachGrief = preload("res://scripts/character/zombie_boss/cailleach/cailleach_plant_grief.gd")

## 现有负面状态类型。数值仅为接口标识，不进入存档。
enum Kind {
	DEGRADATION, ## 永久增伤与减攻；原有最强通道与可选叠加通道独立保存。
	NULLIFICATION, ## 来源独立的活动封锁；保留受击与铲除接口。
	ICE_SLOW, ## 具有原生时长的减速，保留角色自身的寒冷免疫。
	ICE_FREEZE, ## 具有原生时长的冻结。
	STUN, ## 使可受控的僵尸或植物暂停行动，重复命中刷新时长。
	POISON, ## 每半秒造成本体最大生命 2% 的普通伤害，层数按秒数解释。
	CHARM, ## 调用角色原有魅惑入口，保留物种与僵王的魅惑免疫。
	BURN, ## 独立半秒灼烧，层数表示持续秒数；共享原生火豆命中视觉。
	FREEZE_CHARGE, ## 累积冻结值，仅降低移动速度，满十点调用原生冰冻。
	FEAR, ## 限时反向逃跑，保持阵营并独立抑制攻击。
	SILENCE, ## 限时禁用等阶能力，保留基础成长及原生行为。
	SUN_INFUSION, ## 阳光豆式受伤产光，一次赋予一层实伤转换。
	DETONATION_CHARGE, ## 目标累积十点后清零，并交给来源快照引爆一格。
	RESENTMENT, ## 永久且不叠伤的每秒损血，黑白滤镜独立于其他状态。
	BRITTLENESS, ## 仅增加承伤的脆弱层数。
	DEEP_COLD, ## 抗火寒冷，冻结和减速有独立的持续时间。
	SORROW_COLD, ## 妇人的逐层减速，十层时停止植物行动。
	CACTUS_WOUND, ## 创伤每层给后续的非零攻击增加一点固定伤害。
	CACTUS_SHOCK, ## 感电在实际消耗血池后释放受限的局部闪电链。
	CACTUS_THUNDER, ## 惊雷满五层对目标脚下的真实格子落雷。
}

## [param target] 目标角色；[param kind] 为已登记状态；[param source_id] 用于独立解除无效化。
## [param amount] 为劣化比例或限时效果秒数；[param followup] 是冰冻结束后的减速秒数。
## [param context] 的 stackable 令劣化叠加；family 与 cap 可给指定效果族单独封顶，旧通道不受影响。
## on_detonate 接收世界位置与行号，由来源快照安排延迟引爆；同目标十点只回调一次。
## on_kill 是持续伤害的击杀回调，接收实际死亡者；调用方应保存可脱离母株的来源快照。
## 灼烧可提供 final_multiplier、before_death 和 source_active，分别控制末乘、致死前观察和来源边界。
## 脆弱的 amount 为层数；深寒的 amount 为减速秒数，followup 为冻结秒数，battle 和 statuses 为冻结来源及受击位。
## 冻结值 context 可用 control_only 禁用附伤，并以 freeze_hit_scope 观察原生附伤。
## 返回是否接受请求；死亡、非法状态或对应状态免疫返回 false，伤害无敌不等同于状态免疫。
static func apply(target: Character000Base, kind: Kind, source_id: int = 0,
		amount: float = 0.0, followup: float = 0.0, context: Dictionary = {}) -> bool:
	if not is_instance_valid(target) or target.is_death or target.is_queued_for_deletion() \
			or not is_finite(amount) or not target.can_receive_negative_effects():
		return false
	# 控制免疫只拒绝行动限制，毒、灼烧、劣化、脆弱等伤害状态仍由原分支处理。
	if not target.can_receive_control_effects() and kind in [Kind.NULLIFICATION, Kind.ICE_SLOW,
			Kind.ICE_FREEZE, Kind.STUN, Kind.CHARM, Kind.FREEZE_CHARGE, Kind.FEAR,
			Kind.SILENCE, Kind.DEEP_COLD, Kind.SORROW_COLD]:
		return false
	var plant: Plant000Base = target as Plant000Base # 植物沿用原有负面效果总免疫。
	var zombie: Zombie000Base = target as Zombie000Base # 普通僵尸沿用原生负面状态入口。
	if plant != null:
		if plant.battle_negative_effect_immune:
			return false
	elif (zombie == null and not target is ZB000Base) or target.is_hypno \
			or not target.is_inside_tree() \
			or target.character_init_type != Character000Base.E_CharacterInitType.IsNorm:
		return false
	match kind:
		Kind.DEGRADATION:
			if not is_instance_valid(target.hp_component) or amount <= 0.0:
				return false
			if context.has("family") or context.has("cap"):
				var family: Variant = context.get("family", &"") # 家族必须显式命名，不能误封顶旧的全局叠加池。
				var cap: Variant = context.get("cap", 0.0) # 上限沿用比例单位，0.5 表示 50%。
				if not (family is String or family is StringName) or StringName(family).is_empty() \
						or not (cap is float or cap is int) or not is_finite(float(cap)) or float(cap) <= 0.0 \
						or not bool(context.get("stackable", false)):
					return false
				target.hp_component.apply_capped_degradation(amount, float(cap), StringName(family))
			else:
				target.hp_component.apply_degradation(amount, bool(context.get("stackable", false)))
		Kind.NULLIFICATION:
			if plant == null or source_id == 0:
				return false
			AdventurePlantNullification.grant(plant, source_id)
		Kind.ICE_SLOW:
			if amount <= 0.0 or not target.can_receive_cold():
				return false
			target.be_ice_decelerate(amount)
			return target.influence_speed_factors.get(
				Character000Base.E_Influence_Speed_Factor.IceDecelerateSpeed, 1.0) < 1.0
		Kind.ICE_FREEZE:
			if amount <= 0.0 or not is_finite(followup) or not target.can_receive_cold():
				return false
			target.be_ice_freeze(amount, maxf(0.0, followup))
		Kind.STUN:
			if amount <= 0.0 or (plant == null and zombie == null):
				return false
			if plant != null:
				AdventurePlantNullification.grant_stun(plant, amount)
			else:
				zombie.be_stunned(amount)
		Kind.POISON, Kind.BURN:
			var on_kill: Variant = context.get("on_kill", Callable()) # 非法回调不能进入延迟状态。
			if not on_kill is Callable:
				return false
			if kind == Kind.POISON:
				return AdventurePoisonEffect.apply_to(target, amount, on_kill)
			var multiplier: Variant = context.get("final_multiplier", 1.0) # 末乘仅对本次登记的灼烧来源有效。
			var before_death: Variant = context.get("before_death", Callable()) # 可选观察口须为可调用值。
			if not (multiplier is float or multiplier is int) or not is_finite(float(multiplier)) \
					or float(multiplier) < 0.0 or not before_death is Callable \
					or not context.get("source_active", Callable()) is Callable:
				return false
			return AdventureBurnEffect.apply_to(target, amount, on_kill, context)
		Kind.FREEZE_CHARGE:
			return AdventureFreezeChargeEffect.apply_to(target, amount, bool(context.get("control_only", false)),
				context.get("freeze_hit_scope") as CombatHitScope)
		Kind.BRITTLENESS:
			if zombie == null or not is_instance_valid(target.hp_component) or amount < 1.0:
				return false
			target.hp_component.add_brittleness(int(minf(amount, HpComponent.MAX_BRITTLENESS_STACKS)))
		Kind.DEEP_COLD:
			var battle := context.get("battle") as RepeaterShotContext # 用真实来源限制抗火状态的生命周期。
			return AdventureDeepCold.apply_to(zombie, battle, amount, followup, int(context.get("statuses", 1)))
		Kind.DETONATION_CHARGE:
			var on_detonate: Variant = context.get("on_detonate", Callable()) # 必须冻结来源回调，状态自身不依赖弹体。
			if not on_detonate is Callable:
				return false
			return AdventureDetonationChargeEffect.apply_to(target, amount, on_detonate)
		Kind.RESENTMENT:
			var resentment_kill: Variant = context.get("on_kill", Callable()) # 永久跳伤仍沿用真实击杀归属。
			if not resentment_kill is Callable:
				return false
			return AdventureResentmentEffect.apply_to(target, resentment_kill)
		Kind.FEAR:
			return AdventureFearEffect.apply_to(target, amount)
		Kind.SILENCE:
			return AdventureSilenceEffect.apply_to(target, amount)
		Kind.SUN_INFUSION:
			return AdventureSunBeanEffect.apply_to(target)
		Kind.SORROW_COLD:
			return plant != null and plant.is_inside_tree() and plant.is_node_ready() \
				and plant.character_init_type == Character000Base.E_CharacterInitType.IsNorm \
				and CailleachGrief.apply_to(plant, int(clampf(amount, 0.0, CailleachGrief.MAX_STACKS)))
		Kind.CACTUS_WOUND, Kind.CACTUS_SHOCK, Kind.CACTUS_THUNDER:
			var runtime := context.get("cactus_runtime") as Node # 出战快照指定当前战场的共享结算器。
			return zombie != null and amount > 0.0 and is_instance_valid(runtime) \
				and runtime.apply_status(zombie, kind, int(amount), context.get("shot"))
		Kind.CHARM:
			if plant != null:
				return false
			target.be_hypno()
			if not target.is_hypno:
				return false
			SoundManager.play_character_SFX("MindControlled")
		_:
			return false
	return true

## [param plant] 目标；[param kind] 状态类型；[param source_id] 原授予来源；
## [param persistent] 来源消失后仍永久保留无效化时置 true。
## 仅无效化支持外部解除；劣化永久持续，限时状态由各自的计时器结束。
static func release(plant: Plant000Base, kind: Kind, source_id: int,
		persistent: bool = false) -> void:
	if not is_instance_valid(plant):
		return
	if kind == Kind.NULLIFICATION:
		AdventurePlantNullification.release(plant, source_id, persistent)

## 净化 [param plant] 的无效化、劣化、原生寒冷和公共持续伤害。
static func purge(plant: Plant000Base) -> void:
	if not is_instance_valid(plant) or plant.is_death or plant.is_queued_for_deletion():
		return
	CailleachGrief.clear_from(plant)
	AdventurePlantNullification.purge(plant)
	plant.hp_component.clear_degradation()
	plant.clear_cold()
	for child: Node in plant.get_children(): # 仅清公共周期负面节点，保留其余组件和来源。
		if child is AdventurePeriodicDamageEffect:
			child.clear()
