## 植物负面状态唯一公开入口：施加/解除均由此处完成免疫判定和类型派发。
## 各状态自身仍持有其生命周期；新负面类型必须先在这里登记。
extends RefCounted
class_name AdventurePlantNegativeEffects

## 现有负面状态类型。数值仅为接口标识，不进入存档。
enum Kind {
	DEGRADATION, ## 受到更多伤害且输出下降，采用最强强度、永久持续。
	NULLIFICATION, ## 来源独立的活动封锁；保留受击与铲除接口。
	ICE_SLOW, ## 具有原生时长的减速。
	ICE_FREEZE, ## 具有原生时长的冻结。
}

## [param plant] 目标植物；[param kind] 受支持的状态类型；
## [param source_id] 来源实例 ID，用于无效化的独立移除；
## [param amount] 劣化强度或冰冻/减速时间（秒），[param followup] 冰冻结束后减速秒数。
## 返回是否接受了这次状态请求；免疫、非法状态或无效目标返回 false。
static func apply(plant: Plant000Base, kind: Kind, source_id: int = 0,
		amount: float = 0.0, followup: float = 0.0) -> bool:
	if not is_instance_valid(plant) or plant.is_death or plant.is_queued_for_deletion() \
			or plant.battle_negative_effect_immune:
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
## 当前仅无效化支持外部解除；劣化为永久叠加强度，冰冻和减速由各自计时器结束。
static func release(plant: Plant000Base, kind: Kind, source_id: int,
		persistent: bool = false) -> void:
	if not is_instance_valid(plant):
		return
	if kind == Kind.NULLIFICATION:
		AdventurePlantNullification.release(plant, source_id, persistent)
