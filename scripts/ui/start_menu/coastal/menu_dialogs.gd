extends CanvasLayer
## 菜单独有的档案和退出窗口；业务档案仍由原 User 和 SaveService 负责。
## 退出确认通过宿主处理，不在UI中直接销毁游戏树。
signal exit_confirmed
## 原有完整档案选择器。
const Selector=preload("res://scenes/ui/profile_selector.tscn")
## 已有纸面和木框素材。
const Art=preload("res://scripts/adventure/ui/inventory_skin.gd")
## 与游戏一致的中文字体。
const FONT=preload("res://assets/fonts/方正少儿_GBK.ttf")
## 覆盖整个菜单的模态遮罩容器。
var surface: Control
## 退出确认时移至档案选择器上方，阻止鼠标点击穿透。
var _shade: ColorRect
## 取消退出时可恢复的原控件，等待期间可能随旧窗口关闭而销毁。
var _previous_exit_focus: Control
## 负责档案切换的既有选择器。
var selector: Control
## 确认退出和保存失败共用的木框窗口。
var panel: Panel
## 窗口标题，区分确认和保存失败。
var title: Label
## 说明当前操作对进度的影响，或提示保存失败后的操作。
var message: Label
## 关闭弹窗的按钮，也是打开时的默认焦点。
var cancel: Button
## 触发退出的按钮，保存失败时隐藏。
var confirm: Button

## 创建档案选择器、全屏遮罩和退出窗口。
func _ready() -> void:
	# 退出确认及其遮罩须盖过修改器（90），仍由场景切换遮幕（100）统一阻挡切场输入。
	layer = 95
	surface = Control.new()
	add_child(surface)
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade = ColorRect.new()
	_shade.color = Color(0, 0, 0, 0.55)
	surface.add_child(_shade)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	selector = Selector.instantiate()
	surface.add_child(selector)
	selector.visibility_changed.connect(_sync)
	panel = Panel.new()
	surface.add_child(panel)
	panel.size = Vector2(480, 232)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	panel.add_theme_stylebox_override("panel", Art.texture_style("panels/outer_frame_ninepatch.png", 36))
	Art.panel(panel, "panels/parchment_ninepatch.png", Vector2(25, 25), Vector2(430, 182), 20)

	title = Art.label(panel, "", Vector2(44, 42), Vector2(392, 42), 32, Color("362419"))
	title.add_theme_font_override("font", FONT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var divider := ColorRect.new() # 标题下方的短横线，沿用羊皮纸的暖色边缘。
	divider.color = Color("9f754b")
	divider.position = Vector2(216, 91)
	divider.size = Vector2(48, 2)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(divider)
	message = Art.label(panel, "", Vector2(44, 99), Vector2(392, 43), 21, Color("59412e"))
	message.add_theme_font_override("font", FONT)
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var actions := HBoxContainer.new() # 确认按钮隐藏时，返回按钮随按钮栏自动居中。
	actions.position = Vector2(44, 146)
	actions.size = Vector2(392, 44)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 16)
	panel.add_child(actions)
	var button_size := Vector2(150, 44) # 两个操作共用的最小点击区域，以界面坐标计。
	cancel = Art.action_button(actions, "取消", "buttons/action_neutral", Vector2.ZERO, button_size, close_panel)
	cancel.name = "Close"
	cancel.custom_minimum_size = button_size
	cancel.add_theme_font_size_override("font_size", 20)
	confirm = Art.action_button(actions, "退出游戏", "buttons/action_danger", Vector2.ZERO, button_size, func(): exit_confirmed.emit())
	confirm.name = "ConfirmExit"
	confirm.custom_minimum_size = button_size
	confirm.add_theme_font_size_override("font_size", 20)
	confirm.focus_next = confirm.get_path_to(cancel)
	confirm.focus_previous = confirm.focus_next
	confirm.focus_neighbor_left = confirm.focus_next
	confirm.focus_neighbor_right = NodePath(".")
	confirm.focus_neighbor_top = NodePath(".")
	confirm.focus_neighbor_bottom = NodePath(".")
	cancel.focus_neighbor_left = NodePath(".")
	cancel.focus_neighbor_top = NodePath(".")
	cancel.focus_neighbor_bottom = NodePath(".")
	panel.hide()
	_sync()

## 返回当前顶层状态，供工具栏和建筑输入同源阻断。
func is_open() -> bool:
	return is_instance_valid(selector) and (selector.visible or (is_instance_valid(panel) and panel.visible))

## 打开原有档案流程；不创建、修改或切换任何档案，直到用户实际操作。
func open_profiles() -> void:
	if is_open():
		return
	selector.show()
	_sync()

## 响应窗口关闭请求；[param has_profile] 决定显示存档或访客提示。
func open_exit_confirmation(has_profile: bool) -> void:
	if panel.visible:
		return
	_previous_exit_focus = get_viewport().gui_get_focus_owner()
	surface.move_child(_shade, selector.get_index())
	title.text = "退出游戏？"
	message.text = "退出前会自动存档。" if has_profile else "未选择存档，进度不会保存。"
	cancel.text = "取消"
	confirm.text = "保存并退出" if has_profile else "退出游戏"
	cancel.focus_next = cancel.get_path_to(confirm)
	cancel.focus_previous = cancel.focus_next
	cancel.focus_neighbor_right = cancel.focus_next
	confirm.show()
	panel.show()
	_sync()
	cancel.grab_focus()

## 仅关闭当前小窗口；原档案选择器由自己的确认/取消事务关闭。
func close_panel() -> void:
	panel.hide()
	surface.move_child(_shade, 0)
	_sync()
	if is_instance_valid(_previous_exit_focus) and _previous_exit_focus.is_visible_in_tree():
		_previous_exit_focus.grab_focus()
	_previous_exit_focus = null

## 在退出窗口内提示保存失败，并提供返回主菜单的操作。
func show_save_error() -> void:
	title.text = "进度保存失败"
	message.text = "请返回主菜单后再试一次。"
	cancel.text = "返回主菜单"
	confirm.hide()
	cancel.focus_next = NodePath(".")
	cancel.focus_previous = cancel.focus_next
	cancel.focus_neighbor_right = cancel.focus_next
	cancel.grab_focus()

func _sync() -> void:
	surface.visible=is_open()

## 退出确认优先消费 [param event] 的取消操作，避免关闭下层功能窗口。
func _input(event: InputEvent) -> void:
	if panel.visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_panel()

## 其余未被控件消费的 [param event] 继续交由原档案选择器处理。
func _unhandled_key_input(event: InputEvent) -> void:
	if selector.visible and event.is_action_pressed("ui_cancel"):
		selector._on_button_cancel_pressed() # 原选择器保持未选择档案时的拒绝逻辑。
		get_viewport().set_input_as_handled()
