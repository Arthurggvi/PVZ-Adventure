## 图鉴共用的选择按钮和动态节点清理；不保存业务状态或资源缓存。
extends RefCounted

## 图鉴与背包共用的皮肤入口。
const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")

## 在 [param parent] 中按 [param asset] 创建按钮，显示 [param title] 并连接 [param action]；返回可继续定位的按钮。
static func selection_button(parent: Control, title: String, asset: String, action: Callable) -> Button:
	var button: Button = Button.new() # 鼠标与键盘共用一个可切换的选择目标。
	button.text = title
	button.toggle_mode = true
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 24)
	button.add_theme_color_override("font_color", Color("fff0ce"))
	button.add_theme_color_override("font_hover_color", Color("fff6de"))
	button.add_theme_color_override("font_pressed_color", Color("fff6de"))
	button.add_theme_color_override("font_outline_color", Color("3e2518"))
	button.add_theme_constant_override("outline_size", 2)
	button.add_theme_stylebox_override("normal", Art.texture_style(asset + "_normal.png", 14.0))
	button.add_theme_stylebox_override("hover", Art.texture_style(asset + "_hover.png", 14.0))
	button.add_theme_stylebox_override("pressed", Art.texture_style(asset + "_selected.png", 14.0))
	button.add_theme_stylebox_override("hover_pressed", Art.texture_style(asset + "_selected.png", 14.0))
	var focus: StyleBoxFlat = StyleBoxFlat.new() # 焦点只描边，避免盖住选中纹理。
	focus.draw_center = false
	focus.border_color = Color("fff2bd")
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(9)
	button.add_theme_stylebox_override("focus", focus)
	button.pressed.connect(action)
	parent.add_child(button)
	return button

## 当帧移除 [param parent] 的动态子节点，再排队释放；旧动画和回调不会继续显示。
static func clear(parent: Node) -> void:
	for child: Node in parent.get_children(): # 不保留隐藏的旧预览或旧按钮连接。
		parent.remove_child(child)
		child.queue_free()
