## 可独立序列化的冒险数据核心；不加载玩家、不写文件、不保存 UI 或场景对象。
extends RefCounted
class_name AdventureState

const Promotions = preload("res://scripts/adventure/research/research_promotion_catalog.gd")

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
## 玩家累计经验，升级曲线由成长系统提供。
var experience: int = 0
## 玩家当前等级，与具体任务进度分离。
var player_level: int = 1
## 角色装备库存及装配引用，不与普通道具数量混用。
var equipment: PlayerEquipmentState = PlayerEquipmentState.new()
## 任务进度和日常周期随同一档案保存。
var quests: AdventureQuestState = AdventureQuestState.new()
## 已完成的教学步骤；只保存业务节点，不保存窗口、动画或临时选择。
var tutorial_steps: Dictionary[String, bool] = {}
## 永久发现的物种键（plant:编号 / zombie:编号）；不保存阶级或界面状态。
var almanac_discoveries: Dictionary[String, bool] = {}

## 记录 [param kind] 类别的 [param type_id]；首次发现返回 true，重复或非法输入不改变状态。
func discover_character(kind: String, type_id: int) -> bool:
	if kind not in ["plant", "zombie"] or type_id <= 0:
		return false
	var key: String = "%s:%d" % [kind, type_id] # 稳定物种身份，独立于卡片 UID 和当前阶数。
	if almanac_discoveries.has(key):
		return false
	almanac_discoveries[key] = true
	return true

## 返回深拷贝的 JSON 基础数据；非法内存状态返回空字典，不泄漏对象引用。
func to_dict() -> Dictionary:
	if not _is_json_value(regions) or quests == null or AdventureQuestState.from_dict(quests.to_dict()) == null \
			or equipment == null or PlayerEquipmentState.from_dict(equipment.to_dict()) == null:
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
	data["quests"] = quests.to_dict()
	data["experience"] = experience
	data["player_level"] = player_level
	data["equipment"] = equipment.to_dict()
	data["tutorial_steps"] = tutorial_steps.duplicate()
	data["almanac_discoveries"] = almanac_discoveries.duplicate()
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
	var discoveries: Variant = data.get("almanac_discoveries", {}) # 旧档没有发现域，后续从持有植物补录。
	if not discoveries is Dictionary:
		return null
	for key: Variant in discoveries: # 保留合法但未来暂未注册的物种，避免版本变化丢失收集记录。
		if not key is String or not discoveries[key] is bool or discoveries[key] != true:
			return null
		var parts: PackedStringArray = key.split(":") # 分类与编号必须采用唯一规范写法。
		if parts.size() != 2 or parts[0] not in ["plant", "zombie"] or not parts[1].is_valid_int():
			return null
		if int(parts[1]) <= 0 or str(int(parts[1])) != parts[1]:
			return null
		state.almanac_discoveries[key] = true
	var steps: Variant = data.get("tutorial_steps", {}) # 旧档缺字段时从当前任务节点恢复引导。
	if not steps is Dictionary:
		return null
	for step: Variant in steps: # 拒绝损坏标记，不将任意数值隐式转换为布尔值。
		if not step is String or step.is_empty() or not steps[step] is bool:
			return null
		state.tutorial_steps[step] = steps[step]
	for field: String in ["experience", "player_level"]: # 旧档从零经验、一级开始，已有值严格校验。
		var minimum: int = 1 if field == "player_level" else 0 # 每个成长字段的合法下界。
		var value: Variant = data.get(field, minimum) # JSON 数值可能以浮点表示。
		if (typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT) or not is_finite(value) \
				or value < minimum or value > PlantCardInstance.MAX_JSON_INTEGER or value != floor(value):
			return null
		state.set(field, int(value))
	# 旧档保留累计经验；等级缓存按统一成长曲线恢复，不在读档时发放任何奖励。
	state.player_level = int(PlayerProgression.progress(state.experience).level)
	if data.has("equipment"):
		state.equipment = PlayerEquipmentState.from_dict(data.equipment)
		if state.equipment == null:
			return null
	# 旧档缺少任务域时初始化；存在但损坏时拒绝加载。
	if data.has("quests"):
		state.quests = AdventureQuestState.from_dict(data.quests)
		if state.quests == null:
			return null
	state.next_card_id = int(data.next_card_id)
	for card_uid: Variant in data.cards: # UID 必须规范、与卡内一致，并小于下一个分配编号。
		var number: int = PlantCardInstance.uid_number(card_uid) # 当前已有卡的编号。
		var card: PlantCardInstance = PlantCardInstance.from_dict(data.cards[card_uid]) # 独立恢复的卡实例。
		if number == 0 or number >= state.next_card_id or card == null or card.uid != card_uid \
			or not Promotions.is_valid_chain(card):
			return null
		state.cards[card_uid] = card
		state.discover_character("plant", card.plant_type)
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
