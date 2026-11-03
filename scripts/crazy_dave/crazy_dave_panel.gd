extends Panel
class_name DaveDialogMousePress
## 戴夫对话时检测鼠标点击，发出信号，同时截断鼠标点击时间

## 戴夫对话时，检查鼠标是否点击
signal signal_dave_dialog_press

## 可选的输入校验；未配置时保持原版点击行为，不影响既有关卡或商店。
var advance_guard: Callable

## 原生点击和封装层共用同一推进入口；校验拒绝时不发射点击信号。
func request_advance() -> void:
	if advance_guard.is_valid() and not advance_guard.call():
		return
	signal_dave_dialog_press.emit()

func _gui_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			request_advance()
