## One page factory per cheat module. The UI never owns inventory or progress data.
extends RefCounted

## 与背包共用植物中文名，包括图鉴之外的特殊植物。
const InventoryData = preload("res://scripts/adventure/ui/inventory_data.gd")
## 按物品目录的类别组织选择菜单；未定义的类别放入“其他”。
const ITEM_CATEGORIES := {
	"material": "材料",
	"recipe": "配方",
	"promotion_book": "转职书",
	"key": "钥匙",
	"consumable": "消耗品",
	"other": "其他",
}

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

## 按 [param query] 筛选 [param choice] 的植物。仅显示中文名，仍可用图鉴键或枚举 ID 搜索。
static func _plants(choice: OptionButton, query: String) -> void:
	choice.clear()
	var needle: String = query.strip_edges().to_lower() # 中文名称和内部 ID 使用同一搜索词。
	var values: Array = CharacterRegistry.PlantType.keys() # 保留注册表编号对应的显示顺序。
	values.sort()
	for key: String in values: # 枚举键只参与搜索，发放仍使用数值 ID。
		var id: int = int(CharacterRegistry.PlantType[key]) # 对应存档中的植物类型。
		if not PlantCardInstance.is_plant_type(id):
			continue
		var caption: String = InventoryData.plant_name(id) # 与游戏背包显示一致。
		if not needle.is_empty() and not caption.to_lower().contains(needle) and not key.to_lower().contains(needle):
			var almanac_key: String = str(Global.character_registry.get_plant_info(
				id as CharacterRegistry.PlantType, CharacterRegistry.PlantInfoAttribute.PlantName)) # 兼容原图鉴英文键。
			if not almanac_key.to_lower().contains(needle):
				continue
		choice.add_item(caption, id)
	if choice.item_count > 0:
		choice.select(0)

static func build(parent: VBoxContainer, section: String, service: RefCounted, report: Callable) -> void:
	match section:
		"cards": _cards(parent, service, report)
		"items": _items(parent, service, report)
		"player": _player(parent, service, report)
		"coins": _coins(parent, service, report)
		"stages": _stages(parent, service, report)
		"quests": _quests(parent, service, report)
		"battle": _battle(parent, service, report)
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

## 更新 [param choice] 的当前显示和库存操作所用的 [param id]；[param caption] 为对应的物品标签。
static func _set_item_choice(choice: MenuButton, id: String, caption: String) -> void:
	choice.set_meta(&"item_id", id)
	choice.text = caption + "  ▾"
	choice.tooltip_text = caption

## 创建可选择具体物品的子菜单，选择后将物品标签和库存 ID 写入 [param choice]。
static func _create_item_leaf_menu(choice: MenuButton) -> PopupMenu:
	var menu := PopupMenu.new() # 此菜单只接收可发放或扣除的物品项。
	menu.index_pressed.connect(func(index: int) -> void: # 索引用于读取选中项的库存 ID 和标签。
		_set_item_choice(choice, str(menu.get_item_metadata(index)), menu.get_item_text(index)))
	return menu

