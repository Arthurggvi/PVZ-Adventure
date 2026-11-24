## One scalable, purely visual research shell built from the existing inventory skin.
## No baked labels, data or mode-specific pictures in the shared background.
extends RefCounted
const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")
const Preview = preload("res://scripts/adventure/ui/research_ui_meta.gd")
const DESIGN := Vector2(1920.0, 1080.0)
const FRAME := Rect2(55, 74, 1810, 948)
## 三个内容面板从页首木条下沿开始，底部与操作栏留出间距。
const CONTENT_TOP: float = 228.0
## 页首按钮移走后可用于内容的高度。
const CONTENT_HEIGHT: float = 873.0 - CONTENT_TOP
## 左侧候选格的面板边界。
const SELECTION_REGION := Rect2(112, CONTENT_TOP, 414, CONTENT_HEIGHT)
## 工作槽布局从中间面板边界计算。
const WORK_REGION := Rect2(544, CONTENT_TOP, 710, CONTENT_HEIGHT)
## 右侧信息布局的面板边界。
const INFO_REGION := Rect2(1270, CONTENT_TOP, 530, CONTENT_HEIGHT)
## 正常操作和规则页返回共用底栏按钮位置。
const ACTION_REGION := Rect2(1490, 899, 268, 82)
const CONTENT_REGIONS := [
	SELECTION_REGION,
	WORK_REGION,
	INFO_REGION
]

static func build(owner: Control, with_background: bool = false) -> Dictionary:
	var shade := ColorRect.new()
	shade.color = Color(0.06, 0.06, 0.04, 0.10 if with_background else 0.42)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	owner.add_child(shade)
	var canvas := Control.new()
	canvas.name = "ResearchCanvas"
	canvas.size = DESIGN
	canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	owner.add_child(canvas)
	Art.panel(canvas, "panels/outer_frame_ninepatch.png", FRAME.position, FRAME.size, 42)
	Art.panel(canvas, "panels/wood_ninepatch.png", Vector2(100, 205), Vector2(1718, 683), 35)
	Art.panel(canvas, "panels/wood_ninepatch.png", Vector2(100, 110), Vector2(1718, 105), 35)
	Art.panel(canvas, "panels/wood_ninepatch.png", Vector2(110, 887), Vector2(1700, 106), 30)
	for region: Rect2 in CONTENT_REGIONS:
		Art.panel(canvas, "panels/parchment_ninepatch.png", region.position, region.size, 30)
	var wallet := HBoxContainer.new() # 金币和详情入口共同靠右，余额位数变化时保留相同间距。
	wallet.position = Vector2(1090, 126)
	wallet.size = Vector2(626, 74)
	wallet.alignment = BoxContainer.ALIGNMENT_END
	wallet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wallet.add_theme_constant_override("separation", 14)
	canvas.add_child(wallet)
	var history_button: Button = _detail_button(wallet, "ResearchHistoryButton", "历史记录",
		Vector2(154, 46), 23, Callable(owner, "toggle_history")) # 仅强化页展示这个入口。
	var rules_button: Button = _detail_button(wallet, "ResearchRulesButton", "?",
		Vector2(46, 46), 28, Callable(owner, "toggle_rules")) # 仅强化和转职显示规则入口。
	var coin: Label = Art.label(wallet, "$0", Vector2.ZERO, Vector2.ZERO, 26, Color("fae6b8")) # 金额的实际文字宽度决定问号的位置。
	coin.clip_text = false
	coin.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var close := Art.button(canvas, "controls/close", Vector2(1731, 126),
		Vector2(74, 74), Callable(owner, "request_close"))
	close.name = "ResearchClose"
	var tabs: Dictionary = {}
	var labels := ["合成", "强化", "转职"]
	var icons := ["icons/category_recipes.png", "overlays/star_filled.png", "icons/category_plants.png"]
	for i in Preview.MODES.size():
		var key: String = Preview.MODES[i]
		var btn := Art.button(canvas, "tabs/tab", Vector2(116 + i * 210, 126.5),
			Vector2(196, 72), Callable(owner, "choose_mode").bind(key)) # 按原比例缩放，横排在页首左侧。
		btn.name = "ResearchTab_" + key
		Art.image(btn, icons[i], Vector2(18, 12), Vector2(48, 48))
		Art.label(btn, labels[i], Vector2(74, 14), Vector2(98, 47), 28)
		tabs[key] = btn
	var content := Control.new()
	content.name = "ResearchModeContent"
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.size = DESIGN
	canvas.add_child(content)
	var action := Art.button(canvas, "buttons/action_confirm", ACTION_REGION.position,
		ACTION_REGION.size, Callable(owner, "perform_action"))
	action.name = "ResearchAction"
	action.texture_disabled = Art.texture("buttons/action_confirm_disabled.png")
	action.disabled = true
	var action_text := Art.label(action, "合成", Vector2(48, 10), Vector2(170, 65), 35)
	action_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return {"canvas": canvas, "tabs": tabs, "coin": coin, "content": content,
		"action": action, "action_text": action_text, "rules": rules_button, "history": history_button}

## 在 [param parent] 创建金币旁的详情入口，使用 [param node_name] 和 [param caption]。
## [param dimensions] 指定徽记大小，[param point_size] 指定字号，[param toggle] 处理开合。
static func _detail_button(parent: Control, node_name: String, caption: String,
		dimensions: Vector2, point_size: int, toggle: Callable) -> Button:
	var button := Button.new() # 文案与点击区为同一控件，支持鼠标、触屏和焦点导航。
	button.name = node_name
	button.text = caption
	button.custom_minimum_size = dimensions
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.toggle_mode = true
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", point_size)
	button.add_theme_color_override("font_color", Color("fff1cc"))
	button.add_theme_color_override("font_hover_color", Color("fffae4"))
	button.add_theme_color_override("font_pressed_color", Color("fff1cc"))
	button.add_theme_color_override("font_focus_color", Color("fff1cc"))
	button.add_theme_color_override("font_disabled_color", Color("ab9878"))
	button.add_theme_stylebox_override("normal", _detail_badge(Color("3e3022"), Color("d2a369")))
	button.add_theme_stylebox_override("hover", _detail_badge(Color("625037"), Color("f8db99")))
	button.add_theme_stylebox_override("disabled", _detail_badge(Color("3e3022"), Color("826848")))
	var active: StyleBoxFlat = _detail_badge(Color("2d4c39"), Color("f2d58e")) # 阅读中以深绿色区分开启状态。
	button.add_theme_stylebox_override("pressed", active)
	button.add_theme_stylebox_override("hover_pressed", active)
	button.add_theme_stylebox_override("focus", _detail_badge(Color.TRANSPARENT, Color("ffe0a0")))
	button.hide()
	button.pressed.connect(toggle)
	parent.add_child(button)
	return button

## 返回详情入口的胶囊样式，[param fill] 与 [param edge] 分别用于面色与描边。
static func _detail_badge(fill: Color, edge: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new() # 深色铜边徽记与木条拉开对比。
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(2)
	style.set_corner_radius_all(23)
	return style
