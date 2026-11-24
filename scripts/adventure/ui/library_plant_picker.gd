## 定向转换的植物目录。只在打开时装配可见头像，由图书馆窗口校验所选物种。
extends ColorRect

## [param plant_type] 为所选植物编号，零表示关闭目录。
signal finished(plant_type: int)

## 羊皮纸边框、关闭按钮和文字均沿用图书馆素材。
const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")
## 触屏上可从植物卡片开始滑动名录。
const ContentScroll = preload("res://scripts/ui/content_scroll.gd")
## 中文植物名与图鉴一致。
const Names = preload("res://scripts/adventure/ui/inventory_data.gd")
## 使用图鉴按实际可见范围居中的静态头像。
const Portrait = preload("res://scripts/adventure/ui/almanac_preview.gd")
## 按可见范围准备书本和植物头像。
const VisualQueue = preload("res://scripts/adventure/ui/prepared_visual_queue.gd")
## 设计尺寸，目录在图书馆内部等比缩放。
const SHEET_SIZE := Vector2(780, 536)
## 四列植物格的设计尺寸。
const TILE_SIZE := Vector2(164, 94)

## 显示 [param plants] 中的植物，聚焦 [param current] 或第一项，并逐帧准备可见头像。
func open(plants: Array[int], current: int) -> void:
	color = Color(0.13, 0.085, 0.045, 0.59)
	var visuals := VisualQueue.new() # 目录头像独立准备，关闭后释放未显示的请求。
	add_child(visuals)
	var sheet := Control.new() # 独立纸页截获目录内空白处的点击。
	sheet.position = (size - SHEET_SIZE) * 0.5
	sheet.size = SHEET_SIZE
	add_child(sheet)
	Art.panel(sheet, "panels/parchment_ninepatch.png", Vector2.ZERO, SHEET_SIZE, 28)
	Art.label(sheet, "选择目标植物", Vector2(32, 20), Vector2(500, 52), 29)
	var close: TextureButton = Art.button(sheet, "controls/close", Vector2(702, 22), Vector2(46, 46),
		func(): finished.emit(0)) # 与主窗口同样的关闭操作。
	close.accessibility_name = "关闭植物选择"
	var scroll := ContentScroll.new() # 名录增长时保持固定窗口高度。
	scroll.position = Vector2(32, 88)
	scroll.size = Vector2(716, 412)
	scroll.follow_focus = true
	sheet.add_child(scroll)
	var grid := GridContainer.new() # 固定列数让名称和头像在视觉上对齐。
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	var initial_focus: Control = close # 无可选物种时仍可键盘退出。
	for plant: int in plants: # 编号顺序来自书目，头像仅进入可见队列。
		var tile: Button = field_button(grid, Names.plant_name(plant), Rect2(Vector2.ZERO, TILE_SIZE),
			plant == current, Vector2(8, 54)) # 标题留在头像下方，当前目标使用绿底。
		tile.custom_minimum_size = TILE_SIZE
		tile.mouse_filter = Control.MOUSE_FILTER_PASS # 滑动由目录处理，轻触仍选择当前植物。
		tile.pressed.connect(func(): finished.emit(plant))
		queue_portrait(visuals, tile, plant, Rect2(50, 7, 64, 48))
		if plant == current or initial_focus == close:
			initial_focus = tile
	if plants.is_empty():
		Art.label(sheet, "这个等阶暂无可选植物", Vector2(34, 110), Vector2(600, 45), 23, Color("806442"))
	initial_focus.grab_focus()

## 左键点击纸页之外时收起目录并拦截 [param event]。
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		accept_event()
		finished.emit(0)

## 通过 [param queue] 为 [param parent] 的 [param bounds] 请求 [param plant] 的图鉴头像。
static func queue_portrait(queue: VisualQueue, parent: Control, plant: int, bounds: Rect2) -> void:
	var reference: ResourceCardReference = ResourceCardReference.create(ResourceCardReference.CardType.Plant, plant) # 仅请求这个物种的卡面。
	queue.enqueue(parent, AllCards.get_resource_paths([reference]), Portrait.draw_thumbnail.bind(parent, "plant", plant, bounds))

## 为 [param parent] 创建 [param caption] 输入控件。[param bounds] 使用设计坐标。
## [param active] 使用绿色选中态，[param padding] 的两个分量是文字左、上留白。
static func field_button(parent: Node, caption: String, bounds: Rect2, active: bool = false,
		padding: Vector2 = Vector2(14, 0)) -> Button:
	var button := Button.new() # 原生焦点、键盘激活和禁用反馈。
	button.text = caption
	button.clip_text = true
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 22)
	var ink := Color("394820") if active else Color("50361f") # 草绿色选中态与纸面使用不同墨色。
	for state: String in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]: # 鼠标和键盘状态均保留高对比度。
		button.add_theme_color_override(state, ink)
	button.add_theme_color_override("font_disabled_color", Color("8b7350"))
	var fills: Dictionary[String, Color] = { # 同一组暖纸色服务选项与工作台输入区。
		"normal": Color("dce4b6") if active else Color("efddb3"),
		"hover": Color("e8edc5") if active else Color("faebc7"),
		"pressed": Color("dce4b6") if active else Color("e0c599"),
		"disabled": Color("e3cea2"),
	}
	for state: String in fills: # 选中态始终保留草绿色边线。
		var edge := Color("748341") if active else Color("b08a57") # 暖铜色复用木框色相。
		var style: StyleBoxFlat = inset(fills[state], edge) # 圆角浅框用于次级交互。
		style.content_margin_left = padding.x
		style.content_margin_right = 12.0
		style.content_margin_top = padding.y
		style.content_margin_bottom = 0.0
		button.add_theme_stylebox_override(state, style)
	var focus: StyleBoxFlat = inset(Color.TRANSPARENT, Color("795429")) # 焦点描边不遮盖图标和选中底色。
	focus.draw_center = false
	button.add_theme_stylebox_override("focus", focus)
	parent.add_child(button)
	button.position = bounds.position
	button.size = bounds.size
	return button

## 返回以 [param fill] 填充并以 [param edge] 描边的纸面嵌框，圆角半径为 [param radius] 设计像素。
static func inset(fill: Color, edge: Color, radius: int = 11) -> StyleBoxFlat:
	var style := StyleBoxFlat.new() # 控件独立持有样式，可按需要设置内容边距。
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	return style
