## 复用背包筛选框与羊皮纸的下拉控件；仅维护选项和显示，不负责业务过滤。
extends MenuButton
class_name InventoryFilterButton

## 用户选择 [param index] 后通知调用方。
signal option_selected(index: int)
## 共享背包素材与九宫格样式。
const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")
## 当前选项文本；索引由调用方解释。
var _options: PackedStringArray = []

## 应用已有素材，弹出列表也使用同一套界面皮肤。
func _ready() -> void:
	flat = false
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_theme_font_size_override("font_size", 22)
	for state: String in ["normal", "hover", "pressed", "focus"]: # 覆盖默认系统深色按钮。
		add_theme_stylebox_override(state, Art.texture_style("controls/filter_field.png", 12))
	for color: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]: # 浅底深字。
		add_theme_color_override(color, Color("382719"))
	var popup_theme := Theme.new() # 弹出菜单独立设皮肤，不影响其他窗口的原生主题。
	popup_theme.set_stylebox("panel", "PopupMenu", Art.texture_style("panels/parchment_ninepatch.png", 20))
	popup_theme.set_stylebox("hover", "PopupMenu", Art.texture_style("controls/filter_field.png", 10))
	popup_theme.set_color("font_color", "PopupMenu", Color("382719"))
	popup_theme.set_color("font_hover_color", "PopupMenu", Color("382719"))
	popup_theme.set_font_size("font_size", "PopupMenu", 22)
	popup_theme.set_constant("v_separation", "PopupMenu", 12)
	get_popup().theme = popup_theme
	get_popup().id_pressed.connect(_choose)
	get_popup().about_to_popup.connect(_fit_popup)

## 弹出列表至少与筛选框同宽，按实际缩放后的显示尺寸计算。
func _fit_popup() -> void:
	get_popup().min_size.x = ceili(get_global_rect().size.x)

## 用 [param options] 填充菜单，首次默认第一项；不发出业务信号。
func configure(options: PackedStringArray) -> void:
	_options = options.duplicate()
	get_popup().clear()
	for index: int in range(_options.size()): # 普通菜单项避免系统单选圆点，与背包素材一致。
		get_popup().add_item(_options[index], index)
	text = _options[0] + "  ▾" if not _options.is_empty() else ""
	disabled = _options.is_empty()

## 更新 [param index] 的显示并通知外层；菜单只持有界面状态。
func _choose(index: int) -> void:
	if index < 0 or index >= _options.size():
		return
	text = _options[index] + "  ▾"
	option_selected.emit(index)
