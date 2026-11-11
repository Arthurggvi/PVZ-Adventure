extends Node2D
class_name SwimBoxComponent
## 僵尸游泳组件基类

@onready var shadow: Sprite2D = %Shadow
@onready var body: BodyCharacter = %Body

## 游泳时body变化
@export var body_change_swim:ResourceBodyChange

## 特殊水花位置(普通水花位置跟影子重叠,海豚僵尸使用)
@export var special_splash_pos_node:Node2D

var owner_is_death:=false

## 当前接触的水体弱引用；相邻地块/重叠水域不能重复下沉或提前出水。
var _water_contacts: Dictionary[int, WeakRef] = {}
## 当前是否接触任意水体，与具体表现过渡时间分开。
var _water_active: bool = false
## 本帧是否已经安排最后一次水体离开检查。
var _exit_check_pending: bool = false

## 改变游泳状态信号
signal signal_change_is_swimming(is_swimming:bool)

func _on_owner_is_death():
	owner_is_death = true

## 检测到泳池
func _on_area_2d_area_entered(area: Area2D) -> void:
	if not area is WaterBodyArea:
		return
	var id: int = area.get_instance_id() # 水体稳定实例身份。
	if _water_contacts.has(id):
		return
	_water_contacts[id] = weakref(area)
	var removed: Callable = _on_water_removed.bind(id) # 地形销毁也需要释放接触。
	if not area.tree_exiting.is_connected(removed):
		area.tree_exiting.connect(removed, CONNECT_ONE_SHOT)
	if not _water_active:
		_water_active = true
		if not owner_is_death:
			_on_water_contact_changed(true)


## 离开泳池
func _on_area_2d_area_exited(area: Area2D) -> void:
	if area is WaterBodyArea:
		_on_water_removed(area.get_instance_id())


## 出现水花
func appear_splash():
	## 水花
	var splash = SceneRegistry.SPLASH.instantiate()
	splash.position = shadow.global_position - owner.get_parent().global_position + Vector2(0, 15)
	owner.get_parent().add_child.call_deferred(splash)

## 特殊位置水花
func appear_splash_special_pos():
	## 水花
	var splash = SceneRegistry.SPLASH.instantiate()
	splash.position = special_splash_pos_node.global_position - owner.get_parent().global_position + Vector2(0, 15)

	owner.get_parent().add_child.call_deferred(splash)


## 移除 [param id] 后延迟到同帧接触回调结束，避免从一块水域跨入另一块时闪烁。
func _on_water_removed(id: int) -> void:
	_water_contacts.erase(id)
	if not _exit_check_pending:
		_exit_check_pending = true
		_confirm_water_exit.call_deferred()

## 最后一个水体离开才触发出水；释放后的弱引用不会留下永久游泳状态。
func _confirm_water_exit() -> void:
	_exit_check_pending = false
	for id: int in _water_contacts.keys(): # 逐一清除已经释放的水体。
		if not is_instance_valid(_water_contacts[id].get_ref()):
			_water_contacts.erase(id)
	if _water_active and _water_contacts.is_empty():
		_water_active = false
		if not owner_is_death:
			_on_water_contact_changed(false)

## 派生表现只处理聚合后的 [param swimming] 变化，禁止重写接触计数协议。
func _on_water_contact_changed(swimming: bool) -> void:
	signal_change_is_swimming.emit(swimming)
