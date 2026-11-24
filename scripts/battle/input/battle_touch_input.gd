## 手机双指张开输入：只发布一次施放意图，并隔离同次多指操作的残留点击。
## 战斗条件和实际效果由宿主回调决定，此组件不拥有技能或冷却。
extends "res://scripts/battle/input/battle_pointer_router.gd"

## 纯触点与距离状态，不访问战斗或界面。
const SpreadGesture = preload("res://scripts/battle/input/battle_spread_gesture.gd")
## 当前唯一多指操作的识别状态。
var _gesture: RefCounted = SpreadGesture.new()
## 仅校验输入场景是否开放，不把冷却当作取消触摸所有权的理由。
var _can_begin: Callable
## 宿主唯一技能提交入口，失败也不在同一手势中重试。
var _activate: Callable
## 当前真实模拟鼠标是否仍按住；取消重投不改变这个物理状态。
var _mouse_pressed := false
## 原始触点先结束时，继续吃掉随后到来的模拟鼠标释放。
var _drain_mouse := false
## 最近一次未折射的模拟鼠标位置，供取消原有按压。
var _mouse_position := Vector2.ZERO
## 当前触摸设备编号，用于构造同设备的取消事件。
var _touch_device := 0

## 注入 [param can_begin] 的输入资格和 [param activate] 的唯一施放事务，不引用全局技能状态。
func setup(can_begin: Callable, activate: Callable) -> void:
	_can_begin = can_begin
	_activate = activate

## 只读返回原始触点和模拟鼠标是否全部结束，供教学等待，不额外维护第二份触点集合。
func is_pointer_idle() -> bool:
	return not _gesture.has_contacts() and not _mouse_pressed and not _drain_mouse

## 普通输入使用父路由；有触点期间逐帧检查暂停，避免单指跨界面后续接旧手势。
func _ready() -> void:
	super()
	set_process(false)

## 仅消费 [param event] 中已经确认张开的操作；候选阶段的普通双指输入继续照常分发。
func _filter_pointer(event: InputEvent) -> bool:
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		_mouse_position = event.position
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and not _gesture.has_contacts():
				_drain_mouse = false # 后台丢失旧释放时，新的按下仍可开始新操作。
			if not event.pressed and not event.canceled:
				_try_activate() # 快速张开后立即松开也先确认，不能先让 GUI 提交旧点击。
			var consume: bool = _gesture.is_claimed() or _drain_mouse # 先冻结本事件是否属于旧手势。
			_mouse_pressed = event.pressed and not event.canceled
			if not _mouse_pressed:
				_drain_mouse = false
			return consume
		return _gesture.is_claimed() or _drain_mouse
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return false
	if not _gesture.has_contacts():
		if not event is InputEventScreenTouch or not event.pressed:
			return false # 只从真实按下跟踪；门禁关闭时仍等全部触点结束，但候选立即失效。
	_touch_device = event.device
	if event is InputEventScreenTouch and not event.pressed and not event.canceled:
		_try_activate() # 非主指释放不产生模拟鼠标，同样在 GUI 之前作最后一次判断。
	var was_claimed: bool = _gesture.is_claimed() # 最后一指抬起时仍需消费当前释放。
	_gesture.update(event) # 第二指只建立候选，不取消正常点按或平移。
	if not _input_allowed():
		_gesture.invalidate()
	if was_claimed and not _gesture.has_contacts():
		_drain_mouse = _mouse_pressed # 兼容原始触摸与模拟释放的两种到达顺序。
	set_process(_gesture.has_contacts())
	return was_claimed or _gesture.is_claimed()

## [param _delta] 不参与距离计算；等本帧触点更新后判断，并持续检查单指跨暂停的情况。
func _process(_delta: float) -> void:
	_try_activate()

## 明确张开后才接管；先锁存尝试并取消未完成的点击，再调用唯一施放事务。
func _try_activate() -> void:
	if not _input_allowed():
		_gesture.invalidate()
		return
	if not _gesture.take_activation(get_viewport().get_visible_rect().size):
		return
	_cancel_pointer_press()
	if _activate.is_valid():
		_activate.call() # 识别器已先锁存本次尝试，效果失败也不能连续触发。

## 返回本场景是否允许新技能意图；失焦、暂停与弹窗的最终规则仍由宿主统一校验。
func _input_allowed() -> bool:
	return get_window().has_focus() and _can_begin.is_valid() and bool(_can_begin.call())

## 确认张开后取消已有按压，保留已选卡片或工具，不提交尚未完成的种植、铲除或搬移。
func _cancel_pointer_press() -> void:
	var points: Dictionary = _gesture.contact_positions() # 原始触摸索引，不能假设主指编号为零。
	for index: int in points: # 同时兼容原生触摸 GUI 与使用模拟鼠标的旧控件。
		var touch := InputEventScreenTouch.new() # canceled 只取消该触点，不合成新的点击。
		touch.device = _touch_device
		touch.index = index
		touch.position = points[index]
		touch.pressed = false
		touch.canceled = true
		touch.set_meta(CANCEL_KEY, true)
		get_viewport().push_input(touch, true)
	var release := InputEventMouseButton.new() # 让手套、滑拾及旧按钮结束第一指的按压状态。
	release.device = InputEvent.DEVICE_ID_EMULATION
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = _mouse_position
	release.global_position = _mouse_position
	release.pressed = false
	release.canceled = true
	release.set_meta(CANCEL_KEY, true)
	get_viewport().push_input(release, true)

## [param what] 为系统退后台或失焦时，清除旧距离并取消 GUI 按压；恢复后必须重新起手。
func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_PAUSED and what != NOTIFICATION_APPLICATION_FOCUS_OUT:
		return
	if is_inside_tree() and (_gesture.has_contacts() or _mouse_pressed):
		_cancel_pointer_press()
	_gesture.reset()
	_drain_mouse = _mouse_pressed
	set_process(false)
