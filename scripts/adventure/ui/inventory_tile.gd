## 背包格子的底图、图标与边框独立布局；数量徽标始终覆盖在边框上层。
extends Control
signal chosen(record: Dictionary)
signal reorder_requested(uid: String, target: int)
const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")
const ItemArt = preload("res://scripts/adventure/ui/inventory_item_art.gd")
const PromotionVisual = preload("res://scripts/adventure/ui/promotion_book_visual.gd")
const Data = preload("res://scripts/adventure/ui/inventory_data.gd")
## 槽位提示沿用工具栏皮肤。
const HoverTip = preload("res://scripts/adventure/ui/hover_tip_skin.gd")
## 编号徽章使用专属底板和简短提示，仍共用格子交互。
const CollectibleVisual = preload("res://scripts/adventure/ui/collectible_badge_visual.gd")
## 道具底图按格子高度等比填充，透明边缘允许超出格子的水平区域。
const BACKING_SIZE := Vector2(96, 96)
## 底图相对 86 × 96 格子的居中坐标，不改变格子尺寸。
const BACKING_POSITION := (Vector2(86, 96) - BACKING_SIZE) * 0.5
## 道具前景保留相对分类底图的原始大小比例。
const ICON_SIZE := BACKING_SIZE * (58.0 / 68.0)
## 前景与底图共用格子中心。
const ICON_POSITION := (Vector2(86, 96) - ICON_SIZE) * 0.5
## 方形装备槽居中于 86 × 96 的格子，底图边缘略压在槽框内沿下方。
const EQUIPMENT_BACKING_BOUNDS := Rect2(6, 11, 74, 74)
## 要露出底图边缘的方形图标，四周各内缩 7 个设计像素。
const EQUIPMENT_ICON_INSET := 7.0
var record: Dictionary = {}
## 格子已经装配的植物卡，供研究室预览读取实际属性；道具和空槽为空。
var plant_card: Card
var index := -1
var drag_allowed := false
var _plant_slot := false
var _selected := false
var _slot: TextureRect
var _frame: TextureRect
var _hovered := false
## 是否为该格启用紧凑槽位提示，由槽位界面显式设置。
var _has_slot_hint: bool = false
## 编号徽章的底板材质；其他格子继续使用贴图边框。
var _collectible_frame: ShaderMaterial
## 当前底板动画的目标亮度，范围为 0.0 到 1.0。
var _collectible_focus_target := 0.0
## 绑定在当前格子的亮度动画；快速移入移出时复用当前亮度作为起点。
var _collectible_focus_tween: Tween

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
			plant_card = card
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
	elif str(record.get("kind", "")) == "icon":
		if record.has("collectible_badge_id"):
			_setup_collectible()
			return
		# 独立图标投影仅包含表现数据，装备等新领域无需进入普通道具目录。
		var backing_texture: Texture2D = record.get("backing") as Texture2D # 装备底图可选，普通格子仍用原底色。
		if backing_texture != null:
			var backing: TextureRect = Art.image(self, "", EQUIPMENT_BACKING_BOUNDS.position, EQUIPMENT_BACKING_BOUNDS.size) # 先画底图，槽框在最上层收边。
			backing.texture = backing_texture
			backing.stretch_mode = TextureRect.STRETCH_SCALE
		var icon_bounds := Rect2(ICON_POSITION, ICON_SIZE) # 普通装备图标沿用背包原生尺寸。
		if record.get("inset_icon", false):
			icon_bounds = EQUIPMENT_BACKING_BOUNDS.grow(-EQUIPMENT_ICON_INSET)
		var icon: TextureRect = Art.image(self, "", icon_bounds.position, icon_bounds.size) # 按格子尺寸绘制原比例图标。
		icon.texture = record.get("icon") as Texture2D
		var badge: String = str(record.get("badge", "")) # 可选状态角标，不等同于道具数量。
		if not badge.is_empty():
			Art.count_badge(self, badge, size - Vector2(4, 5), Color("fff4d6"), 13)
	else:
		# 转职书是共享装配：背景、对应阶数书本和该植物的静态头像。
		var category: String = str(record.get("category", ""))
		if category == "promotion_book":
			_slot.visible = false
			PromotionVisual.draw(self, str(record["id"]), Rect2(BACKING_POSITION, BACKING_SIZE))
		else:
			var backing: String = Data.item_backing(record)
			var uses_scroll: bool = category == "recipe"
			_slot.visible = backing.is_empty() and not uses_scroll
			if not backing.is_empty():
				Art.image(self, backing, BACKING_POSITION, BACKING_SIZE)
			var icon: String = Data.item_icon(record)
			var icon_size: Vector2 = BACKING_SIZE if uses_scroll else ICON_SIZE
			var icon_position: Vector2 = (size - icon_size) * 0.5
			if not icon.is_empty():
				Art.image(self, icon, icon_position, icon_size)
			if category == "recipe":
				var recipe_scale: float = icon_size.y / 58.0
				ItemArt.add_recipe_portrait(self, int(record.get("plant_type", 0)), size * 0.5, 0.42 * recipe_scale)
				var wax: String = ItemArt.recipe_overlay_uri(str(record["id"]))
				if not wax.is_empty():
					Art.image(self, wax, icon_position + Vector2(35, 39) * recipe_scale, Vector2(20, 20) * recipe_scale)
		Art.count_badge(self, "×%d" % int(record.get("qty", 0)), size - Vector2(4, 5))
	# 默认边框常驻内容上层，悬停与选中边框再叠加在默认边框之上。
	Art.slot_frame(self, Vector2.ZERO, size, plants_tab)
	_frame = Art.image(self, "slots/%s_slot_selected_frame.png" % ("plant" if plants_tab else "item"), Vector2.ZERO, size)
	_update_frame()

