## One independently positioned grid slot: slot -> category backing -> item -> text.
extends Control
signal chosen(record: Dictionary)
signal reorder_requested(uid: String, target: int)
const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")
const ItemArt = preload("res://scripts/adventure/ui/inventory_item_art.gd")
const Data = preload("res://scripts/adventure/ui/inventory_data.gd")
const BACKING_POSITION := Vector2(9, 3)
const BACKING_SIZE := Vector2(68, 68)
const ICON_POSITION := Vector2(14, 8)
const ICON_SIZE := Vector2(58, 58)
var record: Dictionary = {}
var index := -1
var drag_allowed := false
var _plant_slot := false
var _selected := false
var _slot: TextureRect

func setup(value: Dictionary, target: int, may_drag: bool, plants_tab: bool = false, active: bool = false) -> void:
	record = value.duplicate(true)
	index = target
	drag_allowed = may_drag
	_plant_slot = plants_tab
	_selected = active
	size = Vector2(86, 96)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_slot = Art.image(self, _slot_file(false), Vector2.ZERO, size)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	if record.is_empty():
		if plants_tab:
			Art.image(self, "slots/empty_plant_symbol.png", Vector2(24, 30), Vector2(38, 36))
		return
	if str(record.get("kind", "")) == "plant":
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
		# Category backing is fixed to THIS slot. It never inherits icon transform.
		var backing: String = Data.item_backing(record)
		if not backing.is_empty():
			Art.image(self, backing, BACKING_POSITION, BACKING_SIZE)
		var icon: String = Data.item_icon(record)
		if not icon.is_empty():
			Art.image(self, icon, ICON_POSITION, ICON_SIZE)
		if str(record.get("category", "")) == "recipe":
			ItemArt.add_recipe_portrait(self, str(record["id"]), ICON_POSITION + ICON_SIZE * 0.5, 0.42)
		var amount: Label = Art.label(self, "×%d" % int(record.get("qty", 0)), Vector2(8, 66), Vector2(72, 23), 17)
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

## Selection changes only the slot texture; backing and item never move.
func set_active(value: bool) -> void:
	_selected = value
	if is_instance_valid(_slot):
		_slot.texture = Art.texture(_slot_file(false))

func _slot_file(hovered: bool) -> String:
	var prefix := "plant" if _plant_slot else "item"
	var state := "hover" if hovered else ("selected" if _selected else "normal")
	return "slots/%s_slot_%s.png" % [prefix, state]

func _on_mouse_entered() -> void:
	if not record.is_empty():
		_slot.texture = Art.texture(_slot_file(true))

func _on_mouse_exited() -> void:
	_slot.texture = Art.texture(_slot_file(false))

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
