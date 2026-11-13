## One navigation owner for every map HUD surface. Scene UI never owns route selection.
## The picker is a temporary view; the persistent toolbar owns its lifetime.
extends Node

signal navigation_state_changed

const PICKER = preload("res://scenes/adventure/AdventureDestinationPicker.tscn")
const ZOMBIE_ISLAND := "zombie_island"
## 城镇卡片的稳定地区 ID，目标场景由主场景注册表提供。
const TOWN := "town"

var _picker: Control
var _source_scene: Node

func is_open() -> bool:
	return is_instance_valid(_picker)

func open_from(scene: Node) -> bool:
	if not is_instance_valid(scene) or not scene.is_in_group(&"adventure_toolbar_surface"):
		return false
	if is_open():
		return true
	_source_scene = scene
	_picker = PICKER.instantiate()
	_picker.name = "MapDestinationPicker"
	_picker.close_requested.connect(close)
	_picker.destination_selected.connect(_navigate)
	add_child(_picker)
	navigation_state_changed.emit()
	return true

func close() -> void:
	var was_open := is_open()
	if was_open:
		_picker.hide()
		_picker.queue_free()
	_picker = null
	_source_scene = null
	if was_open:
		navigation_state_changed.emit()

## 跳转至 [param destination_id] 对应的场景，选择当前地区时直接关闭地图。
func _navigate(destination_id: String) -> void:
	if not is_open() or not _picker.is_presented() or not _picker.can_select(destination_id):
		return
	if not is_instance_valid(_source_scene) or get_tree().current_scene != _source_scene:
		close()
		return
	var target_scene: String # 用于识别当前地区并避免重复加载场景。
	var enter: Callable # 在遮幕完成后执行的已注册入口。
	match destination_id:
		ZOMBIE_ISLAND:
			target_scene = AdventureSession.MAP_SCENE
			enter = _enter_zombie_island
		TOWN:
			target_scene = Global.main_scene_registry.MainScenesMap[MainSceneRegistry.MainScenes.StartMenu]
			enter = _enter_town.bind(target_scene)
		_:
			_picker.set_navigation_pending(false)
			return
	if _source_scene.scene_file_path == target_scene:
		close()
		return
	var transition := _source_scene.get_node_or_null("SceneTransition") # 使用宿主的场景遮幕。
	if transition == null:
		enter.call()
	elif not transition.run(enter):
		_picker.set_navigation_pending(false)

func _enter_zombie_island() -> bool:
	if not is_open() or not is_instance_valid(_source_scene):
		return false
	if AdventureSession.open_adventure():
		return true
	_picker.show_entry_error(AdventureSession.entry_error)
	return false

## 打开 [param scene_path] 指定的主菜单；切换失败时提示并恢复地图输入。
func _enter_town(scene_path: String) -> bool:
	if not is_open() or not is_instance_valid(_source_scene):
		return false
	if get_tree().change_scene_to_file(scene_path) == OK:
		return true
	_picker.show_entry_error("无法返回城镇，请重试。")
	return false
