## 战斗负面状态入口，统一判定目标类型与免疫，并派发给角色自身。
## 各状态自身仍持有其生命周期；新负面类型必须先在这里登记。
extends RefCounted
class_name AdventurePlantNegativeEffects

## 现有负面状态类型。数值仅为接口标识，不进入存档。
enum Kind {
	DEGRADATION, ## 受到更多伤害且输出下降，采用最强强度、永久持续。
	NULLIFICATION, ## 来源独立的活动封锁；保留受击与铲除接口。
	ICE_SLOW, ## 具有原生时长的减速。
	ICE_FREEZE, ## 具有原生时长的冻结。
	STUN, ## 使可受控的僵尸暂停行动，重复命中刷新时长。
}

## [param target] 目标角色；[param kind] 受支持的状态类型；
## [param source_id] 来源实例 ID，用于无效化的独立移除；
## [param amount] 劣化强度或限时效果的秒数，[param followup] 冰冻结束后减速秒数。
## 返回是否接受了这次状态请求；免疫、非法状态或无效目标返回 false。
static func apply(target: Character000Base, kind: Kind, source_id: int = 0,
		amount: float = 0.0, followup: float = 0.0) -> bool:
	if not is_instance_valid(target) or target.is_death or target.is_queued_for_deletion():
		return false
	if kind == Kind.STUN:
		# 普通僵尸沿用独立的控制计时，僵王保留速度控制免疫。
		var zombie: Zombie000Base = target as Zombie000Base
		if zombie == null or zombie.is_hypno or not zombie.is_inside_tree() \
				or zombie.character_init_type != Character000Base.E_CharacterInitType.IsNorm \
				or not is_finite(amount) or amount <= 0.0:
			return false
		zombie.be_stunned(amount)
		return true
	# 其余状态沿用植物专用的免疫判定。
	var plant: Plant000Base = target as Plant000Base
	if plant == null or plant.battle_negative_effect_immune:
		return false
	match kind:
		Kind.DEGRADATION:
			if not is_instance_valid(plant.hp_component) or amount <= 0.0:
				return false
			plant.hp_component.apply_degradation(amount)
		Kind.NULLIFICATION:
			if source_id == 0:
				return false
			AdventurePlantNullification.grant(plant, source_id)
		Kind.ICE_SLOW:
			if amount <= 0.0:
				return false
			plant.be_ice_decelerate(amount)
		Kind.ICE_FREEZE:
			if amount <= 0.0:
				return false
			plant.be_ice_freeze(amount, maxf(0.0, followup))
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
