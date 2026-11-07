## 延迟静止悬停提示：目标上的移动重置计时，离开、点击、隐藏和失焦立即收起。
extends Control
class_name StationaryHoverHint

## 工具栏与角色面板共享的提示皮肤。
const HoverTip = preload("res://scripts/adventure/ui/hover_tip_skin.gd")
## 鼠标静止多久后显示，单位秒；不受游戏倍速影响。
const DELAY_SECONDS: float = 0.7
## 被观察的表现控件，不持有玩家数据。
var _target: Control
## 单次等待计时器；移动时重新开始。
var _timer: Timer
## 浮动提示面板，所有子控件忽略鼠标以避免抢走目标悬停。
var _bubble: PanelContainer
## 显示文字，仅由外层展示快照更新。
var _text: RichTextLabel
## 最近一次目标鼠标事件的位置，保存为本组件局部坐标，提示不跟随其他窗口的指针查询。
var _pointer_position: Vector2

## 创建提示并绑定窗口焦点；节点随所属窗口销毁，不留下全局计时器。
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 20
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = DELAY_SECONDS
	_timer.ignore_time_scale = true
	add_child(_timer)
	_timer.timeout.connect(_show_hint)
	_bubble = HoverTip.panel(10.0)
	add_child(_bubble)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.add_theme_font_size_override("normal_font_size", 17)
	_text.add_theme_color_override("default_color", HoverTip.TEXT_COLOR)
	_bubble.add_child(_text)
	_bubble.hide()
	visibility_changed.connect(dismiss)
	get_window().focus_exited.connect(dismiss)

## 观察 [param target] 的鼠标输入；只能绑定一次，目标已有业务不受修改。
func watch(target: Control) -> void:
	assert(_target == null)
	_target = target
	_target.mouse_entered.connect(_restart)
	_target.mouse_exited.connect(dismiss)
	_target.gui_input.connect(_target_input)
	_target.visibility_changed.connect(dismiss)

## 更新 [param value] 的 BBCode 摘要；已显示的旧信息随快照变化收起。
func set_text(value: String) -> void:
	_text.text = value
	dismiss()
	if is_instance_valid(_target) and get_viewport().gui_get_hovered_control() == _target:
		_restart()

## 取消等待和显示；离树前调用仍安全。
func dismiss() -> void:
	if is_instance_valid(_timer):
		_timer.stop()
	if is_instance_valid(_bubble):
		_bubble.hide()

## 重新计时，移动鼠标不会让旧位置的提示继续显示。
func _restart() -> void:
	dismiss()
	if is_visible_in_tree() and is_instance_valid(_target) and _target.is_visible_in_tree():
		_pointer_position = get_global_transform_with_canvas().affine_inverse() * get_viewport().get_mouse_position()
		_timer.start()

## [param event] 只用于观察静止；不消费目标输入。
func _target_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_restart()
		_pointer_position = get_global_transform_with_canvas().affine_inverse() \
			* _target.get_global_transform_with_canvas() * event.position
	elif event is InputEventMouseButton:
		dismiss()

## 任意按键或点击（包括打开其他弹窗）立即收起，不拦截输入传播。
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventKey:
		dismiss()

## 等待结束后重验悬停目标，将浮层限制在所属面板设计坐标内。
func _show_hint() -> void:
	if not is_visible_in_tree() or not is_instance_valid(_target) or not _target.is_visible_in_tree() \
			or get_viewport().gui_get_hovered_control() != _target or not get_window().has_focus():
		return
	_bubble.reset_size()
	var bounds: Vector2 = get_parent_control().size # 浮层不越过角色面板边缘。
	_bubble.position = (_pointer_position + Vector2(22, 22)).clamp(Vector2(12, 12), (bounds - _bubble.size - Vector2(12, 12)).max(Vector2(12, 12)))
	_bubble.show()
