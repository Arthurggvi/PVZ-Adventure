## Boss 档案的阅读样式；正文、数值与纸面卡片共用配色和字体，标题沿用图鉴字体。
extends RefCounted

## 随项目分发的宋体用于长段落，避免装饰字体影响阅读。
const BODY_FONT = preload("res://assets/fonts/SIMSUN.TTC")
## 深色正文墨色。
const INK := Color("382b22")
## 次级标签墨色。
const MUTED := Color("6b533c")
## 黑将军的军旗红，也用于生命数值。
const GENERAL_ACCENT := Color("823b28")
## 白爵士使用冷蓝色强调音乐和复生主题。
const DUKE_ACCENT := Color("355c67")

## 返回以 [param fill] 填充、[param border] 描边的纸面卡片样式。
static func card_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new() # 低对比细边减少木框和按钮的重复视觉噪声。
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style

## 在 [param parent] 的 [param rect] 添加不拦截输入的卡片；[param fill] 为底色。
static func card(parent: Control, rect: Rect2, fill: Color = Color(1, 0.96, 0.85, 0.55)) -> Panel:
	var panel := Panel.new() # 内容由调用方按卡片内边距定位。
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", card_style(fill, Color(0.45, 0.31, 0.17, 0.24)))
	parent.add_child(panel)
	return panel

## 在 [param parent] 的 [param rect] 添加 [param caption]；[param font_size]、[param ink] 控制层级。
## [param body] 选择阅读字体；否则继承图鉴的装饰字体。长文本自动换行。
static func label(parent: Control, caption: String, rect: Rect2, font_size: int, ink: Color = INK, body: bool = true) -> Label:
	var text := Label.new() # 不使用文字阴影，保证缩放后笔画清楚。
	text.text = caption
	text.position = rect.position
	text.size = rect.size
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_theme_font_size_override("font_size", font_size)
	text.add_theme_color_override("font_color", ink)
	text.add_theme_constant_override("line_spacing", 5)
	if body:
		text.add_theme_font_override("font", BODY_FONT)
	parent.add_child(text)
	return text

## 在 [param parent] 的 [param rect] 绘制 [param caption] 数值，使用 [param font_size] 和 [param ink]。
## 数字使用引擎自带字体，避免宋体数字笔画太细；单位由调用方另行排版。
static func number(parent: Control, caption: String, rect: Rect2, font_size: int, ink: Color = INK) -> Label:
	var text: Label = label(parent, caption, rect, font_size, ink) # 保持数字与说明相同的定位约定。
	text.add_theme_font_override("font", ThemeDB.fallback_font)
	return text
