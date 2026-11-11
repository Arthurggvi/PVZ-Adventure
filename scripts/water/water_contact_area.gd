## 汇总探测器接触的水体，供不同实体共用同一套入水和出水判定。
extends Area2D
class_name WaterContactArea

## 第一次接触水体或离开最后一个水体时发送。
signal water_contact_changed(touching: bool)

## 是否接触任意水体；同一帧跨过相邻区域时保持为 true。
var touching_water: bool = false
## 按实例 ID 登记接触，避免持有已经移除的水体。
var _contacts: Dictionary[int, WeakRef] = {}
## 同一帧最多安排一次出水确认。
var _exit_check_pending: bool = false

func _ready() -> void:
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)

## 登记水体 [param area]，同时监听水体被移除的情况。
func _on_area_entered(area: Area2D) -> void:
	if not area is WaterBodyArea:
		return
	var id: int = area.get_instance_id() # 区分同时接触的水体。
	if _contacts.has(id):
		return
	_contacts[id] = weakref(area)
	area.tree_exiting.connect(_remove_contact.bind(id), CONNECT_ONE_SHOT)
	if not touching_water:
		touching_water = true
		water_contact_changed.emit(true)

## 结束和 [param area] 的物理接触，解除对应的离树监听。
func _on_area_exited(area: Area2D) -> void:
	if not area is WaterBodyArea:
		return
	var id: int = area.get_instance_id() # 正在离开的水体。
	var on_removed: Callable = _remove_contact.bind(id) # 与入水时注册的监听对应。
	if area.tree_exiting.is_connected(on_removed):
		area.tree_exiting.disconnect(on_removed)
	_remove_contact(id)

## 释放 [param id] 对应的水体，等同帧物理回调结束后再确认出水。
func _remove_contact(id: int) -> void:
	if _contacts.erase(id) and not _exit_check_pending:
		_exit_check_pending = true
		_confirm_exit.call_deferred()

## 清理失效引用，仅在探测器仍在场景树中时通知出水。
func _confirm_exit() -> void:
	_exit_check_pending = false
	for id: int in _contacts.keys(): # 水体释放后可能只剩弱引用。
		if not is_instance_valid(_contacts[id].get_ref()):
			_contacts.erase(id)
	if touching_water and _contacts.is_empty():
		touching_water = false
		if is_inside_tree():
			water_contact_changed.emit(false)