## 按 [param query] 重建 [param choice] 的分类菜单。转职书按所属植物再分组，默认选择第一项匹配的物品。
static func _refill_item_choice(choice: MenuButton, query: String) -> void:
	var popup: PopupMenu = choice.get_popup() # 顶层菜单只列有匹配项的类别。
	popup.clear(true)
	_set_item_choice(choice, "", "没有匹配的物品")
	var needle: String = query.strip_edges().to_lower() # 支持物品名称、ID 和转职书所属植物。
	var ids: Array = ItemRegistry.ITEMS.keys() # 使用稳定的 ID 排序，便于查找。
	ids.sort()
	var groups: Dictionary[String, PopupMenu] = {} # 各类别的子菜单按需创建。
	var plant_menus: Dictionary[int, PopupMenu] = {} # 按植物编号合并转职书，同一植物只出现一次。
	for id: String in ids: # 每条目录记录仅在其所属类别中出现一次。
		var definition: Dictionary = ItemRegistry.get_item_definition(id) # 复用正式物品名及分类。
		var caption: String = "%s · %s" % [definition.get("name", id), id] # 保留物品 ID 以便区分同名道具。
		var category: String = str(definition.get("category", "")) # 与背包使用相同的目录分类。
		var is_promotion_book: bool = category == "promotion_book" # 仅转职书有所属植物子菜单。
		var plant_type: int = 0 # 编号 0 表示技能目录未指定植物。
		var plant_name: String = "" # 仅转职书提供可筛选的植物名。
		if is_promotion_book:
			plant_type = int(AdventurePromotionCatalog.definition(id).get("plant_type", 0))
			plant_name = InventoryData.plant_name(plant_type) if plant_type > 0 else "未标注植物"
		if not needle.is_empty() and not caption.to_lower().contains(needle) and not plant_name.to_lower().contains(needle):
			continue
		if not ITEM_CATEGORIES.has(category):
			category = "other"
		var submenu: PopupMenu = groups.get(category) # 先定位类别菜单，转职书随后定位到植物菜单。
		if submenu == null:
			submenu = PopupMenu.new() if is_promotion_book else _create_item_leaf_menu(choice)
			groups[category] = submenu
		if is_promotion_book:
			var plant_menu: PopupMenu = plant_menus.get(plant_type) # 只为有匹配技能书的植物显示入口。
			if plant_menu == null:
				plant_menu = _create_item_leaf_menu(choice)
				plant_menus[plant_type] = plant_menu
				submenu.add_submenu_node_item(plant_name, plant_menu)
			submenu = plant_menu
		submenu.add_item(caption)
		submenu.set_item_metadata(submenu.item_count - 1, id)
		if choice.get_meta(&"item_id") == "":
			_set_item_choice(choice, id, caption)
	for category: String in ITEM_CATEGORIES: # 按目录类别的显示顺序注册子菜单。
		if groups.has(category):
			popup.add_submenu_node_item(ITEM_CATEGORIES[category], groups[category])
	choice.disabled = popup.item_count == 0

## 在 [param root] 创建物品页；[param service] 负责库存事务，[param report] 显示操作结果。
static func _items(root: VBoxContainer, service: RefCounted, report: Callable) -> void:
	_title(root, "获得 / 扣除物品")
	var search := LineEdit.new() # 同时筛选所有物品类别。
	search.placeholder_text = "筛选物品名称、所属植物或 ID"
	root.add_child(search)
	var choice := MenuButton.new() # 原生下拉菜单处理分类的展开、收起及键盘导航。
	choice.flat = false
	choice.focus_mode = Control.FOCUS_ALL
	choice.alignment = HORIZONTAL_ALIGNMENT_LEFT
	choice.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	choice.custom_minimum_size = Vector2(300, 43)
	root.add_child(choice)
	_refill_item_choice(choice, "")
	search.text_changed.connect(func(query: String) -> void: _refill_item_choice(choice, query))
	var row := _row(root) # 数量供获得和扣除共用。
	_note(row, "数量")
	var count := _count(row, 1, 1000000) # 单次操作的数量范围由库存命令限制。
	var actions := _row(root) # 对当前选中的同一物品执行增减操作。
	_button(actions, "获得物品", func():
		if choice.disabled:
			report.call({"ok": false, "message": "请先选择物品。"})
		else:
			report.call(service.change_item(str(choice.get_meta(&"item_id")), int(count.value))))
	_button(actions, "扣除物品", func():
		if choice.disabled:
			report.call({"ok": false, "message": "请先选择物品。"})
		else:
			report.call(service.change_item(str(choice.get_meta(&"item_id")), -int(count.value))))
	_note(root, "一键资源（转职书和钥匙每种 +1）")
	var quick := _row(root) # 材料和配方保留各自的批量发放数量。
	_button(quick, "全部材料×10", func(): report.call(service.grant_category("material", 10)))
	_button(quick, "全部配方×1", func(): report.call(service.grant_category("recipe", 1)))
	var books_and_keys := _row(root) # 单独一行容纳转职书和钥匙的完整按钮文案。
	_button(books_and_keys, "一键获得所有转职书", func(): report.call(service.grant_category("promotion_book", 1)))
	_button(books_and_keys, "一键获得所有钥匙", func(): report.call(service.grant_category("key", 1)))
	_equipment(root, service, report)

