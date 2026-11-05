## 共用素材弹窗；仅收集确认与数量，不读取库存、不扣除资产、不保存。
extends Control

## 确认时发出已校验的整数数量；弹窗关闭后才派发，防止重复提交。
signal confirmed(quantity: int)
## 双按钮弹窗被取消时发出，确认路径不会触发此信号。
signal canceled
## 取消、确认或关闭提示时发出，供宿主清理引用。
signal closed
## 所有按钮、面板及输入框背景复用背包已有素材。
const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")
## 弹窗标题，由宿主在入树前设置。
var _heading: String = ""
## 弹窗说明，不包含需要执行的行为。
var _message: String = ""
## 丢弃数量上限；无需数量的确认或提示使用零。
var _limit: int = 0
## 主操作按钮文案。
var _accept_text: String = "确定"
## 取消按钮文案；空字符串表示单按钮提示。
var _cancel_text: String = ""
## 说明文字颜色，警示确认可覆写。
var _message_color: Color = Color("382719")
## 原始布局尺寸，按有无数量输入区调整高度。
var _design_size: Vector2
## 统一缩放的弹窗画布。
var _canvas: Control
## 可选数量输入；数量为一或信息提示时不存在。
var _quantity: LineEdit
## 只有合法数量才可用的主操作按钮。
var _confirm_button: Button
## 当前说明已提交或关闭，阻止双击与键盘重复触发。
var _finished: bool = false
## 打开前的焦点控件，关闭弹窗时恢复，避免操作落到下层其他入口。
var _previous_focus: Control

## 入树前设置 [param heading]、[param message]；[param limit] 为零显示提示，为正显示“丢弃”确认。
func setup(heading: String, message: String, limit: int = 0) -> void:
	_heading = heading
	_message = message
	_limit = maxi(0, limit)
	_accept_text = "丢弃" if _limit > 0 else "确定"
	_cancel_text = "取消" if _limit > 0 else ""
	_message_color = Color("382719")

## 入树前设置双按钮确认的 [param heading]、[param message]、[param accept_text]、[param cancel_text] 和 [param message_color]。
## 此模式不请求数量，确认时发出固定值 1，默认聚焦取消按钮。
func setup_confirmation(heading: String, message: String, accept_text: String, cancel_text: String,
		message_color: Color = Color("382719")) -> void:
	setup(heading, message)
	_accept_text = accept_text
	_cancel_text = cancel_text
	_message_color = message_color

## 使用既有木框、羊皮纸及按钮素材构建模态界面。
func _ready() -> void:
	_previous_focus = get_viewport().gui_get_focus_owner()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 10
	var shade := ColorRect.new() # 只作为模态遮罩，拦截点击穿透。
	shade.color = Color(0.05, 0.04, 0.03, 0.65)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	_design_size = Vector2(620, 360 if _limit > 1 else 280)
	_canvas = Control.new()
	_canvas.size = _design_size
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	Art.panel(_canvas, "panels/outer_frame_ninepatch.png", Vector2.ZERO, _design_size, 32)
	Art.panel(_canvas, "panels/parchment_ninepatch.png", Vector2(16, 16), _design_size - Vector2(32, 32), 24)
	var heading: Label = Art.label(_canvas, _heading, Vector2(36, 25), Vector2(548, 48), 31) # 弹窗标题居中。
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var has_cancel: bool = not _cancel_text.is_empty() # 双按钮对话框允许取消。
	var simple_confirmation: bool = has_cancel and _limit == 0 # 无数量确认采用居中说明与左确认、右取消的布局。
	var message: Label = Art.label(_canvas, _message, Vector2(42, 84), Vector2(536, 106), 23, _message_color) # 说明自动换行。
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	if simple_confirmation:
		message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if _limit > 1:
		_build_quantity()
	var cancel_button: Button # 双按钮模式下用于取消并接收初始焦点。
	if has_cancel:
		cancel_button = Art.action_button(_canvas, _cancel_text, "buttons/action_neutral",
			Vector2(338 if simple_confirmation else 92, _design_size.y - 76), Vector2(190, 56), dismiss)
	var accept_x: float = 338.0 if _limit > 0 else (92.0 if simple_confirmation else 215.0) # 丢弃和单按钮提示沿用原布局。
	_confirm_button = Art.action_button(_canvas, _accept_text,
		"buttons/action_danger" if _limit > 0 else "buttons/action_confirm",
		Vector2(accept_x, _design_size.y - 76), Vector2(190, 56), _accept)
	resized.connect(_fit)
	_fit()
	_confine_focus(cancel_button if simple_confirmation else _confirm_button)

## 弹窗内建立闭合焦点环，Tab 和方向键不会切换到底层分类、搜索框或丢弃按钮。
## 无数量输入时聚焦 [param initial_button]。
func _confine_focus(initial_button: Button) -> void:
	var controls: Array[Control] = [] # 仅收集本弹窗画布中的输入控件与素材按钮。
	for child: Node in _canvas.get_children():
		if child is Control and child.focus_mode != Control.FOCUS_NONE:
			controls.append(child)
	for index: int in range(controls.size()):
		var control: Control = controls[index] # 当前可聚焦控件。
		var previous: NodePath = control.get_path_to(controls[(index - 1 + controls.size()) % controls.size()]) # 循环前驱。
		var next: NodePath = control.get_path_to(controls[(index + 1) % controls.size()]) # 循环后继。
		control.focus_previous = previous
		control.focus_next = next
		control.focus_neighbor_left = previous
		control.focus_neighbor_top = previous
		control.focus_neighbor_right = next
		control.focus_neighbor_bottom = next
	if _quantity != null:
		_quantity.grab_focus()
		_quantity.select_all()
	else:
		initial_button.grab_focus()

