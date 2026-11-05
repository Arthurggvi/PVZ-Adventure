## One page factory per cheat module. The UI never owns inventory or progress data.
extends RefCounted

static func _title(parent: Node, value: String) -> void:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", 23)
	parent.add_child(label)

static func _note(parent: Node, value: String) -> void:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 15)
	parent.add_child(label)

static func _row(parent: Node) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	return row

static func _button(parent: Node, value: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size = Vector2(135, 43)
	button.pressed.connect(action)
	parent.add_child(button)
	return button

static func _count(parent: Node, value: int, upper: int) -> SpinBox:
	var number := SpinBox.new()
	number.min_value = 1
	number.max_value = upper
	number.step = 1
	number.rounded = true
	number.value = value
	number.custom_minimum_size = Vector2(118, 42)
	parent.add_child(number)
	return number

static func _select(parent: Node, width: int = 300) -> OptionButton:
	var choice := OptionButton.new()
	choice.custom_minimum_size = Vector2(width, 43)
	choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(choice)
	return choice

static func _plants(choice: OptionButton, query: String) -> void:
	choice.clear()
	var values: Array = CharacterRegistry.PlantType.keys()
	values.sort()
	for key: String in values:
		var id: int = int(CharacterRegistry.PlantType[key])
		if not PlantCardInstance.is_plant_type(id):
			continue
		var name: String = str(Global.character_registry.get_plant_info(id as CharacterRegistry.PlantType,
			CharacterRegistry.PlantInfoAttribute.PlantName))
		var caption: String = "%s · %s" % [name, key]
		if query.is_empty() or caption.to_lower().contains(query.to_lower()):
			choice.add_item(caption, id)
	if choice.item_count > 0:
		choice.select(0)

static func build(parent: VBoxContainer, section: String, service: RefCounted, report: Callable) -> void:
	match section:
		"cards": _cards(parent, service, report)
		"items": _items(parent, service, report)
		"coins": _coins(parent, service, report)
		"stages": _stages(parent, service, report)
		"saves": _saves(parent, service, report)

static func _cards(root: VBoxContainer, service: RefCounted, report: Callable) -> void:
	_title(root, "获得植物卡牌")
	_note(root, "从游戏植物目录选取；每张卡获得独立 UID、星级及背包排序。")
	var search := LineEdit.new()
	search.placeholder_text = "筛选植物名称或英文 ID"
	root.add_child(search)
	var choice := _select(root)
	_plants(choice, "")
	search.text_changed.connect(func(value: String): _plants(choice, value))
	var row := _row(root)
	_note(row, "数量")
	var count := _count(row, 1, 32)
	_note(row, "星级")
	var stars := _count(row, 1, 10)
	stars.min_value = 0
	stars.value = 0
	_button(root, "获得卡牌", func():
		if choice.item_count == 0:
			report.call({"ok": false, "message": "没有匹配的植物。"})
		else:
			report.call(service.add_cards(choice.get_selected_id(), int(stars.value), int(count.value))))

static func _items(root: VBoxContainer, service: RefCounted, report: Callable) -> void:
	_title(root, "获得 / 扣除物品")
	_note(root, "物品 ID 直接读取 ItemRegistry；材料、配方、钥匙与消耗品使用同一库存。")
	var search := LineEdit.new()
	search.placeholder_text = "筛选物品名称或 ID"
	root.add_child(search)
	var choice := _select(root)
	var ids: Array = ItemRegistry.ITEMS.keys()
	ids.sort()
	var refill := func(query: String):
		choice.clear()
		for id: String in ids:
			var def: Dictionary = ItemRegistry.get_item_definition(id)
			var caption: String = "%s · %s" % [def.get("name", id), id]
			if query.is_empty() or caption.to_lower().contains(query.to_lower()):
				choice.add_item(caption)
				choice.set_item_metadata(choice.item_count - 1, id)
		if choice.item_count > 0:
			choice.select(0)
	refill.call("")
	search.text_changed.connect(refill)
	var row := _row(root)
	_note(row, "数量")
	var count := _count(row, 1, 1000000)
	var actions := _row(root)
	_button(actions, "获得物品", func():
		if choice.item_count == 0:
			report.call({"ok": false, "message": "请先选择物品。"})
		else:
			report.call(service.change_item(str(choice.get_selected_metadata()), int(count.value))))
	_button(actions, "扣除物品", func():
		if choice.item_count == 0:
			report.call({"ok": false, "message": "请先选择物品。"})
		else:
			report.call(service.change_item(str(choice.get_selected_metadata()), -int(count.value))))
	_note(root, "一键资源（统一进入真实库存）")
	var quick := _row(root)
	for entry: Dictionary in [{"label": "全部材料×10", "category": "material", "count": 10},
		{"label": "全部配方×1", "category": "recipe", "count": 1},
		{"label": "全部钥匙×1", "category": "key", "count": 1}]:
		var category: String = entry.category
		var amount: int = entry.count
		_button(quick, entry.label, func(): report.call(service.grant_category(category, amount)))

static func _coins(root: VBoxContainer, service: RefCounted, report: Callable) -> void:
	_title(root, "统一金币")
	_note(root, "银币 / 金币 / 钻石是掉落面额，统一写入 coin_value。")
	var balance := Label.new()
	balance.text = "当前余额：%d" % Global.global_game_state.coin_value
	root.add_child(balance)
	var number := _count(root, 1000, 1000000000)
	number.min_value = 0 # Resetting a balance to zero is a supported cheat action.
	var row := _row(root)
	for operation: String in ["add", "sub", "set"]:
		var op: String = operation
		var label: String = {"add": "增加", "sub": "扣除", "set": "设为"}[op]
		_button(row, label, func():
			var result: Dictionary = service.change_coin(int(number.value), op)
			report.call(result)
			balance.text = "当前余额：%d" % Global.global_game_state.coin_value)
	_note(root, "当前余额可在背包上方查看；所有操作立即保存。")

static func _stages(root: VBoxContainer, service: RefCounted, report: Callable) -> void:
	_title(root, "关卡与通关")
	_note(root, "解锁与标记通关会写入当前存档；标记通关绝不发放掉落。")
	var stage := _select(root)
	for index: int in range(1, 7):
		stage.add_item("%d · %s" % [index, AdventureStageRegistry.display_name(index)], index)
	var phase := _select(root)
	phase.add_item("普通", 0)
	phase.add_item("噩梦", 1)
	var row := _row(root)
	_button(row, "解锁至此关", func(): report.call(service.unlock_stage(stage.get_selected_id(), phase.get_selected_id() == 1)))
	_button(row, "标记通关", func(): report.call(service.clear_stage(stage.get_selected_id(), phase.get_selected_id() == 1)))
	var second := _row(root)
	_button(second, "解锁并进入", func(): report.call(service.enter_stage(stage.get_selected_id(), phase.get_selected_id() == 1)))
	_button(second, "真实胜利结算", func(): report.call(service.settle_current()))
	_button(root, "全部普通关卡通关（无奖励）", func(): report.call(service.clear_stage(6, false)))
	_note(root, "真实结算遵守 Boss / 战斗事件条件；未满足时使用“标记通关”跳过奖励。")

static func _saves(root: VBoxContainer, service: RefCounted, report: Callable) -> void:
	_title(root, "当前玩家备份")
	_note(root, "备份属于当前玩家；每次重新备份会覆盖上一次。禁止在战斗中执行。")
	_button(root, "创建存档快照", func(): report.call(service.snapshot()))
	var confirm := ConfirmationDialog.new()
	confirm.title = "恢复玩家存档"
	confirm.dialog_text = "恢复后将替换当前玩家的金币、卡牌、物品和关卡进度。继续？"
	root.add_child(confirm)
	confirm.confirmed.connect(func(): report.call(service.restore()))
	_button(root, "从快照恢复…", func(): confirm.popup_centered(Vector2i(520, 180)))
