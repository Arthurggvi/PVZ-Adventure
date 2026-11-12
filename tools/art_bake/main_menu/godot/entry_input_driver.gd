extends RefCounted
## 录制用原生输入源：持续声明鼠标仍在视口内，不直接指定hover或调用业务。
## 实际接收输入的窗口视口。
var viewport: Window
## 录制鼠标的位置与按下状态。
var position := Vector2.ZERO
var pressed := false
## 键盘演示期间不重复注入鼠标，否则会夺走焦点表现。
var keyboard_mode := false
## 边界通知只在真正离开后恢复；避免每帧重复通知造成原生诊断刷屏。
var _inside := true

## [param target] 是原生视口；不是自定义命中模拟器。
func configure(target: Viewport) -> void:
	viewport=target as Window
	assert(viewport != null,"Recorder requires a native Window")
	viewport.mouse_entered.connect(_set_inside.bind(true))
	viewport.mouse_exited.connect(_set_inside.bind(false))

## [param value] 记录窗口边界事件，不决定任何建筑命中。
func _set_inside(value: bool) -> void:
	_inside=value

## [param point] 为视口坐标，原生Control仍决定是否被UI遮挡。
func move(point: Vector2) -> void:
	position=point
	keyboard_mode=false
	viewport.warp_mouse(position)
	refresh_pointer()

## 录制期间远程终端可能改变OS焦点；重新送入真实Motion事件，不修改目标状态。
func refresh_pointer() -> void:
	if keyboard_mode:
		return
	if not _inside:
		_inside=true
		viewport.notify_mouse_entered()
	var event:=InputEventMouseMotion.new() # 零位移仍通过原生GUI拾取路径。
	event.position=position
	event.global_position=position
	event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0
	viewport.push_input(event,true)

## [param down] 的原生Button事件，提交前先同步鼠标在视口内的状态。
func button(down: bool) -> void:
	keyboard_mode=false
	refresh_pointer()
	pressed=down
	var event:=InputEventMouseButton.new() # 不调用hit.activated或工具栏请求。
	event.position=position
	event.global_position=position
	event.button_index=MOUSE_BUTTON_LEFT
	event.pressed=down
	event.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0
	viewport.push_input(event,true)

## 退出前解除根窗口上的输入边界信号，避免录制器生命周期泄漏。
func dispose() -> void:
	if is_instance_valid(viewport):
		viewport.mouse_entered.disconnect(_set_inside.bind(true))
		viewport.mouse_exited.disconnect(_set_inside.bind(false))
	viewport=null
