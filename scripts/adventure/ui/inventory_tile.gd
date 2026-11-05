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
var _frame: TextureRect
var _hovered := false

func setup(value: Dictionary, target: int, may_drag: bool, plants_tab: bool = false, active: bool = false) -> void:
	record = value.duplicate(true)
	index = target
	drag_allowed = may_drag
	_plant_slot = plants_tab
	_selected = active
	size = Vector2(86, 96)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_slot = Art.image(self, "slots/%s_slot_normal.png" % ("plant" if plants_tab else "item"), Vector2.ZERO, size)
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
		var stars: Label = Art.label(self, "★%s" % record.get("stars", 0), Vector2(8, 78), Vector2(75, 17), 15, Color("eac15e"))
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
			ItemArt.add_recipe_portrait(self, int(record.get("plant_type", 0)), ICON_POSITION + ICON_SIZE * 0.5, 0.42)
			var wax: String = ItemArt.recipe_overlay_uri(str(record["id"]))
			if not wax.is_empty():
				Art.image(self, wax, Vector2(49, 47), Vector2(20, 20))
		var amount: Label = Art.label(self, "×%d" % int(record.get("qty", 0)), Vector2(8, 66), Vector2(72, 23), 17)
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# Border-only overlay is always the top child, above icons, wax seal and quantity.
	_frame = Art.image(self, "slots/%s_slot_selected_frame.png" % ("plant" if plants_tab else "item"), Vector2.ZERO, size)
	_update_frame()

## Selection affects only the border overlay, never the slot backing or icon.
func set_active(value: bool) -> void:
	_selected = value
	_update_frame()

func _update_frame() -> void:
	if not is_instance_valid(_frame):
		return
	_frame.visible = not record.is_empty() and (_selected or _hovered)
	if _frame.visible:
		var prefix := "plant" if _plant_slot else "item"
		var state := "selected" if _selected else "hover"
		_frame.texture = Art.texture("slots/%s_slot_%s_frame.png" % [prefix, state])

func _on_mouse_entered() -> void:
	_hovered = true
	_update_frame()

func _on_mouse_exited() -> void:
	_hovered = false
	_update_frame()

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
