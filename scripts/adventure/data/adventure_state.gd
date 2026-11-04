## 可独立序列化的冒险数据核心；不加载玩家、不写文件、不保存 UI 或场景对象。
extends RefCounted
class_name AdventureState

## 第一阶段协议版本，未知版本不自动初始化或迁移。
var schema_version: int = 1
## 按独立 UID 索引的植物卡实例。
var cards: Dictionary[String, PlantCardInstance] = {}
## 按静态道具 ID 索引的正整数数量，数量为零的条目不保留。
var items: Dictionary[String, int] = {}
## 有序出战 UID 列表，必须存在于 cards 且不重复。
var selected_card_uids: Array[String] = []
## 背包植物永久展示顺序；与上次出战 UID 分离，必须覆盖 cards 的每张实例。
var card_order_uids: Array[String] = []
## 下一个未分配编号，删除卡片不回退，序列化后继续递增。
var next_card_id: int = 1
## 未来地区进度的 JSON 字典，不解释其业务含义。
var regions: Dictionary = {}
## 奖励 ID 对应的布尔领取标记，第一阶段不执行发奖业务。
var claimed_rewards: Dictionary[String, bool] = {}

## 返回深拷贝的 JSON 基础数据；非法内存状态返回空字典，不泄漏对象引用。
func to_dict() -> Dictionary:
	if not _is_json_value(regions):
		return {}
	var encoded_cards: Dictionary = {} # 卡实例逐个编码，不将 RefCounted 对象交给 JSON。
	for card_uid: String in cards: # 字典键和实例 UID 还会经协议校验回比。
		if cards[card_uid] == null:
			return {}
		encoded_cards[card_uid] = cards[card_uid].to_dict()
	var data: Dictionary = {"schema_version": schema_version, "cards": encoded_cards,
		"items": items.duplicate(true), "selected_card_uids": selected_card_uids.duplicate(),
		"card_order_uids": card_order_uids.duplicate(), "next_card_id": next_card_id, "regions": regions.duplicate(true),
		"claimed_rewards": claimed_rewards.duplicate(true)} # 所有嵌套容器独立于运行态。
	return data if from_dict(data) != null else {}

## 从 [param data] 校验并创建独立状态；非法结构、版本、UID、出战列表或数量返回 null。
static func from_dict(data: Variant) -> AdventureState:
	if not data is Dictionary:
		return null
	for field: String in ["schema_version", "cards", "items", "selected_card_uids", "next_card_id", "regions", "claimed_rewards"]: # 协议字段不凭缺失值伪造新档。
		if not data.has(field):
			return null
	if not PlantCardInstance.is_positive_integer(data.schema_version) or data.schema_version != 1 \
		or not PlantCardInstance.is_positive_integer(data.next_card_id):
		return null
	if not data.cards is Dictionary or not data.items is Dictionary or not data.selected_card_uids is Array \
		or not data.regions is Dictionary or not data.claimed_rewards is Dictionary or not _is_json_value(data.regions):
		return null
	if data.has("card_order_uids") and not data.card_order_uids is Array:
		return null
	var state := AdventureState.new() # 所有容器和卡片都在此新实例中恢复。
	state.next_card_id = int(data.next_card_id)
	for card_uid: Variant in data.cards: # UID 必须规范、与卡内一致，并小于下一个分配编号。
		var number: int = PlantCardInstance.uid_number(card_uid) # 当前已有卡的编号。
		var card: PlantCardInstance = PlantCardInstance.from_dict(data.cards[card_uid]) # 独立恢复的卡实例。
		if number == 0 or number >= state.next_card_id or card == null or card.uid != card_uid:
			return null
		state.cards[card_uid] = card
	# 旧版存档没有显式排序：从稳定 UID 数字恢复首次顺序，不触碰卡组。
	if data.has("card_order_uids"):
		for card_uid: Variant in data.card_order_uids:
			if typeof(card_uid) != TYPE_STRING or not state.cards.has(card_uid) or state.card_order_uids.has(card_uid):
				return null
			state.card_order_uids.append(card_uid)
		if state.card_order_uids.size() != state.cards.size():
			return null
	else:
		for card_uid: String in state.cards:
			state.card_order_uids.append(card_uid)
		state.card_order_uids.sort_custom(_uid_before)
	for item_id: Variant in data.items: # 不接受未知种类、零/负数或非整数数量。
		if typeof(item_id) != TYPE_STRING or not ItemRegistry.has_item(item_id) \
			or not PlantCardInstance.is_positive_integer(data.items[item_id]):
			return null
		state.items[item_id] = int(data.items[item_id])
	for card_uid: Variant in data.selected_card_uids: # 先验证整个输入，新状态失败时不会触及调用者的旧状态。
		if typeof(card_uid) != TYPE_STRING or not state.cards.has(card_uid) or state.selected_card_uids.has(card_uid):
			return null
		state.selected_card_uids.append(card_uid)
	for region_id: Variant in data.regions: # 地区标识至少为非空文本，具体内容仍只作为 JSON 数据。
		if typeof(region_id) != TYPE_STRING or region_id.strip_edges().is_empty():
			return null
	state.regions = data.regions.duplicate(true)
	for reward_id: Variant in data.claimed_rewards: # 领取标记不能混入数量、对象或空 ID。
		if typeof(reward_id) != TYPE_STRING or reward_id.strip_edges().is_empty() \
			or typeof(data.claimed_rewards[reward_id]) != TYPE_BOOL:
			return null
		state.claimed_rewards[reward_id] = data.claimed_rewards[reward_id]
	return state

## 旧存档首次排序按 UID 递增；文本排序在编号超过六位时会失序。
static func _uid_before(a: String, b: String) -> bool:
	return PlantCardInstance.uid_number(a) < PlantCardInstance.uid_number(b)

## [param value] 仅可包含 JSON 基础类型；[param depth] 限制异常深度与循环容器。
static func _is_json_value(value: Variant, depth: int = 0) -> bool:
	if depth > 64:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_STRING:
			return true
		TYPE_INT:
			return value >= -PlantCardInstance.MAX_JSON_INTEGER and value <= PlantCardInstance.MAX_JSON_INTEGER
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_ARRAY:
			for entry: Variant in value: # 递归校验，不接受 Object、向量或 Resource 等非 JSON 数据。
				if not _is_json_value(entry, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			for key: Variant in value: # JSON 对象键必须为字符串。
				if typeof(key) != TYPE_STRING or not _is_json_value(value[key], depth + 1):
					return false
			return true
	return false
