## 可独立序列化的冒险数据核心；不加载玩家、不写文件、不保存 UI 或场景对象。
extends RefCounted
class_name AdventureState

const Promotions = preload("res://scripts/adventure/research/research_promotion_catalog.gd")
## 图书馆独立货架协议；字段缺失的旧档使用未开馆状态。
const LibraryStock = preload("res://scripts/adventure/library/library_stock.gd")
## 商店购买记录独立编码，旧档缺失时默认六槽。
const ShopState = preload("res://scripts/adventure/shop/shop_state.gd")

## 强化记录的持久化结果编号，失败保星时仍与普通失败分开显示。
enum EnhancementOutcome { SUCCESS = 0, FAILURE = 1, PROTECTED = 2 }

## 第一阶段协议版本，未知版本不自动初始化或迁移。
var schema_version: int = 1
## 按独立 UID 索引的植物卡实例。
var cards: Dictionary[String, PlantCardInstance] = {}
## 按静态道具 ID 索引的正整数数量，数量为零的条目不保留。
var items: Dictionary[String, int] = {}
## 最近一次整理保存的道具 ID 顺序。已消耗的条目可跳过，未登记的道具在背包末尾显示。
var item_order_ids: Array[String] = []
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
## 修改器为当前档案开放设施；默认按正常任务和教学条件解锁。
var facilities_unlocked_by_cheat: bool = false
## 已完成的教学步骤；只保存业务节点，不保存窗口、动画或临时选择。
var tutorial_steps: Dictionary[String, bool] = {}
## 永久发现的物种键（plant:编号 / zombie:编号）；不保存阶级或界面状态。
var almanac_discoveries: Dictionary[String, bool] = {}
## 每日书籍与售出状态，不持久化窗口选择。
var library: LibraryStock = LibraryStock.new()
## 每日限购、永久槽位与购买版本属于当前玩家档案。
var shop: ShopState = ShopState.new()
## 按结算先后保留本档所有强化记录；单条记录只含不可变的基础值。
var enhancement_history: Array[Dictionary] = []

## 以本机墙钟记录 [param plant_type] 的 [param before_stars] 到 [param after_stars] 及 [param outcome]。
## 由强化事务在存档前追加，保存失败时事务会移除本次记录。
func record_enhancement(plant_type: int, before_stars: int, after_stars: int,
		outcome: EnhancementOutcome) -> void:
	var entry: Dictionary = {"time": Time.get_datetime_string_from_system(false, true),
		"plant_type": plant_type, "before_stars": before_stars, "after_stars": after_stars,
		"outcome": outcome} # 时间精确到秒，保存操作当时设备显示的日期与时间。
	entry.make_read_only()
	enhancement_history.append(entry)

## 记录 [param kind] 类别的 [param type_id]；首次发现返回 true，重复或非法输入不改变状态。
func discover_character(kind: String, type_id: int) -> bool:
	if kind not in ["plant", "zombie"] or type_id <= 0:
		return false
	var key: String = "%s:%d" % [kind, type_id] # 稳定物种身份，独立于卡片 UID 和当前阶数。
	if almanac_discoveries.has(key):
		return false
	almanac_discoveries[key] = true
	return true

## 返回经过协议校验的独立数据；装备使用读档及变更入口已验证的运行态。
func to_dict() -> Dictionary:
	var data: Dictionary = save_snapshot() # 普通序列化调用仍可同步确认存档快照有效。
	return data if validate_save_snapshot(data) else {}

