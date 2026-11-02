## 冒险界面的共享中文字体和轻量控件构造，不包含游戏状态。
extends RefCounted

## 使用项目中文字体，并保留操作系统字体回退。
static func make_theme() -> Theme:
	var theme := Theme.new() # 冒险界面专用主题。
	var font := load("res://assets/fonts/方正少儿_GBK.ttf").duplicate() as FontFile # 不修改原字体资源。
	var fallback := SystemFont.new() # 缺字时使用系统中文字体。
	fallback.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	font.fallbacks = [fallback]
	theme.default_font = font
	theme.default_font_size = 32
	theme.set_stylebox("normal", "Button", panel_style(Color("283d38")))
	theme.set_stylebox("hover", "Button", panel_style(Color("426052")))
	theme.set_stylebox("pressed", "Button", panel_style(Color("192d28")))
	return theme

## [param color] 为面板底色；返回独立圆角样式。
static func panel_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new() # 每个样式独立可调，避免共享修改。
	style.bg_color = color
	style.border_color = Color("c6ae70")
	style.set_border_width_all(2)
	style.set_corner_radius_all(16)
	style.content_margin_left = 18
	style.content_margin_right = 18
	return style

## 在 [param parent] 中创建 [param rect] 范围的文字 [param text]；[param font_size] 为设计画布字号。
static func label(parent: Node, text: String, rect: Rect2, font_size: int = 32) -> Label:
	var node := Label.new() # 独立文字层，永不烘焙到图片。
	node.text = text
	node.position = rect.position
	node.size = rect.size
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_outline_color", Color("18251f"))
	node.add_theme_constant_override("outline_size", 5)
	node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

## 在 [param parent] 的 [param rect] 内创建 [param text] 按钮，点击执行 [param callback]。
static func button(parent: Node, text: String, rect: Rect2, callback: Callable) -> Button:
	var node := Button.new() # 普通文字按钮，样式来自冒险主题。
	node.text = text
	node.position = rect.position
	node.size = rect.size
	node.pressed.connect(callback)
	parent.add_child(node)
	return node
