## 游戏滚动区复用 Godot 的滚轮、触摸拖动、惯性和滚动条。
extends ScrollContainer

## 普通列表预留的纵向滚动条宽度，单位为界面设计像素。
const BAR_WIDTH: int = 10
## 轻触时允许的位移，单位为滚动区局部像素。
const TOUCH_DEADZONE: int = 10

## 保持内容宽度稳定，只有内容超过视口时才显示滚动条。
func _init() -> void:
	horizontal_scroll_mode = SCROLL_MODE_DISABLED
	vertical_scroll_mode = SCROLL_MODE_RESERVE
	mouse_filter = Control.MOUSE_FILTER_STOP
	scroll_deadzone = TOUCH_DEADZONE
	pre_sort_children.connect(_measure_content)
	style_vertical_bar(Color("5f4432"), Color("c99a61"), Color("f4ce85"))

## 在 [param width] 个设计像素内绘制 [param track]、[param thumb] 和悬停或拖动时的 [param active_thumb]。
func style_vertical_bar(track: Color, thumb: Color, active_thumb: Color, width: int = BAR_WIDTH) -> void:
	var bar: VScrollBar = get_v_scroll_bar() # 复用原生滑块，主题尺寸参与内容排版。
	bar.add_theme_stylebox_override("scroll", _bar_style(track, width))
	bar.add_theme_stylebox_override("grabber", _bar_style(thumb, width))
	var highlighted: StyleBoxFlat = _bar_style(active_thumb, width) # 悬停和拖动共用一套高亮。
	bar.add_theme_stylebox_override("grabber_highlight", highlighted)
	bar.add_theme_stylebox_override("grabber_pressed", highlighted)

## 按 [param fill] 和 [param width] 创建样式，最小宽度直接由轨道样式提供。
static func _bar_style(fill: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new() # 纯色圆角跟随各窗口缩放，无需加载贴图。
	style.bg_color = fill
	style.set_corner_radius_all(mini(8, floori(width * 0.5)))
	style.set_content_margin_all(width * 0.5)
	return style

## Godot 4.7.2 排版时读取上次测量的内容尺寸，直接重测可覆盖清空目录时留下的旧范围。
func _measure_content() -> void:
	get_minimum_size()
