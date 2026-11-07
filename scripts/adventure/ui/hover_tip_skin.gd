## 工具栏与角色面板共用的悬停提示样式。
extends RefCounted

## 深底上的浅金正文颜色。
const TEXT_COLOR := Color("f5e1b6")

## 创建工具栏样式的提示面板；[param padding] 为文字留白。
static func panel(padding: float = 2.0) -> PanelContainer:
	var tip := PanelContainer.new() # 悬停提示不接管鼠标。
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new() # 沿用工具栏原来的深棕底与细金边。
	style.bg_color = Color("291c12ed")
	style.border_color = Color("b99459")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	for side: int in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]: # 默认维持工具栏的边框内距。
		style.set_content_margin(side, padding)
	tip.add_theme_stylebox_override("panel", style)
	return tip
