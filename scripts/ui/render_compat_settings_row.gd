## 原设置弹窗的一行轻量兼容选项：单个复选框、问号和八秒自测。
## 只复用原纸面背景，不创建独立页面、表格或调试工作台。
extends Control

const Probe = preload("res://scripts/ui/render_compat_probe.gd")
const INK: Color = Color("382719")
const MUTED: Color = Color("77532e")
const GOOD: Color = Color("48602f")
const WARN: Color = Color("88402d")
const HELP: String = "针对如 iQOO 机型闪退问题的暂时性优化。\n在闪退的地方开启，不闪退了可以关闭。"

## 当前唯一设置复选框，勾选时关闭可选 GPU 特效。
var _checkbox: CheckBox
## 用户显式触摸的帮助按钮，与自测按钮相互独立。
var _help: Button
## 单击后才会加载旧 Shader 的小按钮。
var _test: Button
## 复用同一提示区域显示帮助、自测和配置保存反馈。
var _hint: Label
## 临时 31×31 图片，只有主动自测期间才存在。
var _probe: TextureRect
## 帮助文字的显示状态；通常只展示原设置控件。
var _help_visible: bool = false

## 将控件放在既有 General 纸面内，不额外添加子面板。
func _ready() -> void:
	name = "RenderCompatibility"
	mouse_filter = Control.MOUSE_FILTER_PASS
	var caption := _label("渲染兼容", Rect2(0, 0, 111, 34), 16, INK)
	caption.accessibility_name = "渲染兼容"
	_checkbox = CheckBox.new()
	_checkbox.text = "禁用特效渲染"
	_checkbox.position = Vector2(113, 0)
	_checkbox.size = Vector2(168, 34)
	_checkbox.button_pressed = Global.config_service.optional_rendering_disabled
	_checkbox.accessibility_name = "禁用可选的动态特效渲染"
	_checkbox.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_child(_checkbox)
	_checkbox.toggled.connect(_toggle_rendering)
	_help = Button.new()
	_help.text = "?"
	_help.position = Vector2(286, 3)
	_help.size = Vector2(29, 29)
	_help.add_theme_font_size_override("font_size", 17)
	_help.tooltip_text = HELP
	_help.accessibility_name = "说明：兼容渲染"
	_help.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_child(_help)
	_help.pressed.connect(_toggle_help)
	_test = Button.new()
	_test.text = "自测 8 秒"
	_test.position = Vector2(321, 2)
	_test.size = Vector2(88, 31)
	_test.add_theme_font_size_override("font_size", 13)
	_test.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_test.accessibility_name = "运行八秒五星旧着色器自测，可能导致闪退"
	add_child(_test)
	_test.pressed.connect(_start_test)
	_hint = _label("", Rect2(0, 29, 409, 38), 12, MUTED)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_restore_probe_hint()
	set_process(false)

## 按视觉顺序向设置页提供三个焦点控件，不额外建立导航逻辑。
func focus_controls() -> Array[Control]:
	return [_checkbox, _help, _test]

## 直接更新真实用户配置，保存失败则恢复复选框，绝不谎报已应用。
func _toggle_rendering(disabled: bool) -> void:
	var result: Error = Global.config_service.set_optional_rendering_disabled(disabled)
	if result != OK:
		_checkbox.set_pressed_no_signal(Global.config_service.optional_rendering_disabled)
		_set_hint("保存失败，仍保持原设置。", WARN)
		return
	_help_visible = false
	_set_hint("已启用兼容渲染。" if disabled else "已恢复正常动态特效。", GOOD)

## 小问号仅显示请求的两句说明，不挤出其他设置选项。
func _toggle_help() -> void:
	_help_visible = not _help_visible
	if _help_visible:
		_set_hint(HELP, MUTED)
	else:
		_restore_probe_hint()

## 自测入口先保存运行标记，再在当前小格绘制真实原版五星 Shader。
func _start_test() -> void:
	if is_instance_valid(_probe):
		return
	_help_visible = false
	_probe = Probe.new()
	_probe.position = Vector2(285, 2)
	_probe.size = Vector2(31, 31)
	add_child(_probe)
	_probe.finished.connect(_on_test_finished)
	var result: Error = _probe.begin()
	if result != OK:
		_probe.queue_free()
		_probe = null
		_set_hint("自测无法启动：请确认已登录并能保存设置。", WARN)
		return
	_help.hide()
	_test.disabled = true
	_set_hint("正在测试旧版动态星章（8 秒），可能导致闪退…", MUTED)
	set_process(true)

## 进度只在自测期间刷新，不增加长驻动画或后台计时。
func _process(_delta: float) -> void:
	if is_instance_valid(_probe):
		var remaining: int = maxi(0, ceili(Probe.DURATION_SECONDS - _probe.elapsed_seconds()))
		_set_hint("正在测试旧版动态星章…剩余 %d 秒" % remaining, MUTED)

## 释放临时 Shader 并把八秒结果显示在原有的单行提示区域。
func _on_test_finished(success: bool) -> void:
	set_process(false)
	if is_instance_valid(_probe):
		_probe.queue_free()
	_probe = null
	_test.disabled = false
	_help.show()
	_set_hint("自测完成，未观察到闪退。" if success else "自测中断或保存失败，可重新测试。",
		GOOD if success else WARN)

## 再次打开设置时能看见上次 running 未结束状态，不直接断言驱动崩溃。
func _restore_probe_hint() -> void:
	match Global.config_service.get_render_probe_state():
		"running":
			_set_hint("上次自测未完成；如曾闪退，建议开启兼容渲染。", WARN)
		"passed":
			_set_hint("上次自测通过；仅代表此项运行正常。", GOOD)
		_:
			_set_hint("", MUTED)

## 使用现有纸面颜色排版标签，不另建工作台。
func _label(text: String, rect: Rect2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = rect.position
	label.size = rect.size
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	add_child(label)
	return label

## 帮助与状态更新共用同一固定区域，避免窗口内容跳动。
func _set_hint(message: String, color: Color) -> void:
	_hint.text = message
	_hint.add_theme_color_override("font_color", color)
