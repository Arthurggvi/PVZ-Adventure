## 玉米加农炮的瞄准光标和确认；鼠标与触屏使用同一战场坐标。
extends Sprite2D
class_name CobCannonTarget

## 当前是否正在等待玩家选取落点。
var is_activate := false
## 手机点按只在对应释放时确认，双指接管可以在此之前取消。
var _touch_pressed := false

## 确认加农炮落点时发送，参数为战斗画布的全局位置。
signal signal_cannon_fire(target_global_pos:Vector2)

## 空闲时不注册输入回调，也不更新光标。
func _ready() -> void:
	deactivate_it()

## [param _delta] 为帧间隔；瞄准期间让光标跟随鼠标或当前触点。
func _process(_delta: float) -> void:
	global_position = BattleEnvironmentLens.mouse_position(self)

## [param event] 为取消动作时先关闭瞄准，避免移动端返回键直接打开暂停菜单。
func _input(event: InputEvent) -> void:
	if (event is InputEventScreenTouch or event is InputEventMouseButton) and event.is_canceled():
		_touch_pressed = false
	if event.is_action_pressed(&"ui_cancel"):
		deactivate_it()
		get_viewport().set_input_as_handled()

## [param event] 由 GUI 让到战场时处理；桌面按下确认，手机松开确认以允许双指取消。
func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or event.canceled:
		return
	var touch: bool = OS.has_feature("mobile") and event.device == InputEvent.DEVICE_ID_EMULATION # 仅改变手机的可取消点按。
	if touch and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_touch_pressed = true
			get_viewport().set_input_as_handled()
			return
		if not _touch_pressed:
			return
		_touch_pressed = false
	elif not event.pressed:
		return
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			# 水下透镜转发时已换算事件坐标，不能取上一帧的光标位置。
			var target: Vector2 = get_canvas_transform().affine_inverse() * event.position
			signal_cannon_fire.emit(target)
		MOUSE_BUTTON_RIGHT:
			pass
		_:
			return
	deactivate_it()
	get_viewport().set_input_as_handled()

## 显示瞄准光标并接收战场确认。
func activate_it() -> void:
	_set_aiming(true)

## 收起光标并交还输入。
func deactivate_it() -> void:
	_set_aiming(false)

## 将瞄准状态 [param active] 同步到显示、进程和输入回调。
func _set_aiming(active: bool) -> void:
	_touch_pressed = false
	is_activate = active
	visible = active
	set_process(active)
	set_process_input(active)
	set_process_unhandled_input(active)