## 复制独立的存档字段，完整的纯数据协议校验由持久化入口执行。
func save_snapshot() -> Dictionary:
	if shop == null or library == null or quests == null or equipment == null:
		return {}
	# 这些容器允许变长的嵌套结构，在复制前拒绝场景对象和循环引用。
	if not is_json_value(regions) or not is_json_value(quests.records) or not is_json_value(library.offers):
		return {}
	var encoded_cards: Dictionary = {} # 保留每张卡的独立字段，不传递实例对象。
	for card_uid: String in cards: # 键与实例的 UID 由存档协议核对。
		var card: PlantCardInstance = cards[card_uid] # 一次取出可以安全复制的卡片实例。
		if card == null:
			return {}
		encoded_cards[card_uid] = card.save_snapshot()
	var data: Dictionary = {"schema_version": schema_version, "cards": encoded_cards,
		"items": items.duplicate(true), "selected_card_uids": selected_card_uids.duplicate(),
		"card_order_uids": card_order_uids.duplicate(), "next_card_id": next_card_id, "regions": regions.duplicate(true),
		"claimed_rewards": claimed_rewards.duplicate(true)} # 所有嵌套容器独立于运行态。
	if not item_order_ids.is_empty():
		data["item_order_ids"] = item_order_ids.duplicate() # JSON 字典按键写出，道具顺序单独用数组保存。
	data["quests"] = quests.to_dict()
	if facilities_unlocked_by_cheat:
		data["facilities_unlocked_by_cheat"] = true
	data["experience"] = experience
	data["player_level"] = player_level
	data["equipment"] = equipment.to_dict()
	data["tutorial_steps"] = tutorial_steps.duplicate()
	data["almanac_discoveries"] = almanac_discoveries.duplicate()
	data["library"] = library.to_dict()
	data["shop"] = shop.to_dict()
	if not enhancement_history.is_empty():
		data["enhancement_history"] = enhancement_history.duplicate() # 冻结的记录可以与后台快照安全共享。
	return data

## 校验由 [method save_snapshot] 生成的 [param data]；装备字段已由读档和变更入口校验。
static func validate_save_snapshot(data: Dictionary) -> bool:
	return _decode(data, false) != null

## 从 [param data] 校验并创建独立状态；非法结构、版本、UID、出战列表或数量返回 null。
static func from_dict(data: Variant) -> AdventureState:
	return _decode(data, true)

## 共用 [param data] 的协议检查；[param load_profile_details] 为 true 时恢复装备和强化记录。
static func _decode(data: Variant, load_profile_details: bool) -> AdventureState:
	if not data is Dictionary:
		return null
	for field: String in ["schema_version", "cards", "items", "selected_card_uids", "next_card_id", "regions", "claimed_rewards"]: # 协议字段不凭缺失值伪造新档。
		if not data.has(field):
			return null
	if not PlantCardInstance.is_positive_integer(data.schema_version) or data.schema_version != 1 \
		or not PlantCardInstance.is_positive_integer(data.next_card_id):
		return null
	if not data.cards is Dictionary or not data.items is Dictionary or not data.selected_card_uids is Array \
			or not data.regions is Dictionary or not data.claimed_rewards is Dictionary or not is_json_value(data.regions):
		return null
	if data.has("card_order_uids") and not data.card_order_uids is Array:
		return null
	var state := AdventureState.new() # 所有容器和卡片都在此新实例中恢复。
	var history: Variant = data.get("enhancement_history", []) # 旧档缺少日志时从空记录开始。
	if not history is Array:
		return null
	for entry: Variant in history: # 每条记录独立于当前卡片，卡片消耗后依然有效。
		if not _is_enhancement_record(entry):
			return null
		if load_profile_details:
			var restored: Dictionary = entry.duplicate() # 读档对象独占记录，且只允许追加或回滚整条记录。
			restored.make_read_only()
			state.enhancement_history.append(restored)
	state.shop = ShopState.from_dict(data.get("shop", {}))
	if state.shop == null:
		return null
	state.library = LibraryStock.from_dict(data.get("library", {}))
	if state.library == null:
		return null
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
	if load_profile_details and data.has("equipment"):
		state.equipment = PlayerEquipmentState.from_dict(data.equipment)
		if state.equipment == null:
			return null
	# 旧档缺少任务域时初始化；存在但损坏时拒绝加载。
	if data.has("quests"):
		state.quests = AdventureQuestState.from_dict(data.quests)
		if state.quests == null:
			return null
	var facilities_override: Variant = data.get("facilities_unlocked_by_cheat", false) # 旧档沿用正常解锁规则。
	if not facilities_override is bool:
		return null
	state.facilities_unlocked_by_cheat = facilities_override
	state.next_card_id = int(data.next_card_id)
	for card_uid: Variant in data.cards: # UID 必须规范、与卡内一致，并小于下一个分配编号。
		var number: int = PlantCardInstance.uid_number(card_uid) # 当前已有卡的编号。
		var card: PlantCardInstance = PlantCardInstance.from_dict(data.cards[card_uid]) # 独立恢复的卡实例。
		if number == 0 or number >= state.next_card_id or card == null or card.uid != card_uid \
			or not Promotions.is_valid_chain(card):
			return null
		card.promotion_2 = Promotions.canonical_book_id(card.promotion_2)
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
		if typeof(item_id) != TYPE_STRING or not PlantCardInstance.is_positive_integer(data.items[item_id]):
			return null
		# 读档时归并旧生长剂和旧转职书，保留同一现行道具的合计数量。
		var canonical_id: String = "growth_agent_lv1" if item_id == "growth_agent" else Promotions.canonical_book_id(item_id)
		if not ItemRegistry.has_item(canonical_id):
			return null
		var quantity: int = int(data.items[item_id]) # 单个合法正整数数量。
		var existing: int = int(state.items.get(canonical_id, 0)) # 处理新旧两类 ID 在同一存档中并存。
		if quantity > PlantCardInstance.MAX_JSON_INTEGER - existing:
			return null
		state.items[canonical_id] = existing + quantity
	var item_order: Variant = data.get("item_order_ids", []) # 旧档缺字段时沿用原有的库存遍历顺序。
	if not item_order is Array:
		return null
	var ordered_items: Dictionary[String, bool] = {} # 整理顺序中的道具 ID 去重，不要求当前仍持有。
	var canonical_order: Dictionary[String, bool] = {} # 合并前后的同一本书保留第一次出现的位置。
	for item_id: Variant in item_order: # 允许已消耗或目录已移除的道具占有历史位置。
		if typeof(item_id) != TYPE_STRING or item_id.is_empty() or ordered_items.has(item_id):
			return null
		ordered_items[item_id] = true
		canonical_order[Promotions.canonical_book_id(item_id)] = true
	state.item_order_ids.assign(canonical_order.keys())
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

