## One synchronous memory-and-save transaction; restores original card objects on failure.
## Caller injects the current player's state, inventory, currency and SaveService callback.
extends RefCounted
class_name AdventureResearchTransaction

static func commit(state: AdventureState, inventory: AdventureInventoryService,
		wallet: GlobalGameState, persist: Callable, plan: Dictionary) -> Dictionary:
	if state == null or inventory == null or wallet == null or not persist.is_valid():
		return {"ok": false, "message": "玩家状态不可用。"}
	var fee: int = int(plan.get("fee", -1))
	var consume: Dictionary = plan.get("consume", {})
	var remove_uids: Array = plan.get("remove_uids", [])
	var created_type: int = int(plan.get("create_type", 0))
	var update_uid: String = str(plan.get("update_uid", ""))
	var promotion_id: String = str(plan.get("promotion_id", ""))
	var promotion_tier: int = int(plan.get("promotion_tier", 0))
	if fee < 0 or fee > wallet.coin_value:
		return {"ok": false, "message": "金币不足。"}
	for id: String in consume:
		if not ItemRegistry.has_item(id) or not PlantCardInstance.is_positive_integer(consume[id]) \
				or inventory.get_item_count(id) < int(consume[id]):
			return {"ok": false, "message": "材料或道具不足。"}
	if created_type != 0 and (not PlantCardInstance.is_plant_type(created_type)
			or state.next_card_id >= PlantCardInstance.MAX_JSON_INTEGER):
		return {"ok": false, "message": "无法分配新卡。"}
	if not update_uid.is_empty() and not state.cards.has(update_uid):
		return {"ok": false, "message": "目标卡已不存在。"}
	var before_cards: Dictionary = state.cards.duplicate()
	var before_items: Dictionary = state.items.duplicate(true)
	var before_order: Array[String] = state.card_order_uids.duplicate()
	var before_deck: Array[String] = state.selected_card_uids.duplicate()
	var before_next: int = state.next_card_id
	var before_coin: int = wallet.coin_value
	var before_target: Dictionary = state.cards[update_uid].to_dict() if state.cards.has(update_uid) else {}
	var result_uid := ""
	var completed := true
	for id: String in consume:
		if not inventory.consume_item(id, int(consume[id])):
			completed = false
			break
	if completed:
		for uid: Variant in remove_uids:
			if typeof(uid) != TYPE_STRING or uid == update_uid or not inventory.remove_card(uid):
				completed = false
				break
	if completed and created_type != 0:
		result_uid = inventory.add_card(created_type, 0)
		completed = not result_uid.is_empty()
	if completed and not promotion_id.is_empty():
		completed = state.cards[update_uid].set_promotion(promotion_tier, promotion_id)
	if completed:
		wallet.coin_value -= fee
		completed = persist.call() == true
	if completed:
		return {"ok": true, "message": "操作成功。", "uid": result_uid}
	_restore(state, wallet, before_cards, before_items, before_order,
		before_deck, before_next, before_coin, update_uid, before_target)
	return {"ok": false, "message": "操作或存档失败，所有资产已恢复。"}

static func _restore(state: AdventureState, wallet: GlobalGameState,
		cards: Dictionary, items: Dictionary, order: Array[String],
		deck: Array[String], next_id: int, coins: int, uid: String, card_data: Dictionary) -> void:
	state.cards.clear()
	for id: String in cards:
		state.cards[id] = cards[id]
	state.items.clear()
	for id: String in items:
		state.items[id] = int(items[id])
	state.card_order_uids = order
	state.selected_card_uids = deck
	state.next_card_id = next_id
	if state.cards.has(uid) and not card_data.is_empty():
		var card: PlantCardInstance = state.cards[uid]
		card.stars = int(card_data.stars)
		for field: String in PlantCardInstance.PROMOTION_FIELDS:
			card.set(field, str(card_data.get(field, "")))
	wallet.coin_value = coins
