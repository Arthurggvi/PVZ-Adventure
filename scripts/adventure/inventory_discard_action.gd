## 背包丢弃操作：复用库存接口，保存失败只恢复本次修改的资产，不接触其他进度。
extends RefCounted

## 使用 [param inventory]、[param state] 丢弃 [param record] 的 [param quantity] 份资产。
## [param persist] 是同步保存回调；成功返回空字符串，拒绝或保存失败返回用户可读原因。
## 调用方须保证库存和状态属于同一当前玩家；本操作不访问单例、文件或界面。
static func execute(inventory: AdventureInventoryService, state: AdventureState, record: Dictionary, quantity: int, persist: Callable) -> String:
	if inventory == null or state == null or not persist.is_valid() or quantity < 1:
		return "背包状态不可用，请重新打开背包。"
	match str(record.get("kind", "")):
		"plant":
			return _discard_card(inventory, state, str(record.get("uid", "")), quantity, persist)
		"item":
			return _discard_item(inventory, state, str(record.get("id", "")), quantity, persist)
	return "当前物品无法丢弃。"

## 丢弃 [param uid] 的单卡，使用 [param inventory] 的移除规则；[param quantity] 只能为一。
## [param state] 只在 [param persist] 失败时恢复卡实例、展示顺序及出战引用，返回错误或空字符串。
static func _discard_card(inventory: AdventureInventoryService, state: AdventureState, uid: String, quantity: int, persist: Callable) -> String:
	if quantity != 1 or not state.cards.has(uid):
		return "这张植物卡已不存在，请重新选择。"
	if state.cards.size() <= 1:
		return "至少需要保留一张植物卡。"
	var card: PlantCardInstance = state.cards[uid] # 保留原实例，回滚不重新分配 UID。
	var order: Array[String] = state.card_order_uids.duplicate() # 丢弃前的完整展示顺序。
	var deck: Array[String] = state.selected_card_uids.duplicate() # 丢弃前的出战顺序。
	if not inventory.remove_card(uid):
		return "这张植物卡已不存在，请重新选择。"
	if persist.call() == true:
		return ""
	state.cards[uid] = card
	state.card_order_uids = order
	state.selected_card_uids = deck
	return "丢弃保存失败，植物卡已恢复。"

## 使用 [param inventory] 扣除 [param id] 的 [param quantity] 份物品，不区分材料、配方、钥匙或消耗品。
## [param persist] 失败时恢复 [param state] 中该物品的原数量；数量不足或 ID 非法时不保存。
static func _discard_item(inventory: AdventureInventoryService, state: AdventureState, id: String, quantity: int, persist: Callable) -> String:
	var previous: int = inventory.get_item_count(id) # 保存前快照，仅回滚本次修改的物品。
	if not inventory.consume_item(id, quantity):
		return "物品数量已变更或不足，请重新选择。"
	if persist.call() == true:
		return ""
	state.items[id] = previous
	return "丢弃保存失败，物品数量已恢复。"
