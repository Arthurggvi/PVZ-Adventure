## 仅在上次加载未结束或发生失败时显示的海滨诊断入口。
## 复用主菜单暖黑与旧黄铜视觉，不增加全屏弹窗或调试工作台。
extends Button

## 与资源加载器共享唯一断点报告，玩家复制后只标记已确认。
const Checkpoint = preload("res://scripts/ui/transitions/resource_load_checkpoint.gd")

## 初始化主菜单中不与存档卡片、地图入口重叠的低干扰按钮。
func _ready() -> void:
	name = "LastLoadingReport"
	text = "复制上次加载记录"
	tooltip_text = "上次部分资源未能确认加载完成，可复制信息发送给作者"
	accessibility_name = "复制上一次加载诊断信息"
	position = Vector2(24, 870)
	size = Vector2(252, 46)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_theme_font_size_override("font_size", 18)
	add_theme_color_override("font_color", Color("ead9b6"))
	add_theme_color_override("font_hover_color", Color("fff0d1"))
	add_theme_color_override("font_pressed_color", Color("e7cda0"))
	add_theme_color_override("font_focus_color", Color("fff5dc"))
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := StyleBoxFlat.new() # 单层暖黑浅金边框，匹配档案按钮而不争夺主菜单视觉焦点。
		style.bg_color = Color(0.10, 0.09, 0.07, 0.78)
		style.border_color = Color(0.64, 0.51, 0.32, 0.66)
		style.set_border_width_all(1)
		style.set_corner_radius_all(8)
		if state == "hover":
			style.bg_color = Color(0.22, 0.17, 0.105, 0.90)
		if state == "pressed":
			style.bg_color = Color(0.08, 0.07, 0.05, 0.93)
		if state == "focus":
			style.border_color = Color("ecc486")
		add_theme_stylebox_override(state, style)
	pressed.connect(_copy_report)

## 玩家只需点击一次；不会显示或复制任何玩家存档内容。
func _copy_report() -> void:
	DisplayServer.clipboard_set(Checkpoint.report_text())
	Checkpoint.acknowledge()
	text = "已复制，可发送给作者"
	disabled = true
