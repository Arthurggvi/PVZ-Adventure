## Query/validate/execute for the three lab modes; never stores a parallel inventory.
extends RefCounted
class_name AdventureResearchService

const Recipes = preload("res://scripts/adventure/research/research_recipe_catalog.gd")
const Promotions = preload("res://scripts/adventure/research/research_promotion_catalog.gd")
const Enhancement = preload("res://scripts/adventure/research/research_enhancement_rules.gd")
const Transaction = preload("res://scripts/adventure/research/research_transaction.gd")
var state: AdventureState
var inventory: AdventureInventoryService
var wallet: GlobalGameState
var persist: Callable

func _init(current: AdventureState, stock: AdventureInventoryService,
		currency: GlobalGameState, save_callback: Callable) -> void:
	state = current
	inventory = stock
	wallet = currency
	persist = save_callback

func options(mode: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if mode == "craft":
		for id: String in Recipes.all_ids():
			if inventory.get_item_count(id) > 0:
				var definition: Dictionary = Recipes.definition(id)
				definition["title"] = ItemRegistry.get_item_definition(id).get("name", id)
				entries.append(definition)
	elif mode == "upgrade" or mode == "promotion":
		for card: Dictionary in inventory.list_cards():
			if mode == "promotion" and Promotions.options(state.cards[card.uid]).is_empty():
				continue
			entries.append(card)
	return entries

func quote(mode: String, choice: Dictionary) -> Dictionary:
	match mode:
		"craft":
			return _craft_quote(str(choice.get("recipe_id", "")))
		"upgrade":
			return _upgrade_quote(choice)
		"promotion":
			return _promotion_quote(choice)
	return {"ready": false, "message": "未知研究功能。"}

func _craft_quote(id: String) -> Dictionary:
	var recipe: Dictionary = Recipes.definition(id)
	if recipe.is_empty():
		return {"ready": false, "message": "请选择已登记的制作书。"}
	var material_slots: Array[Dictionary] = []
	var enough := inventory.get_item_count(id) > 0 and wallet.coin_value >= Recipes.COST
	for material_id: String in recipe.materials:
		var owned: int = inventory.get_item_count(material_id)
		material_slots.append({"id": material_id, "owned": owned, "required": 1})
		if owned < 1:
			enough = false
	recipe["slots"] = material_slots
	recipe["ready"] = enough
	recipe["message"] = "可合成" if enough else "缺少制作书、材料或金币。"
	return recipe

func _upgrade_quote(choice: Dictionary) -> Dictionary:
	var uid: String = str(choice.get("uid", ""))
	var main: PlantCardInstance = state.cards.get(uid)
	var consumed: Array = choice.get("materials", [])
	var pot: bool = bool(choice.get("use_pot", false))
	var fertilizer: String = str(choice.get("fertilizer", ""))
	var pot_cost: int = Enhancement.protection_count(main.stars + 1) if main != null else 0
	var material_cards: Array[Dictionary] = []
	for card_uid: Variant in consumed:
		material_cards.append(inventory.get_card(str(card_uid)))
	var data := {"ready": false, "uid": uid, "type": main.plant_type if main else 0,
		"fee": Enhancement.COST, "pot_required": pot_cost,
		"pot_owned": inventory.get_item_count("seedling_pot"),
		"materials": consumed.duplicate(), "material_cards": material_cards,
		"use_pot": pot, "fertilizer": fertilizer,
		"stars": main.stars if main else 0}
	var issue: String = Enhancement.validate(state, uid, consumed, pot, fertilizer)
	if issue.is_empty() and wallet.coin_value < Enhancement.COST:
		issue = "金币不足。"
	if not issue.is_empty():
		data["message"] = issue
		return data
	var chance: Variant = Enhancement.success_probability(main, consumed, fertilizer)
	if chance == null:
		data["message"] = "概率算法未定义：强化执行暂不可用。"
		return data
	data["chance"] = chance
	data["ready"] = true
	data["message"] = "可强化"
	return data

func _promotion_quote(choice: Dictionary) -> Dictionary:
	var uid: String = str(choice.get("uid", ""))
	var book_id: String = str(choice.get("book_id", ""))
	var card: PlantCardInstance = state.cards.get(uid)
	if card == null:
		return {"ready": false, "message": "请选择植物卡。"}
	var tier: int = Promotions.next_tier(card)
	var branches: Array[Dictionary] = Promotions.options(card)
	var data := {"ready": false, "uid": uid, "type": card.plant_type,
		"stars": card.stars, "tier": tier, "fee": Promotions.COST,
		"branches": branches, "book_id": book_id}
	for branch: Dictionary in branches:
		branch["owned"] = inventory.get_item_count(str(branch.id))
	if tier == 0 or branches.is_empty():
		data["message"] = "当前没有已定义的转职路线。"
		return data
	if card.stars < Promotions.REQUIREMENTS[tier - 1]:
		data["message"] = "第%d次转职要求至少%d星。" % [tier, Promotions.REQUIREMENTS[tier - 1]]
		return data
	if not branches.any(func(entry: Dictionary) -> bool: return entry.id == book_id):
		data["message"] = "请选择这一阶段的转职书。"
		return data
	if inventory.get_item_count(book_id) < 1 or wallet.coin_value < Promotions.COST:
		data["message"] = "缺少转职书或金币。"
		return data
	data["ready"] = true
	data["message"] = "转职不影响星级，选择后不可撤销。"
	return data

## Re-quotes live state; never trusts display snapshots as executable commands.
func execute(mode: String, choice: Dictionary) -> Dictionary:
	var preview: Dictionary = quote(mode, choice)
	if not preview.get("ready", false):
		return {"ok": false, "message": str(preview.get("message", "条件不满足。"))}
	var plan: Dictionary = {}
	match mode:
		"craft":
			var id: String = str(choice.recipe_id)
			var ingredients: Dictionary = {id: 1}
			for material_id: String in preview.materials:
				ingredients[material_id] = 1
			plan = {"fee": Recipes.COST, "consume": ingredients,
				"create_type": int(preview.plant_type)}
		"promotion":
			plan = {"fee": Promotions.COST, "consume": {str(choice.book_id): 1},
				"update_uid": str(choice.uid), "promotion_tier": int(preview.tier),
				"promotion_id": str(choice.book_id)}
		"upgrade":
			return {"ok": false, "message": "强化概率尚未定义，未扣除任何资源。"}
		_:
			return {"ok": false, "message": "未知操作。"}
	return Transaction.commit(state, inventory, wallet, persist, plan)