## 角色调试入口只调用正式命令；[param root] 为页面容器，[param service] 提交事务，[param report] 显示结果。
static func _player(root: VBoxContainer, service: RefCounted, report: Callable) -> void:
	_equipment(root, service, report)
	var row: HBoxContainer = _row(root) # 等级设置与装备授予各自独立提交。
	var highest: int = int(PlayerProgression.progress(PlayerProgression.MAX_EXPERIENCE).level) # 取真实可表示上限。
	var level: SpinBox = _count(row, 1, highest) # 输入值为目标等级，不是经验。
	_button(row, "设置角色等级", func(): report.call(service.set_player_level(int(level.value))))

## 在 [param root] 创建共用的装备发放区；[param service] 提交事务，[param report] 显示结果。
static func _equipment(root: VBoxContainer, service: RefCounted, report: Callable) -> void:
	_title(root, "获得装备")
	_note(root, "在地图上发放装备，领取后到角色的装备背包查看。限时装备从发放时开始计时。")
	var choice: OptionButton = _select(root) # 内容来自正式装备目录。
	for item: EquipmentDefinition in EquipmentCatalog.definitions(): # 不复制装备 ID 列表。
		var caption: String = item.display_name # 获取前标明限时版本的有效天数。
		if item.lifetime_days > 0:
			caption += "（%d 天）" % item.lifetime_days
		choice.add_item(caption)
		choice.set_item_metadata(choice.item_count - 1, str(item.id))
	if choice.item_count > 0:
		choice.select(0)
	var grant: Button = _button(root, "获得所选装备", func(): # 两页都通过同一发放事务。
		if choice.item_count > 0:
			report.call(service.grant_equipment(str(choice.get_selected_metadata()))))
	grant.disabled = choice.item_count == 0

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

## 在 [param root] 列出全部任务；[param service] 提交领奖或设施解锁，[param report] 显示结果。
static func _quests(root: VBoxContainer, service: RefCounted, report: Callable) -> void:
	_title(root, "任务奖励")
	_note(root, "可领取尚未解锁或未完成的任务奖励。日常任务每期可领一次。")
	var choice := _select(root) # 显示正式任务分组和标题，用稳定 ID 领取。
	choice.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	for task: Dictionary in AdventureQuestCatalog.TASKS: # 包含当前档案尚未接取的任务。
		choice.add_item("%s · %s" % [task.group, task.title])
		choice.set_item_metadata(choice.item_count - 1, task.id)
	if choice.item_count > 0:
		choice.select(0)
	var claim := _button(root, "强制领取奖励", func() -> void: # 每次只领取选中任务。
		if choice.selected >= 0:
			report.call(service.force_claim_quest(str(choice.get_selected_metadata()))))
	claim.disabled = choice.item_count == 0
	_title(root, "设施解锁")
	_note(root, "开放任务入口、研究室、图书馆和戴夫商店，并跳过解锁引导。")
	_button(root, "一键解锁全部设施", func(): report.call(service.unlock_all_facilities()))

## 在 [param parent] 放置由 [param id] 标识的 [param caption] 开关。
## 切换时调用 [param action]，失败则恢复原状态，最后用 [param report] 显示结果。
static func _battle_toggle(parent: VBoxContainer, id: StringName, caption: String,
		action: Callable, report: Callable) -> void:
	var toggle := CheckButton.new() # 使用 Godot 的滑动开关，支持鼠标和键盘切换。
	toggle.name = id
	toggle.text = caption
	toggle.custom_minimum_size.y = 36
	toggle.toggled.connect(func(enabled: bool) -> void:
		var result: Dictionary = action.call(enabled) # 以命令结果为准，避免失败后显示成已启用。
		if not result.get("ok", false):
			toggle.set_pressed_no_signal(not enabled)
		report.call(result)
	)
	parent.add_child(toggle)

## 通过 [param service] 将 [param root] 中的战斗开关与当前战场同步。
static func refresh_battle_toggles(root: VBoxContainer, service: RefCounted) -> void:
	var group := root.get_node_or_null("BattleToggles") as VBoxContainer # 页面切换后此组可能尚未创建。
	if group == null:
		return
	var states: Dictionary = service.battle_toggle_states() # 缺少状态的开关在当前战斗中不可用。
	for toggle: CheckButton in group.get_children(): # 按开关节点名匹配战斗状态。
		var enabled: Variant = states.get(toggle.name) # bool 表示开关状态，null 表示不可用。
		toggle.disabled = enabled == null
		toggle.set_pressed_no_signal(enabled == true)

