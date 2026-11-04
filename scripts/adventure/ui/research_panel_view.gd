## Rebuilds mode-only contents; all textures and card portraits are shared game resources.
## Selectable rows change the preview only. Material slots are deliberately non-interactive.
extends RefCounted
const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")
const Preview = preload("res://scripts/adventure/ui/research_preview_data.gd")

static func render(owner: Control, target: Control, mode: String, choice: int) -> void:
	for child: Node in target.get_children():
		target.remove_child(child)
		child.queue_free()
	var options: Array = Preview.records(mode)
	var record: Dictionary = options[clampi(choice, 0, options.size() - 1)]
	Art.label(target, "选择区", Vector2(149, 368), Vector2(335, 52), 34)
	Art.label(target, "工作区", Vector2(582, 368), Vector2(600, 52), 34)
	Art.label(target, "信息区", Vector2(1303, 368), Vector2(447, 52), 34)
	_text(target, "预览选项 · 不改变背包", Vector2(149, 422), 25)
	for index in options.size():
		_add_choice(target, options[index], index, index == choice, owner)
	match mode:
		"craft": _craft(target, record)
		"upgrade": _upgrade(target, record)
		"promotion": _promotion(target, record)

static func _text(parent: Node, value: String, at: Vector2, size: int = 24,
		color: Color = Color("4b3324")) -> void:
	var width := 353.0 if at.x < 545.0 else (625.0 if at.x < 1270.0 else 450.0)
	Art.label(parent, value, at, Vector2(width, 43), size, color)

static func _add_choice(parent: Control, entry: Dictionary, index: int,
		selected: bool, owner: Control) -> void:
	var pos := Vector2(139, 485 + index * 111)
	var row := Art.panel(parent, "panels/wood_ninepatch.png", pos,
		Vector2(358, 87), 18)
	row.modulate = Color("f8cf85") if selected else Color("ffffff")
	Art.image(parent, "icons/category_recipes.png" if owner.mode == "craft" else
		"icons/category_plants.png", pos + Vector2(16, 12), Vector2(61, 60))
	_text(parent, str(entry.title), pos + Vector2(88, 14), 27, Color("f9e1ae"))
	var hit := Button.new()
	hit.name = "ResearchChoice_%d" % index
	hit.position = pos
	hit.size = Vector2(358, 87)
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	hit.pressed.connect(Callable(owner, "choose_entry").bind(index))
	parent.add_child(hit)

static func _material(parent: Control, id: String, pos: Vector2) -> void:
	Art.image(parent, "slots/item_slot_normal.png", pos, Vector2(120, 120))
	Art.image(parent, Preview.ITEM_ROOT + id + ".png",
		pos + Vector2(24, 20), Vector2(72, 72))
	_text(parent, str(Preview.MATERIAL_LABELS.get(id, id)),
		pos + Vector2(-12, 128), 22)

static func _plant(parent: Control, type_id: int, pos: Vector2,
		dimensions: Vector2) -> void:
	Art.image(parent, "slots/plant_slot_normal.png", pos, dimensions)
	var ref := ResourceCardReference.create(ResourceCardReference.CardType.Plant, type_id)
	var card: Card = AllCards.create_card(ref, Card.CardContext.Catalog)
	if card == null:
		Art.image(parent, "slots/empty_plant_symbol.png",
			pos + dimensions * 0.22, dimensions * 0.56)
		return
	parent.add_child(card)
	card.visible = true
	card.size = card.get_combined_minimum_size()
	var factor: float = minf(dimensions.x / card.size.x, dimensions.y / card.size.y) * 0.88
	card.scale = Vector2.ONE * factor
	card.position = pos + (dimensions - card.size * factor) * 0.5
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.button.mouse_filter = Control.MOUSE_FILTER_IGNORE

static func _craft(parent: Control, entry: Dictionary) -> void:
	_text(parent, "选择配方后，材料将自动匹配", Vector2(580, 422), 25)
	var materials: Array = entry.materials
	for i in materials.size():
		_material(parent, str(materials[i]), Vector2(652 + i * 183, 495))
	_text(parent, "→", Vector2(1014, 545), 43)
	_plant(parent, int(entry.type), Vector2(1080, 488), Vector2(114, 154))
	_text(parent, "产物：%s" % str(entry.title).trim_suffix("制作书"),
		Vector2(1315, 435), 28)
	_text(parent, "材料需求", Vector2(1315, 502), 28)
	for i in materials.size():
		_text(parent, "• %s：库存 / 需求待接入" %
			str(Preview.MATERIAL_LABELS.get(str(materials[i]), "")),
			Vector2(1323, 563 + 57 * i), 23)
	_text(parent, "费用：由正式配方数据决定", Vector2(1315, 724))
	_text(parent, "材料槽只读，无需手动选择", Vector2(590, 744), 23)

static func _upgrade(parent: Control, entry: Dictionary) -> void:
	_text(parent, "中央保留主卡，最多三张耗材卡", Vector2(582, 424), 25)
	_plant(parent, int(entry.type), Vector2(834, 458), Vector2(144, 182))
	for i in 3:
		var pos := Vector2(665 + i * 178, 681)
		Art.image(parent, "slots/plant_slot_normal.png", pos, Vector2(124, 145))
		Art.image(parent, "slots/empty_plant_symbol.png",
			pos + Vector2(34, 38), Vector2(56, 63))
		_text(parent, "耗材卡 %d" % (i + 1), pos + Vector2(-3, 148), 21)
	_text(parent, "升星前 → 升星后", Vector2(1315, 444), 28)
	for i in 3:
		Art.image(parent, "overlays/star_filled.png" if i == 0 else
			"overlays/star_empty.png", Vector2(1335 + i * 64, 507), Vector2(56, 56))
	_text(parent, "成功率：等待强化规则", Vector2(1315, 606))
	_text(parent, "失败风险：等待强化规则", Vector2(1315, 665))
	Art.image(parent, "res://assets/adventure/ui/items/consumables/seedling_pot.png",
		Vector2(1324, 729), Vector2(64, 69))
	_text(parent, "育苗花盆：保星道具", Vector2(1404, 741), 22)

static func _promotion(parent: Control, entry: Dictionary) -> void:
	_text(parent, "当前形态", Vector2(680, 443), 28)
	_text(parent, "进阶目标", Vector2(1031, 443), 28)
	_plant(parent, int(entry.type), Vector2(689, 492), Vector2(158, 206))
	_text(parent, "→", Vector2(895, 572), 58)
	Art.image(parent, "slots/plant_slot_disabled.png",
		Vector2(1044, 492), Vector2(150, 206))
	Art.image(parent, "slots/empty_plant_symbol.png",
		Vector2(1088, 549), Vector2(63, 67))
	_text(parent, "分支根据实际职业配置生成", Vector2(599, 766), 22)
	_text(parent, "进阶路线与条件", Vector2(1315, 445), 28)
	_text(parent, "• 原卡保留独立身份", Vector2(1323, 524))
	_text(parent, "• 可用分支：等待定义", Vector2(1323, 592))
	_text(parent, "• 资源要求：等待定义", Vector2(1323, 659))
	_text(parent, "不会预设职业或固定路线数", Vector2(1315, 741), 21)
