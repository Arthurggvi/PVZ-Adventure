## Research shared panel renderer. All input records are service-owned read-only snapshots.
extends RefCounted
const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")
const ItemArt = preload("res://scripts/adventure/ui/inventory_item_art.gd")
const Names = preload("res://scripts/adventure/ui/inventory_data.gd")
const ModeView = preload("res://scripts/adventure/ui/research_mode_view.gd")

static func render(owner: Control, target: Control, mode: String,
		options: Array[Dictionary], choice: int, preview: Dictionary,
		selection: Dictionary, picking: bool) -> void:
	for child: Node in target.get_children():
		target.remove_child(child)
		child.queue_free()
	Art.label(target, "选择区", Vector2(149, 368), Vector2(335, 52), 34)
	Art.label(target, "工作区", Vector2(582, 368), Vector2(600, 52), 34)
	Art.label(target, "信息区", Vector2(1303, 368), Vector2(447, 52), 34)
	var note := "已持有制作书" if mode == "craft" else (
		"请选择耗材卡" if mode == "upgrade" and picking else "选择植物")
	Art.label(target, note, Vector2(149, 420), Vector2(330, 39), 23)
	_choices(owner, target, mode, options, choice)
	if options.is_empty():
		Art.label(target, "当前没有可用条目", Vector2(160, 505),
			Vector2(340, 50), 22)
		return
	match mode:
		"craft":
			_craft(target, preview)
		"upgrade":
			ModeView.upgrade(owner, target, preview, selection, picking)
		"promotion":
			ModeView.promotion(owner, target, preview, selection)

static func _choices(owner: Control, target: Control, mode: String,
		options: Array[Dictionary], chosen: int) -> void:
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(139, 475)
	scroll.size = Vector2(358, 386)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	target.add_child(scroll)
	var stack := VBoxContainer.new()
	stack.custom_minimum_size = Vector2(335, 0)
	stack.add_theme_constant_override("separation", 11)
	scroll.add_child(stack)
	for index: int in options.size():
		var entry: Dictionary = options[index]
		var row := Control.new()
		row.custom_minimum_size = Vector2(335, 86)
		stack.add_child(row)
		var frame := Art.panel(row, "panels/wood_ninepatch.png",
			Vector2.ZERO, Vector2(335, 85), 18)
		frame.modulate = Color("eed087") if index == chosen else Color.WHITE
		Art.image(row, "icons/category_recipes.png" if mode == "craft" else
			"icons/category_plants.png", Vector2(10, 11), Vector2(59, 60))
		var label: String = str(entry.get("title", ""))
		if mode != "craft":
			label = Names.plant_name(int(entry.get("plant_type", 0)))
			label += " ★%d" % int(entry.get("stars", 0))
		var text := Art.label(row, label, Vector2(76, 13),
			Vector2(252, 58), 22, Color("f9e7b8"))
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var button := Button.new()
		button.name = "ResearchChoice_%d" % index
		button.flat = true
		button.size = Vector2(335, 85)
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.pressed.connect(Callable(owner, "choose_entry").bind(index))
		row.add_child(button)

static func _craft(parent: Control, preview: Dictionary) -> void:
	Art.label(parent, "材料自动匹配 · 每种消耗一份", Vector2(580, 420),
		Vector2(630, 52), 25)
	var slots: Array = preview.get("slots", [])
	for index: int in slots.size():
		var slot: Dictionary = slots[index]
		var position := Vector2(595 + index * 192, 497)
		Art.image(parent, "slots/item_slot_normal.png", position, Vector2(137, 137))
		var icon: String = ItemArt.icon_uri(str(slot.id))
		var sprite := Art.image(parent, icon, position + Vector2(24, 20),
			Vector2(90, 90))
		var enough := int(slot.owned) >= int(slot.required)
		if not enough:
			sprite.modulate = Color(0.38, 0.38, 0.38, 0.68)
		Art.label(parent, str(ItemRegistry.get_item_definition(str(slot.id)).get("name", slot.id)),
			position + Vector2(-19, 142), Vector2(185, 38), 20)
		Art.label(parent, "%d / %d" % [int(slot.owned), int(slot.required)],
			position + Vector2(-8, 183), Vector2(155, 39), 22,
			Color("356c38") if enough else Color("b34f3a"))
	ModeView.plant(parent, int(preview.get("plant_type", 0)),
		Vector2(1070, 498), Vector2(136, 175))
	Art.label(parent, "合成产物", Vector2(1315, 437), Vector2(450, 48), 30)
	var plant_type: int = int(preview.get("plant_type", 0))
	Art.label(parent, Names.plant_name(plant_type), Vector2(1315, 507),
		Vector2(445, 51), 28)
	Art.label(parent, "初始星级：0 星", Vector2(1315, 579),
		Vector2(442, 42), 25)
	Art.label(parent, "固定费用：$%d" % int(preview.get("fee", 0)), Vector2(1315, 651),
		Vector2(442, 42), 25)
	Art.label(parent, "消耗制作书 ×1", Vector2(1315, 722),
		Vector2(442, 42), 24)
	Art.label(parent, "单次产出植物卡 ×1", Vector2(600, 786),
		Vector2(596, 43), 23)