## 在 [param root] 绘制战斗工具，[param service] 执行命令，[param report] 接收结果。
static func _battle(root: VBoxContainer, service: RefCounted, report: Callable) -> void:
	_title(root, "战斗")
	_note(root, "仅在正式战斗中可用。单只出怪会随机选择兼容行，各路生成会先检查地形。")
	_note(root, "秒杀开启后，新生成的僵尸和 Boss 会立即死亡，本局有效。")
	var toggles := VBoxContainer.new() # 将持续生效的战斗开关放在一组。
	toggles.name = "BattleToggles"
	root.add_child(toggles)
	_battle_toggle(toggles, &"instant_kill", "秒杀", Callable(service, "set_battle_instant_kill"), report)
	_battle_toggle(toggles, &"no_card_cooldown", "卡牌无冷却", Callable(service, "set_battle_no_card_cooldown"), report)
	_battle_toggle(toggles, &"infinite_sun", "无限阳光", Callable(service, "set_battle_infinite_sun"), report)
	refresh_battle_toggles(root, service)
	_note(root, "僵尸类型")
	var zombie: OptionButton = _select(root) # 选项 ID 直接使用僵尸注册表枚举值。
	Global.global_read_data.ensure_almanac_loaded()
	var almanac: Dictionary = Global.global_read_data.data_almanac.get("Zombie", {}) # 复用图鉴中文名。
	var types: Array = CharacterRegistry.ZombieInfo.keys() # 只枚举有可用角色定义的普通僵尸。
	types.sort()
	for zombie_type: int in types: # 按注册编号排序。
		var key: String = str(CharacterRegistry.ZombieInfo[zombie_type][CharacterRegistry.ZombieInfoAttribute.ZombieName]) # 用图鉴键查名称。
		var entry: Dictionary = almanac.get(key, {}) # 无图鉴条目的类型显示注册名。
		zombie.add_item(str(entry.get("名字", key)), zombie_type)
	zombie.select(0)
	_note(root, "等阶")
	var tier: OptionButton = _select(root) # 展示现有的一至五阶，元数据保留稳定等阶 ID。
	for tier_id: StringName in AdventureZombieTierCatalog.tier_ids(): # 目录顺序对应等阶编号。
		tier.add_item("%d 阶" % (tier.item_count + 1))
		tier.set_item_metadata(tier.item_count - 1, tier_id)
	tier.select(0)
	var spawn_buttons: HBoxContainer = _row(root) # 两个出怪动作共用当前选项。
	_button(spawn_buttons, "生成一只", func():
		report.call(service.spawn_battle_zombies(zombie.get_selected_id(), StringName(tier.get_selected_metadata()), false)))
	_button(spawn_buttons, "各路各一只", func():
		report.call(service.spawn_battle_zombies(zombie.get_selected_id(), StringName(tier.get_selected_metadata()), true)))
	_note(root, "Boss 类型")
	var boss: OptionButton = _select(root) # 选项 ID 来自 Boss 注册表，与普通僵尸等阶无关。
	var boss_almanac: Dictionary = Global.global_read_data.data_almanac.get("ZombieBoss", {}) # 已收录的中文名称。
	var boss_types: Array = CharacterRegistry.ZombieBossInfo.keys() # 目录自动纳入后续注册的 Boss。
	boss_types.sort()
	for boss_type: int in boss_types: # 按注册编号显示可召唤类型。
		var key: String = str(CharacterRegistry.ZombieBossInfo[boss_type][CharacterRegistry.ZombieBossInfoAttribute.BossName]) # 图鉴条目键。
		var entry: Dictionary = boss_almanac.get(key, {}) # 白公爵等尚未收录的 Boss 可照常召唤。
		var fallback: String = "白公爵" if boss_type == CharacterRegistry.ZombieBossType.ZB003WhiteDuke else key # 白公爵尚无图鉴条目时显示通用中文名。
		boss.add_item(str(entry.get("名字", fallback)), boss_type)
	boss.select(0)
	_button(root, "召唤 Boss", func(): report.call(service.spawn_battle_boss(boss.get_selected_id())))
	_note(root, "一键通关会结束当前阶段并保存正式结算；跳过的 Boss 不计击杀。")
	_button(root, "一键通关", func(): report.call(service.clear_current_battle()))

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
