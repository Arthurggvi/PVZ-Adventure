## 只操作构造注入状态的冒险库存服务；没有单例、存档、场景或全局玩家依赖。
extends RefCounted
class_name AdventureInventoryService

## 本服务唯一操作的状态，不复制或访问其他玩家状态。
var _state: AdventureState

## [param state] 必须是调用者拥有的独立 AdventureState；仅绑定内存引用。
func _init(state: AdventureState) -> void:
	assert(state != null, "必须注入 AdventureState")
	_state = state

## Explicit identity check for multi-system asset transactions and profile isolation.
func owns_state(state: AdventureState) -> bool:
	return _state == state

## 添加 [param plant_type]、[param stars] 指定的卡，返回新 UID；非法输入或编号耗尽返回空字符串。
func add_card(plant_type: Variant, stars: Variant = 0) -> String:
	if not PlantCardInstance.is_plant_type(plant_type) or not PlantCardInstance.is_nonnegative_integer(stars) \
		or int(stars) > PlantCardInstance.MAX_STARS \
		or not PlantCardInstance.is_positive_integer(_state.next_card_id) \
		or _state.next_card_id >= PlantCardInstance.MAX_JSON_INTEGER:
		return ""
	var card_uid: String = "PC%06d" % _state.next_card_id # 编号至少六位，递增后不回收。
	if _state.cards.has(card_uid):
		return ""
	var card := PlantCardInstance.new() # 每次新增都是独立实例，即使物种相同。
	card.uid = card_uid
	card.plant_type = int(plant_type)
	card.stars = int(stars)
	_state.cards[card_uid] = card
	_state.card_order_uids.append(card_uid)
	_state.next_card_id += 1
	_state.discover_character("plant", card.plant_type)
	return card_uid

## 删除 [param uid] 的卡并同步剔除所有出战引用；不存在时返回 false。
func remove_card(uid: String) -> bool:
	if not _state.cards.erase(uid):
		return false
	_state.card_order_uids.erase(uid)
	while _state.selected_card_uids.has(uid):
		_state.selected_card_uids.erase(uid)
	return true

## 返回 [param uid] 的数据副本；不存在时返回空字典。
func get_card(uid: String) -> Dictionary:
	return _state.cards[uid].to_dict() if _state.cards.has(uid) else {}

## 返回所有卡的独立字典列表，不向外暴露可写卡对象。
func list_cards() -> Array[Dictionary]:
	var result: Array[Dictionary] = [] # 每个列表元素也是重新构造的纯数据副本。
	for card_uid: String in _state.card_order_uids: # 背包与冒险选卡共用保存后的卡牌 UID 顺序。
		result.append(get_card(card_uid))
	return result

## 返回独立排序快照，界面拖拽不能直接改写状态数组。
func get_card_order() -> Array[String]:
	return _state.card_order_uids.duplicate()

## 原子设置完整卡牌顺序；漏卡、重复 UID 或跨档 UID 一律拒绝。
func set_card_order(uids: Array[String]) -> bool:
	if uids.size() != _state.cards.size():
		return false
	var seen: Dictionary = {}
	for uid: String in uids:
		if not _state.cards.has(uid) or seen.has(uid):
			return false
		seen[uid] = true
	_state.card_order_uids = uids.duplicate()
	return true

## 背包拖拽将单卡插入目标序位，其他卡平移；仅移动引用，不改变出战历史。
func move_card(uid: String, target_index: int) -> bool:
	if not _state.cards.has(uid) or target_index < 0 or target_index >= _state.card_order_uids.size():
		return false
	var order: Array[String] = _state.card_order_uids.duplicate()
	order.erase(uid)
	order.insert(target_index, uid)
	return set_card_order(order)

## 整理整个背包：植物卡按物种和星级归组，其余库存按物品目录排列。
## [param persist] 同步提交两类顺序，失败时全部回滚；已经排好时直接返回 true。
func organize(persist: Callable) -> bool:
	if not persist.is_valid():
		return false
	var before_cards: Array[String] = _state.card_order_uids # 保留原数组供失败回滚。
	var before_items: Array[String] = _state.item_order_ids # 保留上一轮道具顺序。
	var card_order: Array[String] = before_cards.duplicate() # 对独立的 UID 列表排序。
	card_order.sort_custom(_organized_card_before)
	var item_order: Array[String] = [] # 只记录整理时持有的道具。
	for id: String in ItemRegistry.ITEMS: # 沿用目录中的分类与系列顺序。
		if _state.items.has(id):
			item_order.append(id)
	if card_order == before_cards and item_order == before_items:
		return true
	if not set_card_order(card_order):
		return false
	_state.item_order_ids = item_order
	if persist.call() == true:
		return true
	_state.card_order_uids = before_cards
	_state.item_order_ids = before_items
	return false

## 比较 [param left_uid] 和 [param right_uid]，同种植物高星在前，同星按分配 UID 先后排列。
func _organized_card_before(left_uid: String, right_uid: String) -> bool:
	var left: PlantCardInstance = _state.cards[left_uid] # 左侧 UID 对应的现有卡片。
	var right: PlantCardInstance = _state.cards[right_uid] # 右侧 UID 对应的现有卡片。
	if left.plant_type != right.plant_type:
		return left.plant_type < right.plant_type
	if left.stars != right.stars:
		return left.stars > right.stars
	return PlantCardInstance.uid_number(left_uid) < PlantCardInstance.uid_number(right_uid)

## 用 [param uids] 原子替换出战列表；重复或不存在的 UID 拒绝，旧列表保持不变。
func set_deck(uids: Array[String]) -> bool:
	var seen: Dictionary = {} # 本次请求内已见的 UID，不依赖物种或卡对象身份。
	for card_uid: String in uids:
		if seen.has(card_uid) or not _state.cards.has(card_uid):
			return false
		seen[card_uid] = true
	_state.selected_card_uids = uids.duplicate()
	return true

## 增加已知道具 [param id] 的正整数 [param qty]；非法输入或数量溢出时不改变状态。
func add_item(id: String, qty: Variant) -> bool:
	if not ItemRegistry.has_item(id) or not PlantCardInstance.is_positive_integer(qty):
		return false
	var amount: int = int(qty) # 在校验后转换 JSON 整数表示。
	var current: int = get_item_count(id) # 当前持有量；不存在时从零增加。
	if current < 0 or current > PlantCardInstance.MAX_JSON_INTEGER - amount:
		return false
	_state.items[id] = current + amount
	return true

## 扣除 [param id] 的正整数 [param qty]；不足或非法时不扣，扣完删除零数量条目。
func consume_item(id: String, qty: Variant) -> bool:
	if not ItemRegistry.has_item(id) or not PlantCardInstance.is_positive_integer(qty):
		return false
	var amount: int = int(qty) # 已校验的本次扣除量。
	var current: int = get_item_count(id) # 扣除前的持有量。
	if amount > current:
		return false
	if amount == current:
		_state.items.erase(id)
	else:
		_state.items[id] = current - amount
	return true

## 返回 [param id] 的持有量，未知或未持有为零，不创建库存条目。
func get_item_count(id: String) -> int:
	return _state.items.get(id, 0)

## 返回按背包顺序排列的独立数量字典，尚未整理的道具依次追加。
func get_items() -> Dictionary:
	var ordered: Dictionary[String, int] = {} # 只纳入当前仍持有的条目。
	for id: String in _state.item_order_ids: # 先恢复上次整理过的道具位置。
		if _state.items.has(id):
			ordered[id] = _state.items[id]
	ordered.merge(_state.items) # 按库存顺序补入新道具，保留已有键的位置。
	return ordered
