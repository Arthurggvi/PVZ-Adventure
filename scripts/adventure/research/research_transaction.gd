## Single asset transaction. Accepts only a typed operation and re-quotes live
## state through the authoritative service before any mutation or save.
extends RefCounted
class_name AdventureResearchTransaction

const Recipes = preload("res://scripts/adventure/research/research_recipe_catalog.gd")
const Promotions = preload("res://scripts/adventure/research/research_promotion_catalog.gd")
const Enhancement = preload("res://scripts/adventure/research/research_enhancement_rules.gd")

static func commit(state: AdventureState, inventory: AdventureInventoryService,
		wallet: GlobalGameState, persist: Callable, operation: AdventureResearchOperation,
		quote: Callable) -> Dictionary:
	if state == null or inventory == null or wallet == null or operation == null \
			or not quote.is_valid() or not persist.is_valid():
		return _error("研究所事务上下文不可用。")
	if wallet.adventure_state != state or not inventory.owns_state(state):
		return _error("玩家档案已切换，拒绝跨档操作。")
	var preview: Dictionary = quote.call(operation.mode(), operation.choice())
	if not preview.get("ready", false):
		return _error(str(preview.get("message", "操作条件不满足。")))
	var fee := -1
	var consume: Dictionary = {}
	var remove_uids: Array = []
	var created_type := 0
	var updated_uid := ""
	var resulting_stars := -1
	var promotion_tier := 0
	var promotion_id := ""
	var succeeded := false
	match operation.kind:
		AdventureResearchOperation.Kind.CRAFT:
			var recipe: Dictionary = Recipes.definition(operation.recipe_id)
			if recipe.is_empty():
				return _error("未知配方。")
			fee = Recipes.COST
			created_type = int(recipe.plant_type)
			consume[operation.recipe_id] = 1
			for material: String in recipe.materials:
				consume[material] = 1
		AdventureResearchOperation.Kind.PROMOTE:
			var book: Dictionary = Promotions.definition(operation.book_id)
			var target: PlantCardInstance = state.cards.get(operation.card_uid)
			if book.is_empty() or target == null or not Promotions.is_valid_chain(target):
				return _error("转职数据无效。")
			promotion_tier = Promotions.next_tier(target)
			if promotion_tier == 0 or promotion_tier != int(book.tier) \
					or target.plant_type != int(book.plant_type) \
					or target.stars < Promotions.REQUIREMENTS[promotion_tier - 1]:
				return _error("当前卡片不满足该技能书条件。")
			fee = Promotions.COST
			updated_uid = target.uid
			promotion_id = operation.book_id
			consume[promotion_id] = 1
		AdventureResearchOperation.Kind.ENHANCE:
			var target: PlantCardInstance = state.cards.get(operation.card_uid)
			var chance: Variant = preview.get("chance")
			if target == null or chance == null or typeof(chance) not in [TYPE_INT, TYPE_FLOAT] \
					or not is_finite(chance) or chance < 0.0 or chance > 1.0:
				return _error("强化概率规则未就绪。")
			if not Enhancement.validate(state, operation.card_uid, operation.material_uids,
					operation.use_pot, operation.fertilizer_id, operation.growth_agent_id).is_empty():
				return _error("强化材料状态已变化。")
			fee = Enhancement.COST
			updated_uid = target.uid
			remove_uids = operation.material_uids.duplicate()
			if operation.use_pot:
				consume["seedling_pot"] = Enhancement.protection_count(target.stars + 1)
			if not operation.fertilizer_id.is_empty():
				consume[operation.fertilizer_id] = 1
			if not operation.growth_agent_id.is_empty():
				consume[operation.growth_agent_id] = 1
			succeeded = randf() < float(chance)
			resulting_stars = Enhancement.result_star(target.stars, succeeded, operation.use_pot)
		_:
			return _error("未知研究操作。")
	if fee < 0 or fee > wallet.coin_value:
		return _error("金币不足。")
	for id: String in consume:
		if not ItemRegistry.has_item(id) or not PlantCardInstance.is_positive_integer(consume[id]) \
				or inventory.get_item_count(id) < int(consume[id]):
			return _error("材料或道具不足。")
	if created_type != 0 and (not PlantCardInstance.is_plant_type(created_type)
			or state.next_card_id >= PlantCardInstance.MAX_JSON_INTEGER):
		return _error("无法分配新卡。")
	var before_cards: Dictionary = state.cards.duplicate()
	var before_items: Dictionary = state.items.duplicate(true)
	var before_order: Array[String] = state.card_order_uids.duplicate()
	var before_deck: Array[String] = state.selected_card_uids.duplicate()
	var before_next: int = state.next_card_id
	var before_coin: int = wallet.coin_value
	var before_quests: Dictionary = state.quests.to_dict() # 制卡进度与卡片资产在同一保存边界提交。
	var before_steps: Dictionary = state.tutorial_steps.duplicate() # 坚果教学完成标记随失败事务回滚。
	var before_discoveries: Dictionary = state.almanac_discoveries.duplicate() # 合成保存失败时，未真正获得的物种不能留在图鉴。
	var before_target: Dictionary = state.cards[updated_uid].to_dict() if state.cards.has(updated_uid) else {}
	var completed := true
	for id: String in consume:
		if not inventory.consume_item(id, int(consume[id])):
			completed = false
			break
	if completed:
		for uid: Variant in remove_uids:
			if typeof(uid) != TYPE_STRING or uid == updated_uid or not inventory.remove_card(uid):
				completed = false
				break
	var result_uid := ""
	if completed and created_type != 0:
		result_uid = inventory.add_card(created_type, 0)
		completed = not result_uid.is_empty()
	if completed and not promotion_id.is_empty():
		completed = state.cards[updated_uid].set_promotion(promotion_tier, promotion_id)
	if completed and resulting_stars >= 0:
		state.cards[updated_uid].stars = resulting_stars
	if completed:
		wallet.coin_value -= fee
		if operation.kind == AdventureResearchOperation.Kind.CRAFT:
			AdventureQuestService.record_event(state, "card_crafted", operation.recipe_id, AdventureQuestService.today())
			if operation.recipe_id == "recipe_wall_nut":
				state.tutorial_steps["research_wall_nut"] = true
		completed = persist.call() == true
	if not completed:
		state.quests = AdventureQuestState.from_dict(before_quests)
		state.tutorial_steps.assign(before_steps)
		state.almanac_discoveries.assign(before_discoveries)
		_restore(state, wallet, before_cards, before_items, before_order,
			before_deck, before_next, before_coin, updated_uid, before_target)
		return _error("操作或存档失败，所有资产已恢复。")
	return {"ok": true, "message": "操作成功。", "uid": result_uid,
		"success": succeeded, "stars": resulting_stars}

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

static func _error(message: String) -> Dictionary:
	return {"ok": false, "message": message}