## 在现有格子尺寸中放置专属底板、徽章及已有状态角标。
func _setup_collectible() -> void:
	_slot.hide()
	_collectible_frame = CollectibleVisual.draw_mark(self, record.collectible_badge_id,
		record.get("icon") as Texture2D, Rect2(2, 6, 82, 84))
	var badge: String = str(record.get("badge", "")) # 装备状态仍沿用背包角标。
	if not badge.is_empty():
		Art.count_badge(self, badge, size - Vector2(4, 5), Color("fff4d6"), 13)
	_prepare_tooltip_theme()
	set_active(_selected)

## 为当前格设置 [param title] 槽位名；空槽和已占用槽共用小提示。
func set_slot_hint(title: String) -> void:
	_has_slot_hint = true
	if _collectible_frame == null:
		tooltip_text = title
		_prepare_tooltip_theme()

## 清除原生提示的外框，让自定义面板绘制自身背景。
func _prepare_tooltip_theme() -> void:
	theme = Theme.new()
	theme.set_stylebox("panel", "TooltipPanel", StyleBoxEmpty.new()) # 浮层背景由共用提示皮肤绘制。

## 为未选中的编号徽章创建简短提示，或用工具栏样式显示 [param for_text] 槽位名。
func _make_custom_tooltip(for_text: String) -> Object:
	if _collectible_frame != null:
		return null if _selected else CollectibleVisual.tooltip(record)
	if not _has_slot_hint:
		return null
	var panel: PanelContainer = HoverTip.panel(6.0) # 槽位名只需一行，缩小留白。
	var caption := Label.new() # 单行槽位名，无须展开装备说明。
	caption.text = for_text
	caption.add_theme_font_size_override("font_size", 15)
	caption.add_theme_color_override("font_color", HoverTip.TEXT_COLOR)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(caption)
	return panel

## 用 [param value] 更新选中边框或编号徽章底板亮度。选中后由详情区提供信息。
func set_active(value: bool) -> void:
	_selected = value
	if _collectible_frame != null:
		tooltip_text = "" if _selected else str(record.get("title", ""))
	_update_frame()

## 同步当前边框状态，选中亮度优先于悬停。
func _update_frame() -> void:
	if _collectible_frame != null:
		_update_collectible_focus()
		return
	if not is_instance_valid(_frame):
		return
	_frame.visible = not record.is_empty() and (_selected or _hovered)
	if _frame.visible:
		var prefix := "plant" if _plant_slot else "item"
		var state := "selected" if _selected else "hover"
		_frame.texture = Art.texture("slots/%s_slot_%s_frame.png" % [prefix, state])

## 让编号徽章的金边平滑亮起或回落；入树前直接应用起始亮度。
func _update_collectible_focus() -> void:
	var focus: float = 1.0 if _selected else (0.72 if _hovered else 0.0) # 选中时保持最亮。
	if is_inside_tree() and focus == _collectible_focus_target:
		return
	if _collectible_focus_tween != null:
		_collectible_focus_tween.kill()
	var duration: float = 0.20 if focus > _collectible_focus_target else 0.30 # 亮起较快，回落稍缓，单位为秒。
	_collectible_focus_target = focus
	if not is_inside_tree():
		_collectible_frame.set_shader_parameter("focus_strength", focus)
		return
	_collectible_focus_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_collectible_focus_tween.tween_property(_collectible_frame, "shader_parameter/focus_strength", focus, duration)

func _on_mouse_entered() -> void:
	_hovered = true
	_update_frame()

func _on_mouse_exited() -> void:
	_hovered = false
	_update_frame()

## 在触屏上让 [param hit_area] 接收轻触，移动超过阈值时由所在滚动区取消点击。
## 仅用于滚动列表中已完成布置的格子，每个格子调用一次。
func enable_scrollable_selection(hit_area: Control) -> void:
	if not DisplayServer.is_touchscreen_available():
		return
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if record.is_empty():
		return
	var button := TextureButton.new() # 透明点击区交给原生按钮区分轻触与滚动。
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_PASS
	button.mouse_default_cursor_shape = mouse_default_cursor_shape
	button.tooltip_text = tooltip_text
	button.mouse_entered.connect(_on_mouse_entered)
	button.mouse_exited.connect(_on_mouse_exited)
	button.pressed.connect(func() -> void: chosen.emit(record))
	hit_area.add_child(button)
	button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

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
