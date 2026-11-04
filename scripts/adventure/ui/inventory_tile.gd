## One drag-aware tile; Godot Card art is sourced from the existing registered template.
extends Control
signal chosen(record: Dictionary)
signal reorder_requested(uid: String, target: int)
const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")
const Data = preload("res://scripts/adventure/ui/inventory_data.gd")
var record: Dictionary = {}
var index := -1
var drag_allowed := false

func setup(value: Dictionary, target: int, may_drag: bool) -> void:
	record = value.duplicate(true)
	index = target
	drag_allowed = may_drag
	size = Vector2(86, 96)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var plant := str(record.get("kind", "")) == "plant"
	Art.image(self, "slots/plant_slot_normal.png" if plant else "slots/item_slot_normal.png", Vector2.ZERO, size)
	if record.is_empty():
		Art.image(self, "slots/empty_plant_symbol.png", Vector2(24, 30), Vector2(38, 36))
		return
	if plant:
		var reference := ResourceCardReference.create(ResourceCardReference.CardType.Plant, int(record["plant_type"]))
		var card: Card = AllCards.create_card(reference, Card.CardContext.Catalog)
		if card != null:
			card.battle_card_data = record.duplicate(true)
			add_child(card)
			card.visible = true
			card.position = Vector2(15, 5)
			card.scale = Vector2(1.10, 1.09)
			card.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var stars: Label = Art.label(self, "★%s" % record.get("stars", 1), Vector2(8, 78), Vector2(75, 17), 15, Color("eac15e"))
		stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	else:
		Art.image(self, Data.item_icon(record), Vector2(14, 5), Vector2(58, 58))
		var amount: Label = Art.label(self, "×%d" % int(record.get("qty", 0)), Vector2(8, 66), Vector2(72, 23), 17)
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

func _gui_input(event: InputEvent) -> void:
	if record.is_empty():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		chosen.emit(record)
		accept_event()

func _get_drag_data(_pos: Vector2) -> Variant:
	if not drag_allowed or str(record.get("kind", "")) != "plant":
		return null
	var preview := TextureRect.new()
	preview.texture = Art.texture("slots/plant_slot_selected.png")
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.custom_minimum_size = Vector2(70, 82)
	set_drag_preview(preview)
	return {"uid": str(record["uid"])}

func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
	return drag_allowed and data is Dictionary and data.has("uid")

func _drop_data(_pos: Vector2, data: Variant) -> void:
	if _can_drop_data(_pos, data):
		reorder_requested.emit(str(data["uid"]), index)