## 生成使用已有素材的数量输入、增减及全部按钮；不使用系统默认 SpinBox 箭头。
func _build_quantity() -> void:
	Art.label(_canvas, "数量", Vector2(42, 196), Vector2(82, 46), 24)
	Art.action_button(_canvas, "−", "buttons/action_neutral", Vector2(132, 192), Vector2(56, 52), _change_quantity.bind(-1))
	Art.panel(_canvas, "controls/search_field.png", Vector2(196, 192), Vector2(116, 52), 12)
	_quantity = LineEdit.new()
	_quantity.text = "1"
	_quantity.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quantity.flat = true
	_quantity.add_theme_font_size_override("font_size", 24)
	_quantity.add_theme_color_override("font_color", Color("382719"))
	_canvas.add_child(_quantity)
	_quantity.position = Vector2(204, 198)
	_quantity.size = Vector2(100, 38)
	_quantity.text_changed.connect(_quantity_changed)
	_quantity.text_submitted.connect(_quantity_submitted)
	Art.action_button(_canvas, "+", "buttons/action_neutral", Vector2(320, 192), Vector2(56, 52), _change_quantity.bind(1))
	Art.action_button(_canvas, "全部", "buttons/action_neutral", Vector2(396, 192), Vector2(116, 52), _select_all)
	Art.label(_canvas, "最多可丢弃 %d" % _limit, Vector2(132, 248), Vector2(420, 30), 19)

## 保持弹窗素材与文字等比缩放，小窗口也不会超出屏幕。
func _fit() -> void:
	if not is_instance_valid(_canvas):
		return
	var factor: float = minf(1.25, minf(size.x / (_design_size.x + 32.0), size.y / (_design_size.y + 32.0))) # 留出屏幕外沿间距。
	_canvas.scale = Vector2.ONE * factor
	_canvas.position = (size - _design_size * factor) * 0.5

## 返回合法整数数量；空白、负数、小数及超出上限的输入返回零。
func _read_quantity() -> int:
	if _quantity == null:
		return 1
	var text: String = _quantity.text.strip_edges() # 先限制位数，再转换，避免超长输入溢出。
	if text.length() > str(_limit).length() or not text.is_valid_int():
		return 0
	var amount: int = text.to_int() # 数量保持整数，不通过浮点数转换。
	return amount if amount >= 1 and amount <= _limit else 0

## [param _text] 是输入控件通知；非法输入只禁用确认，不悄悄替换成其他丢弃数量。
func _quantity_changed(_text: String) -> void:
	if is_instance_valid(_confirm_button):
		_confirm_button.disabled = _read_quantity() == 0

## [param _text] 是回车提交时的输入，统一交给已校验的确认入口。
func _quantity_submitted(_text: String) -> void:
	_accept()

## 按 [param delta] 增减数量，始终限制在一至确认时的持有上限。
func _change_quantity(delta: int) -> void:
	_quantity.text = str(clampi(maxi(1, _read_quantity()) + delta, 1, _limit))
	_quantity_changed(_quantity.text)

## 选择本次弹窗打开时的全部数量，最终数量仍由丢弃操作重新校验。
func _select_all() -> void:
	_quantity.text = str(_limit)
	_quantity_changed(_quantity.text)

## 先关闭弹窗再发出确认；无效输入及重复点击不会派发。
func _accept() -> void:
	var quantity: int = _read_quantity() # 单卡或提示不需要数量控件。
	if _finished or quantity == 0:
		return
	_close()
	if not _cancel_text.is_empty():
		confirmed.emit(quantity)

## 取消或按 Esc 关闭弹窗；只有双按钮确认会派发取消信号。
func dismiss() -> void:
	if _finished:
		return
	_close()
	if not _cancel_text.is_empty():
		canceled.emit()

## 先释放模态界面和焦点，再由调用者发出确认或取消。
func _close() -> void:
	_finished = true
	hide()
	if is_instance_valid(_previous_focus) and _previous_focus.is_inside_tree() and _previous_focus.is_visible_in_tree():
		_previous_focus.grab_focus()
	closed.emit()
	queue_free()

## [param event] 的 Esc 在输入框处理前取消，避免被输入框吞掉或继续关闭整个背包。
func _input(event: InputEvent) -> void:
	if not _finished and event.is_action_pressed(&"ui_cancel"):
		dismiss()
		get_viewport().set_input_as_handled()

## [param event] 的 Enter 在没有焦点控件处理时确认；输入框另通过 text_submitted 进入同一确认入口。
func _unhandled_key_input(event: InputEvent) -> void:
	if _finished or event.is_echo():
		return
	if event.is_action_pressed(&"ui_accept"):
		_accept()
		get_viewport().set_input_as_handled()
