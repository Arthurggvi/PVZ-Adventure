## Work-area widgets for upgrade and promotion; selection only, no business mutations.
extends RefCounted
const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")
const Names = preload("res://scripts/adventure/ui/inventory_data.gd")
const ItemArt = preload("res://scripts/adventure/ui/inventory_item_art.gd")

static func _label(parent: Node, message: String, pos: Vector2, size: Vector2,
		font: int = 24, color: Color = Color("4b3324")) -> void:
	Art.label(parent, message, pos, size, font, color)

static func plant(parent: Control, type_id: int, pos: Vector2, dimensions: Vector2) -> void:
	Art.image(parent, "slots/plant_slot_normal.png", pos, dimensions)
	if not PlantCardInstance.is_plant_type(type_id):
		Art.image(parent, "slots/empty_plant_symbol.png",
			pos + dimensions * 0.22, dimensions * 0.55)
		return
	var ref := ResourceCardReference.create(ResourceCardReference.CardType.Plant, type_id)
	var card: Card = AllCards.create_card(ref, Card.CardContext.Catalog)
	if card == null:
		return
	parent.add_child(card)
	card.visible = true
	card.size = card.get_combined_minimum_size()
	var factor := minf(dimensions.x / card.size.x, dimensions.y / card.size.y) * 0.88
	card.scale = Vector2.ONE * factor
	card.position = pos + (dimensions - card.size * factor) * 0.5
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.button.mouse_filter = Control.MOUSE_FILTER_IGNORE

static func upgrade(owner: Control, parent: Control,
		preview: Dictionary, selection: Dictionary, picking: bool) -> void:
	var main_type := int(preview.get("type", 0))
	_label(parent, "主卡：%s" % (Names.plant_name(main_type) if main_type > 0 else "请选择"),
		Vector2(600, 427), Vector2(590, 43), 25)
	plant(parent, main_type, Vector2(856, 483), Vector2(150, 175))
	_label(parent, "%d → %d 星" % [int(preview.get("stars", 0)),
		int(preview.get("target_star", 0))],
		Vector2(1018, 535), Vector2(210, 48), 26)
	var material_cards: Array = preview.get("material_cards", [])
	for index: int in range(3):
		var pos := Vector2(618 + index * 199, 681)
		var card: Dictionary = material_cards[index] if index < material_cards.size() else {}
		var uid: String = str(card.get("uid", ""))
		plant(parent, int(card.get("plant_type", 0)), pos, Vector2(126, 126))
		var card_name := "空耗材槽"
		if not card.is_empty():
			card_name = "%s ★%d" % [Names.plant_name(int(card.plant_type)), int(card.stars)]
		_label(parent, card_name, pos + Vector2(-6, 132), Vector2(182, 30), 19)
		if not uid.is_empty():
			_hit(parent, pos, Vector2(126, 126), Callable(owner, "remove_material").bind(uid))
	var caption := "选择耗材中…" if picking else "添加耗材卡"
	Art.action_button(parent, caption, "buttons/action_neutral",
		Vector2(599, 515), Vector2(217, 58), Callable(owner, "toggle_material_pick"))
	_label(parent, "强化费用：$%d" % int(preview.get("fee", 0)), Vector2(1315, 444), Vector2(425, 43), 28)
	_label(parent, "成功率：下一阶段接入", Vector2(1315, 505), Vector2(445, 43), 25)
	_label(parent, "4星起失败降1星（未保护）", Vector2(1315, 560),
		Vector2(445, 48), 22)
	var pot_count := int(preview.get("pot_required", 0))
	_label(parent, "育苗花盆：%d / %d" % [int(preview.get("pot_owned", 0)), pot_count],
		Vector2(1315, 624), Vector2(434, 38), 23)
	Art.action_button(parent, "保星：" + ("开启" if selection.get("use_pot", false) else "关闭"),
		"buttons/action_neutral", Vector2(1318, 670), Vector2(225, 58),
		Callable(owner, "toggle_protection"))
	var fertilizer: String = str(selection.get("fertilizer", ""))
	_label(parent, "肥料：" + (ItemRegistry.get_item_definition(fertilizer).get("name", "无")
		if not fertilizer.is_empty() else "无"), Vector2(1315, 737), Vector2(443, 40), 22)
	Art.action_button(parent, "更换肥料", "buttons/action_neutral",
		Vector2(1318, 786), Vector2(225, 58), Callable(owner, "cycle_fertilizer"))

static func promotion(owner: Control, parent: Control,
		preview: Dictionary, selection: Dictionary) -> void:
	var type_id := int(preview.get("type", 0))
	var tier := int(preview.get("tier", 0))
	_label(parent, "当前植物", Vector2(675, 431), Vector2(225, 42), 27)
	plant(parent, type_id, Vector2(686, 493), Vector2(156, 190))
	_label(parent, "→", Vector2(874, 537), Vector2(70, 75), 48)
	_label(parent, "第 %d 阶转职" % tier if tier > 0 else "转职完成",
		Vector2(950, 431), Vector2(255, 42), 26)
	var branches: Array = preview.get("branches", [])
	for index: int in branches.size():
		var b: Dictionary = branches[index]
		var pos := Vector2(939, 491 + index * 103)
		var selected := str(selection.get("book_id", "")) == str(b.id)
		var panel := Art.panel(parent, "panels/wood_ninepatch.png", pos, Vector2(285, 87), 20)
		panel.modulate = Color("f4d28a") if selected else Color.WHITE
		_label(parent, str(b.title), pos + Vector2(18, 4),
			Vector2(248, 42), 25, Color("f9e6bf"))
		_label(parent, "转职书 ×%d" % int(b.get("owned", 0)),
			pos + Vector2(18, 42), Vector2(248, 34), 19, Color("f9e6bf"))
		_hit(parent, pos, Vector2(285, 87),
			Callable(owner, "choose_branch").bind(str(b.id)))
	_label(parent, "分支仅可选择一次", Vector2(635, 771), Vector2(560, 48), 25)
	_label(parent, "转职费用：$%d" % int(preview.get("fee", 0)), Vector2(1315, 445), Vector2(455, 45), 28)
	_label(parent, "星级：%d（转职不改变星级）" % int(preview.get("stars", 0)),
		Vector2(1315, 512), Vector2(450, 45), 23)
	_label(parent, "对应转职书必须持有", Vector2(1315, 569), Vector2(450, 45), 23)
	_label(parent, "选定后不可更改或退回", Vector2(1315, 625),
		Vector2(450, 45), 22)
	var current := str(selection.get("book_id", ""))
	for b: Dictionary in branches:
		if str(b.id) == current:
			_label(parent, str(b.get("summary", "")), Vector2(1315, 695),
				Vector2(450, 85), 21)
			break

static func _hit(parent: Control, pos: Vector2, size: Vector2, action: Callable) -> void:
	var button := Button.new()
	button.flat = true
	button.position = pos
	button.size = size
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(action)
	parent.add_child(button)
