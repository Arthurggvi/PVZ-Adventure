## 背包格子的底图、图标与边框独立布局；数量徽标始终覆盖在边框上层。
extends Control
signal chosen(record: Dictionary)
signal reorder_requested(uid: String, target: int)
const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")
const ItemArt = preload("res://scripts/adventure/ui/inventory_item_art.gd")
const Data = preload("res://scripts/adventure/ui/inventory_data.gd")
## 道具底图按格子高度等比填充，透明边缘允许超出格子的水平区域。
const BACKING_SIZE := Vector2(96, 96)
## 底图相对 86 × 96 格子的居中坐标，不改变格子尺寸。
const BACKING_POSITION := (Vector2(86, 96) - BACKING_SIZE) * 0.5
## 道具前景保留相对分类底图的原始大小比例。
const ICON_SIZE := BACKING_SIZE * (58.0 / 68.0)
## 前景与底图共用格子中心。
const ICON_POSITION := (Vector2(86, 96) - ICON_SIZE) * 0.5
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
			card.plant_spawn_profile = AdventureBattleAdapter.profile_for(record)
			add_child(card)
			card.visible = true
			# 还原卡牌原生尺寸，避免继承源目录容器拉伸后的比例。
			card.size = card.get_combined_minimum_size()
			var card_scale: float = size.y / card.size.y # 按格子高度等比填充。
			card.scale = Vector2.ONE * card_scale
			card.position = (size - card.size * card_scale) * 0.5 # 两个方向均居中。
			card.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var stars: Label = Art.label(self, "★%s" % record.get("stars", 0), Vector2(8, 78), Vector2(75, 17), 15, Color("eac15e"))
		stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	else:
		# 分类底图或卷轴替换普通方格的填色，默认边框在内容之后独立绘制。
		var backing: String = Data.item_backing(record)
		var category: String = str(record.get("category", "")) # 配方和转职书都使用卷轴作为底图。
		var uses_scroll: bool = category in ["recipe", "promotion_book"] # 卷轴格保留边框，隐藏普通方格填色。
		_slot.visible = backing.is_empty() and not uses_scroll
		if not backing.is_empty():
			Art.image(self, backing, BACKING_POSITION, BACKING_SIZE)
		var icon: String = Data.item_icon(record)
		var icon_size: Vector2 = BACKING_SIZE if uses_scroll else ICON_SIZE # 卷轴使用完整底图区域。
		var icon_position: Vector2 = (size - icon_size) * 0.5 # 所有道具前景共用格子中心。
		if not icon.is_empty():
			Art.image(self, icon, icon_position, icon_size)
		if category == "recipe":
			var recipe_scale: float = icon_size.y / 58.0 # 植物和蜡封随卷轴整体等比放大。
			ItemArt.add_recipe_portrait(self, int(record.get("plant_type", 0)), size * 0.5, 0.42 * recipe_scale)
			var wax: String = ItemArt.recipe_overlay_uri(str(record["id"]))
			if not wax.is_empty():
				Art.image(self, wax, icon_position + Vector2(35, 39) * recipe_scale, Vector2(20, 20) * recipe_scale)
		Art.count_badge(self, "×%d" % int(record.get("qty", 0)), size - Vector2(4, 5))
	# 默认边框常驻内容上层，悬停与选中边框再叠加在默认边框之上。
	Art.slot_frame(self, Vector2.ZERO, size, plants_tab)
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
