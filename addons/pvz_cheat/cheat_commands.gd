## Cheat operations use existing inventory and save services; never fork game data.
extends RefCounted
const Stage = preload("res://addons/pvz_cheat/cheat_stages.gd")
const Backup = preload("res://addons/pvz_cheat/cheat_backup.gd")
var stage_service := Stage.new()
var backup_service := Backup.new()

static func available() -> bool:
	return Global.save_service != null and Global.save_service.is_current_profile_loaded() \
		and Global.adventure_inventory != null and Global.global_game_state.adventure_state != null

static func result(ok: bool, message: String) -> Dictionary:
	return {"ok": ok, "message": message}

func add_cards(plant_type: int, stars: int, amount: int) -> Dictionary:
	if not available():
		return result(false, "请先选择有效的玩家存档。")
	if not PlantCardInstance.is_plant_type(plant_type) or stars < 0 or stars > 10 or amount < 1 or amount > 32:
		return result(false, "植物、星级或数量无效（一次最多32张，星级0–10）。")
	var state: AdventureState = Global.global_game_state.adventure_state
	var previous_next: int = state.next_card_id
	var created: Array[String] = []
	for i in amount:
		var uid: String = Global.adventure_inventory.add_card(plant_type, stars)
		if uid.is_empty():
			break
		created.append(uid)
	if created.size() == amount and Global.save_service.save_now():
		return result(true, "已获得 %d 张独立卡牌，最后UID：%s" % [amount, created[-1]])
	for uid: String in created:
		Global.adventure_inventory.remove_card(uid)
	state.next_card_id = previous_next
	return result(false, "生成或保存失败，已回滚。")

func change_item(id: String, amount: int) -> Dictionary:
	if not available():
		return result(false, "请先选择有效的玩家存档。")
	if not ItemRegistry.has_item(id) or amount == 0 or absi(amount) > 1000000:
		return result(false, "物品或数量非法（单次最多100万）。")
	var inventory: AdventureInventoryService = Global.adventure_inventory
	var before: int = inventory.get_item_count(id)
	var ok: bool = inventory.add_item(id, amount) if amount > 0 else inventory.consume_item(id, -amount)
	if not ok:
		return result(false, "库存不足或数量溢出。")
	if Global.save_service.save_now():
		return result(true, "%s %+d，现有 %d" % [ItemRegistry.get_item_definition(id).get("name", id), amount, inventory.get_item_count(id)])
	var state: AdventureState = Global.global_game_state.adventure_state
	if before == 0:
		state.items.erase(id)
	else:
		state.items[id] = before
	return result(false, "保存失败，库存已回滚。")

func grant_category(category: String, amount: int) -> Dictionary:
	if not available() or category not in ["material", "recipe", "key", "consumable"] or amount < 1 or amount > 100:
		return result(false, "类别或数量无效（每种最多100）。")
	var state: AdventureState = Global.global_game_state.adventure_state
	var previous: Dictionary = state.items.duplicate(true)
	var total := 0
	for id: String in ItemRegistry.ITEMS:
		if str(ItemRegistry.get_item_definition(id).get("category", "")) != category:
			continue
		if not Global.adventure_inventory.add_item(id, amount):
			_restore_items(state, previous)
			return result(false, "批量发放失败，已回滚。")
		total += 1
	if total > 0 and Global.save_service.save_now():
		return result(true, "已发放 %d 种资源，每种 ×%d。" % [total, amount])
	_restore_items(state, previous)
	return result(false, "批量保存失败，已回滚。")

func _restore_items(state: AdventureState, items: Dictionary) -> void:
	state.items.clear()
	for id: String in items:
		state.items[id] = int(items[id])

func change_coin(value: int, operation: String) -> Dictionary:
	if not available():
		return result(false, "请先选择有效的玩家存档。")
	var old: int = Global.global_game_state.coin_value
	var target: int = value if operation == "set" else old + value if operation == "add" else old - value
	if value < 0 or value > 1000000000 or target < 0 or target > PlantCardInstance.MAX_JSON_INTEGER:
		return result(false, "金币数值无效或越界。")
	Global.global_game_state.coin_value = target
	if Global.save_service.save_now():
		return result(true, "金币：%d → %d" % [old, target])
	Global.global_game_state.coin_value = old
	return result(false, "保存失败，金币已回滚。")

func unlock_stage(stage: int, nightmare: bool) -> Dictionary:
	return stage_service.unlock(stage, nightmare, false)

func clear_stage(stage: int, nightmare: bool) -> Dictionary:
	return stage_service.unlock(stage, nightmare, true)

func enter_stage(stage: int, nightmare: bool) -> Dictionary:
	return stage_service.enter(stage, nightmare)

func settle_current() -> Dictionary:
	return stage_service.settle_current()

func snapshot() -> Dictionary:
	return backup_service.snapshot()

func restore() -> Dictionary:
	return backup_service.restore()
