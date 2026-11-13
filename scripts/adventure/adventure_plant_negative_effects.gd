## 战斗负面状态入口，统一判定目标类型与免疫，并派发给角色自身。
## 各状态自身仍持有其生命周期；新负面类型必须先在这里登记。
extends RefCounted
class_name AdventurePlantNegativeEffects

## 现有负面状态类型。数值仅为接口标识，不进入存档。
enum Kind {
	DEGRADATION, ## 永久增伤与减攻；原有最强通道与可选叠加通道独立保存。
	NULLIFICATION, ## 来源独立的活动封锁；保留受击与铲除接口。
	ICE_SLOW, ## 具有原生时长的减速，保留角色自身的寒冷免疫。
	ICE_FREEZE, ## 具有原生时长的冻结。
	STUN, ## 使可受控的僵尸暂停行动，重复命中刷新时长。
	POISON, ## 每半秒造成本体最大生命 2% 的普通伤害，层数按秒数解释。
	CHARM, ## 调用角色原有魅惑入口，保留物种与僵王的魅惑免疫。
}

## [param target] 目标角色；[param kind] 为已登记状态；[param source_id] 用于独立解除无效化。
## [param amount] 为劣化比例或限时效果秒数；[param followup] 是冰冻结束后的减速秒数。
## [param context] 的 stackable 仅令劣化写入独立叠加通道，默认保留原有最强值规则；
## on_kill 是毒伤击杀回调，接收实际死亡的角色，调用方应保存可脱离母株的来源快照。
## 返回是否接受请求；死亡、非法状态或对应状态免疫返回 false，伤害无敌不等同于状态免疫。
static func apply(target: Character000Base, kind: Kind, source_id: int = 0,
		amount: float = 0.0, followup: float = 0.0, context: Dictionary = {}) -> bool:
	if not is_instance_valid(target) or target.is_death or target.is_queued_for_deletion() \
			or not is_finite(amount):
		return false
	var plant: Plant000Base = target as Plant000Base # 植物沿用原有负面效果总免疫。
	var zombie: Zombie000Base = target as Zombie000Base # 眩晕仅支持普通僵尸的独立行动计时。
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
			target.hp_component.apply_degradation(amount, bool(context.get("stackable", false)))
		Kind.NULLIFICATION:
			if plant == null or source_id == 0:
				return false
			AdventurePlantNullification.grant(plant, source_id)
		Kind.ICE_SLOW:
			if amount <= 0.0:
				return false
			target.be_ice_decelerate(amount)
			return target.influence_speed_factors.get(
				Character000Base.E_Influence_Speed_Factor.IceDecelerateSpeed, 1.0) < 1.0
		Kind.ICE_FREEZE:
			if plant == null or amount <= 0.0 or not is_finite(followup):
				return false
			plant.be_ice_freeze(amount, maxf(0.0, followup))
		Kind.STUN:
			if zombie == null or amount <= 0.0:
				return false
			zombie.be_stunned(amount)
		Kind.POISON:
			var on_kill: Variant = context.get("on_kill", Callable()) # 非法回调不能进入延迟状态。
			if not on_kill is Callable:
				return false
			return AdventurePoisonEffect.apply_to(target, amount, on_kill)
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
