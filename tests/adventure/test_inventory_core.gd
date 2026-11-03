## 冒险数据核心的纯内存验收；不调用玩家存档、场景或业务入口。
extends SceneTree

## 延迟到引擎初始化完成，失败断言由短超时以非零退出兜底。
func _initialize() -> void:
	create_timer(5.0, true, false, true).timeout.connect(func(): quit(1))
	_run.call_deferred()

## 验证身份、库存、出战列表、JSON 边界与不同状态的隔离。
func _run() -> void:
	assert(OS.get_user_data_dir().contains("inventory-core-test"), "必须使用隔离 APPDATA")
	var card_model: GDScript = load("res://scripts/adventure/data/plant_card_instance.gd") # 实际卡实例模型。
	var state_model: GDScript = load("res://scripts/adventure/data/adventure_state.gd") # 实际聚合状态。
	var service_model: GDScript = load("res://scripts/adventure/adventure_inventory_service.gd") # 实际内存服务。
	assert(card_model != null and state_model != null and service_model != null)
	var state: RefCounted = state_model.new() # 第一玩家状态，不关联任何文件。
	var inventory: RefCounted = service_model.new(state) # 构造注入，无全局状态。
	var first: String = inventory.add_card(1) # 第一张豌豆射手。
	var second: String = inventory.add_card(1, 2) # 同物种的第二张独立卡。
	assert(first == "PC000001" and second == "PC000002")
	assert(inventory.get_card(first).stars == 1 and inventory.get_card(second).stars == 2)
	assert(inventory.add_card(0).is_empty() and inventory.add_card(999).is_empty())
	assert(inventory.add_card(123456).is_empty() and inventory.add_card(1, 0).is_empty())
	assert(inventory.add_card(true).is_empty() and inventory.add_card(1, 1.5).is_empty())
	assert(inventory.list_cards().size() == 2 and state.next_card_id == 3)
	var card_copy: Dictionary = inventory.get_card(first) # 查询结果不能成为修改真实卡的旁路。
	card_copy.stars = 99
	var card_list: Array[Dictionary] = inventory.list_cards() # 列表中的每个字典也必须独立。
	card_list[0].stars = 88
	assert(inventory.get_card(first).stars == 1)
	var deck: Array[String] = [first, second] # 合法双卡出战列表。
	assert(inventory.set_deck(deck))
	deck.clear()
	assert(state.selected_card_uids == [first, second])
	var duplicate_deck: Array[String] = [first, first] # 重复 UID 必须原子拒绝。
	var missing_deck: Array[String] = ["PC999999"] # 不存在的合法格式 UID。
	assert(not inventory.set_deck(duplicate_deck) and not inventory.set_deck(missing_deck))
	assert(state.selected_card_uids == [first, second])
	assert(inventory.remove_card(first) and state.selected_card_uids == [second])
	assert(not inventory.remove_card(first) and inventory.get_card(first).is_empty())
	assert(inventory.add_card(1) == "PC000003") # 删除不会回收历史编号。
	assert(inventory.add_item("nut_fragments", 2) and inventory.add_item("nut_fragments", 3))
	assert(inventory.consume_item("nut_fragments", 2) and inventory.get_item_count("nut_fragments") == 3)
	assert(not inventory.consume_item("nut_fragments", 4))
	for quantity: Variant in [0, -1, 1.5, true]: # 非正数、非整数和布尔值均不得改数量。
		assert(not inventory.add_item("nut_fragments", quantity))
		assert(not inventory.consume_item("nut_fragments", quantity))
	assert(not inventory.add_item("unknown", 1) and not inventory.consume_item("unknown", 1))
	assert(inventory.get_item_count("unknown") == 0)
	var items_copy: Dictionary = inventory.get_items() # 数量查询返回深拷贝。
	items_copy.clear()
	assert(inventory.get_item_count("nut_fragments") == 3)
	assert(inventory.consume_item("nut_fragments", 3) and not inventory.get_items().has("nut_fragments"))
	assert(inventory.add_item("fertilizer_lv1", 2))
	var definition: Dictionary = ItemRegistry.get_item_definition("recipe_wall_nut") # 静态定义也不暴露可写引用。
	assert(definition.category == "recipe" and ItemRegistry.has_item("recipe_potato_mine"))
	definition.name = "changed"
	assert(ItemRegistry.get_item_definition("recipe_wall_nut").name != "changed")
	assert(ItemRegistry.get_item_definition("unknown").is_empty())
	state.regions = {"zombie_island": {"cleared": [1], "note": null}}
	state.claimed_rewards["starter"] = true
	state.cards[second].promotion_1 = "branch_a"
	var encoded: String = JSON.stringify(state.to_dict()) # 仅经 JSON 基础类型往返。
	var payload: Dictionary = JSON.parse_string(encoded) # 解码得到独立、无类型约束的输入字典。
	var restored: RefCounted = state_model.from_dict(payload) # 第二个状态由协议恢复。
	assert(restored != null and restored.cards.size() == 2)
	assert(restored.cards[second].promotion_1 == "branch_a" and restored.cards[second].promotion_2.is_empty())
	assert(restored.selected_card_uids == [second] and restored.items.fertilizer_lv1 == 2)
	# Godot JSON 将数组内数字解码为浮点；比较数值语义，不要求原始 Variant 数字类型相同。
	assert(restored.regions.zombie_island.cleared.size() == 1 and restored.regions.zombie_island.cleared[0] == 1 and restored.claimed_rewards.starter)
	var resumed: RefCounted = service_model.new(restored) # 恢复后继续使用持久计数器。
	assert(resumed.add_card(2) == "PC000004")
	payload.regions.zombie_island.cleared.append(2)
	assert(restored.regions.zombie_island.cleared.size() == 1 and restored.regions.zombie_island.cleared[0] == 1)
	var other_state: RefCounted = state_model.new() # 另一玩家从空状态独立起步。
	var other: RefCounted = service_model.new(other_state) # 服务只绑定构造参数。
	assert(other.add_card(2) == "PC000001" and other.get_item_count("fertilizer_lv1") == 0)
	assert(other.add_item("fertilizer_lv1", 7))
	assert(inventory.get_item_count("fertilizer_lv1") == 2 and inventory.list_cards().size() == 2)
	var valid_card: Dictionary = inventory.get_card(second) # 合法单卡协议基线。
	for invalid_uid: String in ["", "PC000000", "PC1", "PC+00001", "PC0000002", "PC000002x"]: # 拒绝非法或非规范 UID。
		var invalid_card: Dictionary = valid_card.duplicate(true) # 每次只改变一个输入边界。
		invalid_card.uid = invalid_uid
		assert(card_model.from_dict(invalid_card) == null)
	for invalid_plant: Variant in [0, 999, 123456, true, 1.5]: # 不把布尔或小数强转成物种。
		var invalid_card: Dictionary = valid_card.duplicate(true) # 单卡负例。
		invalid_card.plant_type = invalid_plant
		assert(card_model.from_dict(invalid_card) == null)
	for field: String in ["schema_version", "next_card_id"]: # 版本和计数器拒绝非整数、非正数。
		for invalid_value: Variant in [0, -1, 1.5, true, "1"]:
			var invalid_state: Dictionary = JSON.parse_string(encoded) # 保持其他字段合法。
			invalid_state[field] = invalid_value
			assert(state_model.from_dict(invalid_state) == null)
	var invalid_state: Dictionary = JSON.parse_string(encoded) # 未知版本不得按新档默认接受。
	invalid_state.schema_version = 2
	assert(state_model.from_dict(invalid_state) == null)
	invalid_state = JSON.parse_string(encoded)
	invalid_state.next_card_id = 2
	assert(state_model.from_dict(invalid_state) == null) # 下一个编号必须大于所有现存卡编号。
	invalid_state = JSON.parse_string(encoded)
	invalid_state.cards = {"PC000099": valid_card}
	invalid_state.next_card_id = 100
	assert(state_model.from_dict(invalid_state) == null) # 字典键和卡内 UID 必须一致。
	for quantity: Variant in [0, -1, 1.5, true, "2"]: # items 必须为已知道具的正整数。
		invalid_state = JSON.parse_string(encoded)
		invalid_state.items.fertilizer_lv1 = quantity
		assert(state_model.from_dict(invalid_state) == null)
	invalid_state = JSON.parse_string(encoded)
	invalid_state.items = {"unknown": 1}
	assert(state_model.from_dict(invalid_state) == null)
	invalid_state = JSON.parse_string(encoded)
	invalid_state.selected_card_uids = [second, second]
	assert(state_model.from_dict(invalid_state) == null)
	invalid_state.selected_card_uids = ["PC999999"]
	assert(state_model.from_dict(invalid_state) == null)
	invalid_state = JSON.parse_string(encoded)
	invalid_state.regions = {"bad": RefCounted.new()}
	assert(state_model.from_dict(invalid_state) == null)
	state.regions["bad"] = RefCounted.new()
	assert(state.to_dict().is_empty()) # 不让对象混入序列化输出。
	print("PASS: inventory core UID/deck/items/copy/JSON/validation/profile isolation")
	quit(0)
