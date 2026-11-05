## 研究室选择网格与工作槽。统一复用背包格的美术、数量徽标和卡片展示。
extends RefCounted

## 背包格和已有边框素材。
const Tile = preload("res://scripts/adventure/ui/inventory_tile.gd")
## 面板文字与高亮边框的共享绘制工具。
const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")
## 槽位类型和当前选取状态。
const Picker = preload("res://scripts/adventure/ui/research_slot_picker.gd")
## 道具目录中的图标路径，不依赖玩家是否持有该道具。
const ItemArt = preload("res://scripts/adventure/ui/inventory_item_art.gd")
## 复用现有灰显效果，只用于空槽图标。
const PLACEHOLDER_SHADER = preload("res://shaders/adventure/locked_stage.gdshader")
## 强化空道具槽显示的图标；占位图不代表已填入道具。
const EMPTY_ITEM_HINTS := {Picker.Slot.POT: "seedling_pot", Picker.Slot.FERTILIZER: "fertilizer_lv1"}
## 根据研究室面板边界铺设格子，避免预留已删除标题的高度。
const Layout = preload("res://scripts/adventure/ui/research_panel_skin.gd")
## 合成材料槽和强化工作槽使用同一等比缩放。
const COMPACT_SLOT_SCALE: float = 0.70
## 四列背包格，每列保留间距和滚动条空间。
const COLUMNS: int = 4
## 选择区首屏行数及格间距，更多条目可垂直滚动。
const VISIBLE_ROWS: int = 6
## 相邻背包格之间的设计像素间距。
const GRID_GAP: int = 8

## 在 [param parent] 内绘制 [param rows] 的选择网格，点击后向 [param owner] 提交行索引。
## [param picker] 指定格子类型与当前高亮。
static func choices(owner: Control, parent: Control, rows: Array[Dictionary], picker: Picker) -> void:
	var scroll := ScrollContainer.new() # 道具较多时只滚动选择区，不影响工作槽。
	var bounds: Rect2 = Layout.SELECTION_REGION.grow(-18.0) # 网格铺到面板上下内沿。
	scroll.position = bounds.position
	scroll.size = bounds.size
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var grid := GridContainer.new() # 在不足一页时也展示空背包格。
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", GRID_GAP)
	grid.add_theme_constant_override("v_separation", GRID_GAP)
	scroll.add_child(grid)
	var gutter: float = scroll.get_v_scroll_bar().get_combined_minimum_size().x # 滚动条出现时第四列也能完整显示。
	var cell_size := Vector2(floorf((bounds.size.x - gutter - (COLUMNS - 1) * GRID_GAP) / COLUMNS),
		floorf((bounds.size.y - (VISIBLE_ROWS - 1) * GRID_GAP) / VISIBLE_ROWS)) # 每格使用相同宽高，贴图在格内等比适配。
	var plants: bool = Picker.is_plant_slot(picker.active_slot) # 空格采用当前槽位的类别样式。
	var selected: String = picker.key_for(picker.active_slot, picker.active_index) # 按 ID 或 UID 高亮当前槽内容。
	for index: int in range(maxi(rows.size(), COLUMNS * VISIBLE_ROWS)):
		var record: Dictionary = rows[index] if index < rows.size() else {} # 超出库存的格子作为空位展示。
		var cell := Control.new() # 容器尺寸独立于背包格内部等比缩放。
		cell.custom_minimum_size = cell_size
		grid.add_child(cell)
		var key: String = str(record.get("uid", record.get("id", ""))) # 区分同物种的多张独立卡。
		var tile: Control = _tile(cell, record, Rect2(Vector2.ZERO, cell_size), plants, not key.is_empty() and key == selected) # 格子复用背包点击信号。
		if record.is_empty():
			continue
		tile.tooltip_text = str(record.get("title", ""))
		var pick := func(_record: Dictionary) -> void: # 格子离树后忽略排队中的旧点击。
			if tile.is_inside_tree():
				owner.call("choose_entry", index)
		# 等背包格处理完当前输入，再移除旧格子并刷新界面。
		tile.connect("chosen", pick, Object.CONNECT_DEFERRED)

## 在工作面板中按 [param columns] 列、[param rows] 行划分空间，返回 [param index] 的槽位区域。
## [param scale_factor] 按原格中心等比缩放槽位区域，1 表示原始大小。
static func work_cell(columns: int, rows: int, index: int, scale_factor: float = 1.0) -> Rect2:
	var area: Rect2 = Layout.WORK_REGION.grow(-24.0) # 留出羊皮纸面板边框。
	var gap: float = 18.0 # 槽位之间的设计间距。
	var cell := (area.size - Vector2(columns - 1, rows - 1) * gap) / Vector2(columns, rows) # 均分可用尺寸。
	var address := Vector2(index % columns, floori(float(index) / columns)) # 按行从左到右排列。
	var position: Vector2 = area.position + address * (cell + Vector2.ONE * gap) # 未缩放的槽位左上角。
	var dimensions: Vector2 = cell * scale_factor # 保持原格的宽高比。
	return Rect2(position + (cell - dimensions) * 0.5, dimensions)

