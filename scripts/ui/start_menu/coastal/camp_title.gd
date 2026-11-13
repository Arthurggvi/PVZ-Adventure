extends Control
## 远征营地的简洁标题，与角色和地图构成主菜单中心，不承担输入或业务状态。

## 标题尺寸以原画坐标定义，随菜单统一缩放。
const TITLE_SIZE := Vector2(250, 126)

## [param font] 为游戏中文字体；标题在加入场景前创建，不截获地图或建筑的输入。
func configure(font: Font) -> void:
	size = TITLE_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var series := Label.new() # 小字号说明作品身份，主标题保留足够留白。
	series.text = "植物大战僵尸"
	series.position = Vector2(0, 0)
	series.size = Vector2(250, 28)
	_style(series, font, 20, Color("eee1b8"), 4)
	add_child(series)
	var title := Label.new() # 大字形成视觉锚点，不再向广场增加说明段落。
	title.text = "冒险"
	title.position = Vector2(0, 19)
	title.size = Vector2(250, 101)
	_style(title, font, 79, Color("ffe8a5"), 9)
	title.add_theme_color_override("font_shadow_color", Color("302c1e"))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 5)
	title.add_theme_constant_override("shadow_outline_size", 4)
	add_child(title)

## [param label] 接收 [param font]、[param pixels]、[param color] 和 [param outline] 定义的统一描边文字。
func _style(label: Label, font: Font, pixels: int, color: Color, outline: int) -> void:
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", pixels)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color("39311e"))
	label.add_theme_constant_override("outline_size", outline)
