extends Control
## 稳定建筑命中控件：原生GUI路由、同目标按下释放；视觉蒙版由另一层拥有。
## 真正完成激活时通知父层重新检查业务状态。
signal activated(entry_id: String)
## 入口身份，不保存解锁状态。
var entry_id := ""
## 稳定原画坐标轮廓及排除区。
var outlines: Array[PackedVector2Array] = []
var exclusions: Array[PackedVector2Array] = []
## 当前是否可接收动作；模态打开时清除按下状态。
var input_allowed := true
## 同一次鼠标按下的归属。
var armed := false

## [param entry] 中的坐标是母图像素；控件随同一画布缩放，不增加屏幕偏移。
func configure(entry: Dictionary, canvas: Vector2) -> void:
	entry_id = entry.id
	name = entry_id
	size = canvas
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	accessibility_name = entry.name+"："+entry.title
	for values: Array in entry.hit:
		var shape := PackedVector2Array() # 只在装载时转换一次。
		for point: Array in values:
			shape.append(Vector2(point[0],point[1]))
		outlines.append(shape)
	for values: Array in entry.exclude:
		var shape := PackedVector2Array() # 排除皮卡等不属于入口的部分。
		for point: Array in values:
			shape.append(Vector2(point[0],point[1]))
		exclusions.append(shape)

## [param point] 为控件局部原画坐标；只处理稳定空间，不读取运动纹理。
func _has_point(point: Vector2) -> bool:
	if not input_allowed:
		return false
	for shape: PackedVector2Array in exclusions:
		if Geometry2D.is_point_in_polygon(point,shape):
			return false
	for shape: PackedVector2Array in outlines:
		if Geometry2D.is_point_in_polygon(point,shape):
			return true
	return false

## [param enabled] 仅阻塞输入，不决定业务解锁；隐藏模态时必须取消已按下动作。
func set_input_allowed(enabled: bool) -> void:
	if input_allowed == enabled:
		return
	input_allowed = enabled
	mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
	if not enabled:
		armed = false
		if has_focus():
			release_focus()

## 接收 [param event] 的原生GUI事件；hover永不触发打开，释放须仍在同一目标。
func _gui_input(event: InputEvent) -> void:
	if not input_allowed:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			armed = true
		else:
			var accepted: bool = armed and _has_point(event.position) and get_viewport().gui_get_hovered_control() == self # 捕获释放不等于仍在顶层；前景控件覆盖也取消。
			armed = false
			if accepted:
				activated.emit(entry_id)
		accept_event()
	elif event.is_action_pressed(&"ui_accept") and not event.is_echo():
		activated.emit(entry_id)
		accept_event()