## 在 [param bounds] 绘制 [param picker] 的 [param slot]、[param index]，从 [param inventory] 读取内容。
## [param mode] 决定可用性，点击和清空交给 [param owner]，控件挂到 [param parent]。
## [param required_quantity] 大于零时，工作槽数量代表本次所需数量。
static func work(owner: Control, parent: Control, mode: String, picker: Picker,
		inventory: AdventureInventoryService, slot: Picker.Slot, bounds: Rect2, index: int = 0,
		required_quantity: int = 0) -> void:
	var button := TextureButton.new() # 透明点击区域，图案与边框由共享格子绘制。
	button.ignore_texture_size = true
	button.focus_mode = Control.FOCUS_NONE
	button.disabled = inventory == null or not picker.can_focus(mode, slot, index)
	button.mouse_default_cursor_shape = Control.CURSOR_ARROW if button.disabled else Control.CURSOR_POINTING_HAND
	parent.add_child(button)
	button.position = bounds.position
	button.size = bounds.size
	var record: Dictionary = picker.slot_row(inventory, slot, index) # 仅用于展示当前填入的资产。
	if required_quantity > 0 and not record.is_empty():
		record["qty"] = required_quantity
	var active: bool = picker.active_slot == slot and picker.active_index == index and not button.disabled # 当前接受选择的工作槽。
	var plants: bool = Picker.is_plant_slot(slot) # 植物槽与道具槽分别沿用背包边框。
	var tile: Control = _tile(button, record, Rect2(Vector2.ZERO, bounds.size), plants, active) # 背包格只显示，由外层捕获点击。
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if record.is_empty():
		var hint_item: String = EMPTY_ITEM_HINTS.get(slot, "") # 花盆槽和肥料槽按道具 ID 取图。
		var hint_uri: String = ItemArt.promotion_tier_uri(1) if slot == Picker.Slot.PROMOTION_BOOK else ItemArt.icon_uri(hint_item) # 空转职书槽使用灰显的一转书本。
		if not hint_uri.is_empty():
			var hint: TextureRect = Art.image(tile, hint_uri, Tile.ICON_POSITION, Tile.ICON_SIZE) # 跟随背包格等比缩放。
			var gray := ShaderMaterial.new() # 灰度材质只作用于占位图，不影响填入的道具。
			gray.shader = PLACEHOLDER_SHADER
			hint.material = gray
			hint.self_modulate.a = 0.56
		if active:
			Art.image(button, "slots/%s_slot_selected_frame.png" % ("plant" if plants else "item"), tile.position, tile.size * tile.scale)
		if required_quantity > 0:
			Art.count_badge(tile, "×%d" % required_quantity, tile.size - Vector2(4, 5))
	button.pressed.connect(Callable(owner, "focus_slot").bind(slot, index))
	button.tooltip_text = Picker.slot_title(slot, index)
	if not record.is_empty():
		button.tooltip_text += "\n" + str(record.get("title", ""))
	if required_quantity > 0:
		button.tooltip_text += "\n本次需要 %d 个" % required_quantity
	if not button.disabled:
		button.tooltip_text += "\n点击选择" if record.is_empty() else "\n点击替换"
	if not button.disabled and not record.is_empty() and slot != Picker.Slot.MAIN_CARD:
		button.tooltip_text += "，右键清空"
		button.gui_input.connect(_clear_on_right_click.bind(button, Callable(owner, "clear_slot").bind(slot, index)))

## [param event] 为工作槽输入，右键按下时由 [param button] 消费并调用 [param clear]。
static func _clear_on_right_click(event: InputEvent, button: Control, clear: Callable) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		button.accept_event()
		clear.call()

## 在 [param parent] 中创建 [param record] 的背包格，等比适配 [param bounds]。
## [param plants] 决定空格样式，[param active] 决定选中边框。
static func _tile(parent: Control, record: Dictionary, bounds: Rect2, plants: bool, active: bool) -> Control:
	var tile: Control = Tile.new() # 研究室选择不允许拖拽改变背包顺序。
	parent.add_child(tile)
	tile.setup(record, -1, false, plants, active)
	var factor: float = minf(bounds.size.x / tile.size.x, bounds.size.y / tile.size.y) # 卡片、卷轴和道具统一等比缩放。
	tile.scale = Vector2.ONE * factor
	tile.position = bounds.position + (bounds.size - tile.size * factor) * 0.5
	return tile
