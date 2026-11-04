## 事件产生的战利品和地区标记只进入本局待结算账本；不触碰用户库存/磁盘。
extends RefCounted
class_name AdventureBattleEventLedger

static func apply(event: StageEventDefinition, items: Dictionary,
		region_flags: Dictionary, rng: RandomNumberGenerator) -> bool:
	match event.action:
		StageEventDefinition.Action.REQUEST_DROP:
			var result: Dictionary = AdventureRewardService.roll(event.action_drop_table, rng)
			if not result.get("ok", false):
				return false
			var rolled: Dictionary = result["items"]
			for item_id: String in rolled:
				var qty: int = int(rolled[item_id])
				var original: int = int(items.get(item_id, 0))
				if qty < 0 or original > PlantCardInstance.MAX_JSON_INTEGER - qty:
					return false
			for item_id: String in rolled:
				items[item_id] = int(items.get(item_id, 0)) + int(rolled[item_id])
			return true
		StageEventDefinition.Action.SET_REGION_FLAG:
			region_flags[event.action_target_id] = event.action_flag_value == StageEventDefinition.FlagValue.ON
			return true
	return false
