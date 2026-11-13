## Typed pre-tree plant spawn configuration. Keeps generic planting independent
## from adventure cards, research rules and other game modes.
extends RefCounted
class_name PlantSpawnModifier

func apply(_plant: Plant000Base, _snapshot: Dictionary) -> bool:
	return false

## Optional card presentation values calculated from original registry values.
func card_stats(_snapshot: Dictionary, base_sun_cost: int, base_cooldown: float) -> Dictionary:
	return {"sun_cost": base_sun_cost, "cooldown": base_cooldown}

## 返回 [param _snapshot] 对应卡片占用的选卡名额；普通卡默认占1格。
func selection_slot_cost(_snapshot: Dictionary) -> int:
	return 1

## 由 [param _snapshot] 投影 [param base_condition]；默认原样返回，不修改共享注册资源。
func placement_condition(_snapshot: Dictionary, base_condition: ResourcePlantCondition) -> ResourcePlantCondition:
	return base_condition

## 玩家主种植成功后接收一次通知；默认无附加效果，不负责费用或冷却结算。
## [param _cell] 为已成功占用的中心格；[param _profile] 是本次使用的冻结配置。
func player_placement_committed(_cell: PlantCell, _profile: PlantSpawnProfile) -> void:
	pass
