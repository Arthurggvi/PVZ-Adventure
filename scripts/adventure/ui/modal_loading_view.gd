## 模态请求的轻量反馈；只使用原生控件，不加载功能窗口的美术或业务资源。
extends Control

## 取消请求时通知同一个工具栏模态拥有者。
signal closed
## 当前加载说明。
var _caption: Label
## 资源准备进度，不表示窗口已经可以操作。
var _progress: ProgressBar
## 防止重复取消。
var _closed := false

## 立即建立可取消反馈，保留窗口下方的场景。
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new() # 遮挡原场景点击，不依赖外部贴图。
	shade.color = Color(0.025, 0.035, 0.025, 0.64)
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new() # 原生居中布局随窗口大小变化。
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new() # 小型反馈面板，不创建真实窗口的控件树。
	panel.custom_minimum_size = Vector2(300, 150)
	center.add_child(panel)
	var rows := VBoxContainer.new() # 标题、进度与取消按钮按顺序排列。
	rows.add_theme_constant_override("separation", 14)
	panel.add_child(rows)
	_caption = Label.new()
	_caption.text = "正在打开…"
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(_caption)
	_progress = ProgressBar.new()
	_progress.show_percentage = false
	rows.add_child(_progress)
	var cancel := Button.new() # 同一按钮用于取消加载和关闭失败反馈。
	cancel.text = "取消"
	cancel.pressed.connect(request_close)
	rows.add_child(cancel)
	cancel.grab_focus()

## [param amount] 为当前阶段的零至一进度。
func set_progress(amount: float) -> void:
	_progress.value = clampf(amount, 0.0, 1.0) * 100.0

## [param message] 为可重试失败说明；关闭后恢复原入口。
func show_error(message: String) -> void:
	_caption.text = message
	_progress.hide()

## 取消只撤销呈现资格，不同步等待后台请求。
func request_close() -> void:
	if _closed:
		return
	_closed = true
	closed.emit()
	queue_free()

## [param event] 的取消键关闭反馈并阻止穿透。
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		request_close()
