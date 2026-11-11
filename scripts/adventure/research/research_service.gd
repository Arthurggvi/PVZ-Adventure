## Query/validate/execute for the three lab modes; never stores a parallel inventory.
extends RefCounted
class_name AdventureResearchService

const Recipes = preload("res://scripts/adventure/research/research_recipe_catalog.gd")
const Promotions = preload("res://scripts/adventure/research/research_promotion_catalog.gd")
const Enhancement = preload("res://scripts/adventure/research/research_enhancement_rules.gd")
const Transaction = preload("res://scripts/adventure/research/research_transaction.gd")
const Operation = preload("res://scripts/adventure/research/research_operation.gd")
## 当前物种和转职阶段没有可用路线时的提示。
const NO_PROMOTION_ROUTE := "当前没有已定义的转职路线。"
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
		entries = inventory.list_cards()
		for card: Dictionary in entries: # 不剔除不满足操作条件的已拥有卡。
			card["selection_issue"] = main_card_issue(mode, str(card.uid))
	return entries

## 返回 [param uid] 在 [param mode] 中不能放入主卡槽的原因；可放入时返回空字符串。
func main_card_issue(mode: String, uid: String) -> String:
	var card: PlantCardInstance = state.cards.get(uid) # 点击时从真实库存读取最新星级及转职状态。
	if card == null:
		return "该植物卡已不在背包。"
	if mode == "upgrade" and card.stars >= Enhancement.MAX_STARS:
		return "主卡已达到星级上限。"
	if mode == "promotion":
		var minimum: int = Promotions.REQUIREMENTS[0] # 主卡至少达到一转门槛；后续门槛由报价校验。
		if card.stars < minimum:
			return "%d 星及以上的植物卡才能进行转职。" % minimum
		if Promotions.options(card).is_empty():
			return NO_PROMOTION_ROUTE
	return ""

func quote(mode: String, choice: Dictionary) -> Dictionary:
	if not AdventureQuestService.feature_unlocked(state, "research"):
		return {"ready": false, "message": "领取「初次远征」奖励后解锁研究室。"}
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
		return {"ready": false, "message": "请选择已登记的配方。"}
	var material_slots: Array[Dictionary] = []
	var enough := inventory.get_item_count(id) > 0 and wallet.coin_value >= Recipes.COST
	for material_id: String in recipe.materials:
		var owned: int = inventory.get_item_count(material_id)
		material_slots.append({"id": material_id, "owned": owned, "required": 1})
		if owned < 1:
			enough = false
	recipe["slots"] = material_slots
	recipe["fee"] = Recipes.COST
	recipe["ready"] = enough
	recipe["message"] = "可合成" if enough else "缺少配方、材料或金币。"
	return recipe

func _upgrade_quote(choice: Dictionary) -> Dictionary:
	var uid: String = str(choice.get("uid", ""))
	var main: PlantCardInstance = state.cards.get(uid)
	var raw_materials: Variant = choice.get("materials", [])
	if not raw_materials is Array:
		return {"ready": false, "message": "耗材卡列表格式无效。"}
	var consumed: Array = raw_materials
	var pot: bool = bool(choice.get("use_pot", false))
	var fertilizer: String = str(choice.get("fertilizer", ""))
	var growth_agent: String = str(choice.get("growth_agent", "")) # 保底与肥料分别选择，可同场使用。
	var pot_cost: int = Enhancement.protection_count(main.stars + 1) if main != null else 0
	var material_cards: Array[Dictionary] = []
	for card_uid: Variant in consumed:
		material_cards.append(inventory.get_card(str(card_uid)))
	var data := {"ready": false, "uid": uid, "type": main.plant_type if main else 0,
		"fee": Enhancement.COST, "pot_required": pot_cost, "target_star": mini(Enhancement.MAX_STARS, int(main.stars) + 1) if main else 0,
		"pot_owned": inventory.get_item_count("seedling_pot"),
		"materials": consumed.duplicate(), "material_cards": material_cards,
		"use_pot": pot, "fertilizer": fertilizer, "growth_agent": growth_agent,
		"fertilizer_multiplier": Enhancement.fertilizer_multiplier(fertilizer),
		"stars": main.stars if main else 0}
	var issue: String = Enhancement.validate(state, uid, consumed, pot, fertilizer, growth_agent)
	if not issue.is_empty():
		data["message"] = issue
		return data
	var material_instances: Array[PlantCardInstance] = []
	for material_uid: Variant in consumed:
		material_instances.append(state.cards[str(material_uid)])
	var chance: Variant = Enhancement.success_probability(main, material_instances, fertilizer, growth_agent)
	if chance == null:
		data["message"] = "概率算法未定义：强化执行暂不可用。"
		return data
	if typeof(chance) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(chance) \
			or chance < 0.0 or chance > 1.0:
		data["message"] = "强化成功率返回值无效。"
		return data
	data["chance"] = chance
	# 余额只决定能否执行，材料有效时仍返回强化概率供界面预览。
	if wallet.coin_value < Enhancement.COST:
		data["message"] = "金币不足。"
		return data
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
		data["message"] = NO_PROMOTION_ROUTE
		return data
	if card.stars < Promotions.REQUIREMENTS[tier - 1]:
		data["message"] = "第%d次转职要求至少%d星。" % [tier, Promotions.REQUIREMENTS[tier - 1]]
		return data
	if not branches.any(func(entry: Dictionary) -> bool: return entry.id == book_id):
		data["message"] = "请选择这一阶段的技能书。"
		return data
	if inventory.get_item_count(book_id) < 1 or wallet.coin_value < Promotions.COST:
		data["message"] = "缺少技能书或金币。"
		return data
	data["ready"] = true
	data["message"] = "转职不影响星级，选择后不可撤销。"
	return data

## The transaction owns the only save boundary and re-quotes immediately before writing.
func execute(mode: String, choice: Dictionary) -> Dictionary:
	if not AdventureQuestService.feature_unlocked(state, "research"):
		return {"ok": false, "message": "领取「初次远征」奖励后解锁研究室。"}
	var action: AdventureResearchOperation = Operation.from_choice(mode, choice)
	if action == null:
		return {"ok": false, "message": "无效研究操作。"}
	return Transaction.commit(state, inventory, wallet, persist, action,
		Callable(self, "quote"))
