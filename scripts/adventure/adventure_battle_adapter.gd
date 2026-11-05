## 冒险卡实例和原版模板卡牌的唯一适配点；不拥有玩家资产或场景。
extends RefCounted
class_name AdventureBattleAdapter

## The only adventure-side factory for validated plant spawn configurations.
static func profile_for(snapshot: Dictionary) -> PlantSpawnProfile:
	var card: PlantCardInstance = PlantCardInstance.from_dict(snapshot)
	if card == null or not AdventurePromotionCatalog.is_valid_chain(card):
		return null
	return PlantSpawnProfile.create(snapshot, AdventureResearchBattleEffects.new())

## 在关卡入口冻结选中的独立卡数据；战斗中不再读取可变玩家库存。
static func create_loadout(state: AdventureState) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if state == null or state.selected_card_uids.is_empty():
		return result
	for uid: String in state.selected_card_uids:
		var card: PlantCardInstance = state.cards.get(uid)
		if card == null:
			return []
		var snapshot: Dictionary = card.to_dict()
		if snapshot.is_empty() or snapshot.get("uid") != uid:
			return []
		result.append(snapshot.duplicate(true))
	return result

## 通过卡槽次序匹配 UID，不能用物种编号反查（同种植物可有多个实例）。
static func binding_at(loadout: Array[Dictionary], slot_index: int, reference: ResourceCardReference) -> Dictionary:
	if slot_index < 0 or slot_index >= loadout.size() or reference == null:
		return {}
	if reference.card_type != ResourceCardReference.CardType.Plant or reference.is_imitater:
		return {}
	var snapshot: Dictionary = loadout[slot_index]
	if int(snapshot.get("plant_type", -1)) != reference.content_id:
		return {}
	return snapshot.duplicate(true)
