## Typed pre-tree plant spawn configuration. Keeps generic planting independent
## from adventure cards, research rules and other game modes.
extends RefCounted
class_name PlantSpawnModifier

func apply(_plant: Plant000Base, _snapshot: Dictionary) -> bool:
	return false

## Optional card presentation values calculated from original registry values.
func card_stats(_snapshot: Dictionary, base_sun_cost: int, base_cooldown: float) -> Dictionary:
	return {"sun_cost": base_sun_cost, "cooldown": base_cooldown}

## 玩家主种植成功后接收一次通知；默认无附加效果，不负责费用或冷却结算。
## [param _cell] 为已成功占用的中心格；[param _profile] 是本次使用的冻结配置。
func player_placement_committed(_cell: PlantCell, _profile: PlantSpawnProfile) -> void:
	pass
