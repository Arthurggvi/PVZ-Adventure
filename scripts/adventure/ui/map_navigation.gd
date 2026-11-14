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
	var target_scene: String
	match destination_id:
		ZOMBIE_ISLAND:
			target_scene = AdventureSession.MAP_SCENE
		TOWN:
			target_scene = Global.main_scene_registry.MainScenesMap[MainSceneRegistry.MainScenes.StartMenu]
		_:
			_picker.set_navigation_pending(false)
			return
	if _source_scene.scene_file_path == target_scene:
		close()
		return
	# 档案和冒险进度由 AdventureSession 校验/保存，导航本身不接管用户状态。
	if destination_id == ZOMBIE_ISLAND and not AdventureSession.prepare_adventure():
		_picker.show_entry_error(AdventureSession.entry_error)
		return
	var transition: Node = _source_scene.get_node_or_null("SceneTransition")
	if transition == null:
		_picker.show_entry_error("当前场景缺少统一场景切换组件。")
		return
	var on_failed := _transition_failed
	transition.transition_failed.connect(on_failed, CONNECT_ONE_SHOT)
	if not transition.change_scene(target_scene):
		transition.transition_failed.disconnect(on_failed)
		_picker.show_entry_error("场景加载请求未被接受，请稍后重试。")

func _transition_failed() -> void:
	if is_open():
		_picker.show_entry_error("场景资源加载失败，可以重试。")