## 校验 [param entry] 的固定格式和结果范围，容许档案记录中出现已移除的植物物种。
static func _is_enhancement_record(entry: Variant) -> bool:
	if not entry is Dictionary or entry.size() != 5:
		return false
	var local_time: Variant = entry.get("time") # 以固定宽度保留当时本机日期和秒数。
	var before: Variant = entry.get("before_stars") # 从零星起记录实际结算前的星级。
	var after: Variant = entry.get("after_stars") # 结算后可能升星、掉星或保持原星级。
	var outcome: Variant = entry.get("outcome") # JSON 读回的整数也可能以浮点类型表示。
	return (local_time is String and local_time.length() == 19
		and local_time[4] == "-" and local_time[7] == "-" and local_time[10] == " "
		and local_time[13] == ":" and local_time[16] == ":"
		and PlantCardInstance.is_positive_integer(entry.get("plant_type"))
		and PlantCardInstance.is_nonnegative_integer(before) and before < PlantCardInstance.MAX_STARS
		and PlantCardInstance.is_nonnegative_integer(after) and after <= PlantCardInstance.MAX_STARS
		and PlantCardInstance.is_nonnegative_integer(outcome) and outcome <= EnhancementOutcome.PROTECTED)

## 旧存档首次排序按 UID 递增；文本排序在编号超过六位时会失序。
static func _uid_before(a: String, b: String) -> bool:
	return PlantCardInstance.uid_number(a) < PlantCardInstance.uid_number(b)

## [param value] 仅可包含 JSON 基础类型；[param depth] 限制异常深度与循环容器。
static func is_json_value(value: Variant, depth: int = 0) -> bool:
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
				if not is_json_value(entry, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			for key: Variant in value: # JSON 对象键必须为字符串。
				if typeof(key) != TYPE_STRING or not is_json_value(value[key], depth + 1):
					return false
			return true
	return false
