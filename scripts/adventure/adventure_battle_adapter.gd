## 冒险卡实例和原版模板卡牌的唯一适配点；不拥有玩家资产或场景。
extends RefCounted
class_name AdventureBattleAdapter

## 临时卡共用无法被库存分配或从存档恢复的来源编号，避免植株收益触及背包实卡。
const TEMPORARY_SOURCE_UID: String = "PC%d" % PlantCardInstance.MAX_JSON_INTEGER

## The only adventure-side factory for validated plant spawn configurations.
static func profile_for(snapshot: Dictionary) -> PlantSpawnProfile:
	var card: PlantCardInstance = PlantCardInstance.from_dict(snapshot)
	if card == null or not AdventurePromotionCatalog.is_valid_chain(card):
		return null
	return PlantSpawnProfile.create(snapshot, AdventureResearchBattleEffects.new())

## 用 [param snapshot] 生成升一星、最多十星的临时种植配方，保持所有转职分支。
## 卡片实例由战场独立持有，临时配方只用于数值和植株收益归属。
static func delivery_profile_for(snapshot: Dictionary) -> PlantSpawnProfile:
	var delivery: Dictionary = snapshot.duplicate(true) # 不改写玩家背包数据。
	delivery["uid"] = TEMPORARY_SOURCE_UID
	delivery["stars"] = mini(int(snapshot.get("stars", 0)) + 1, PlantCardInstance.MAX_STARS)
	return profile_for(delivery)

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
static func binding_at(loadout: Array[Dictionary], slot_index: int, card_reference: ResourceCardReference) -> Dictionary:
	if slot_index < 0 or slot_index >= loadout.size() or card_reference == null:
		return {}
	if card_reference.card_type != ResourceCardReference.CardType.Plant or card_reference.is_imitater:
		return {}
	var snapshot: Dictionary = loadout[slot_index]
	if int(snapshot.get("plant_type", -1)) != card_reference.content_id:
		return {}
	return snapshot.duplicate(true)
