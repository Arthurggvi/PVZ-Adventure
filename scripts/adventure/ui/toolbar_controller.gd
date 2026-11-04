## Single persistent UI layer for any scene advertising the toolbar surface group.
extends CanvasLayer

const View = preload("res://scripts/adventure/ui/toolbar_view.gd")
const Features = preload("res://scripts/adventure/ui/toolbar_features.gd")
const Inventory = preload("res://scripts/adventure/ui/inventory_window.gd")
const HOST_GROUP := &"adventure_toolbar_surface"
var _view: AdventureToolbarView
var _hooks: Dictionary = {}
var _host_allowed := false
var _host_scene: Node
var _inventory: AdventureInventoryWindow

func _ready() -> void:
	layer = 50 # Below existing SceneTransition (100), above ordinary map art.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_view = View.new()
	_view.name = "ToolbarView"
	add_child(_view)
	_view.feature_pressed.connect(_on_feature_pressed)
	get_tree().scene_changed.connect(_on_scene_changed)
	Global.user_manager.signal_users_update.connect(_refresh)
	register_feature("inventory", Callable(self, "_can_open_inventory"), Callable(self, "_open_inventory"))
	_on_scene_changed(get_tree().current_scene)

func _process(_delta: float) -> void:
	# Profile load completes after the user-update signal; sync availability on transition only.
	if is_instance_valid(_view) and _view._available.get("inventory", false) != _can_open_inventory():
		_refresh()
	# Menus temporarily disabled by modal navigation cannot leak clicks to this layer.
	var can_show := _host_allowed and is_instance_valid(_host_scene) \
		and _host_scene.process_mode != Node.PROCESS_MODE_DISABLED and not get_tree().paused
	if visible != can_show:
		visible = can_show

func _on_scene_changed(scene: Node) -> void:
	if is_instance_valid(_inventory):
		_inventory.queue_free()
	_inventory = null
	_host_scene = scene
	_host_allowed = is_instance_valid(scene) and scene.is_in_group(HOST_GROUP)
	visible = _host_allowed
	_refresh()

func _can_open_inventory() -> bool:
	return Global.save_service != null and Global.save_service.is_current_profile_loaded() \
		and Global.adventure_inventory != null and Global.global_game_state.adventure_state != null

func _open_inventory() -> void:
	if is_instance_valid(_inventory):
		_inventory.request_close()
		return
	if not _can_open_inventory():
		return
	_inventory = Inventory.new()
	_inventory.name = "AdventureInventoryWindow"
	add_child(_inventory)
	# Toolbar stays above the modal, so its inventory icon can close it again.
	move_child(_view, get_child_count() - 1)
	_inventory.closed.connect(func(): _inventory = null)

## Additional modules register a real screen and its actual unlock predicate here.
## Registration alone never changes a player's stored progress.
func register_feature(feature_id: String, unlock_check: Callable, open_action: Callable) -> bool:
	if feature_id == "map" or feature_id == "empty" \
		or not Features.is_known(feature_id) or not unlock_check.is_valid() or not open_action.is_valid():
		return false
	_hooks[feature_id] = {"unlock": unlock_check, "open": open_action}
	_refresh()
	return true

func unregister_feature(feature_id: String) -> void:
	_hooks.erase(feature_id)
	_refresh()

func _refresh() -> void:
	if not is_instance_valid(_view):
		return
	var enabled: Dictionary = {"map": Features.can_open_map()}
	for id: String in _hooks:
		var entry: Dictionary = _hooks[id]
		if entry.unlock.is_valid() and entry.open.is_valid():
			enabled[id] = entry.unlock.call() == true
	_view.refresh(enabled)

func _on_feature_pressed(feature_id: String) -> void:
	# Modal window blocks map and unrelated navigation; inventory remains a toggle.
	if is_instance_valid(_inventory) and feature_id != "inventory":
		return
	if feature_id == "map":
		if not Features.can_open_map():
			return
		var scene := get_tree().current_scene
		if is_instance_valid(scene) and scene.has_method("open_adventure_toolbar_map"):
			scene.call("open_adventure_toolbar_map") # Scene chooses its region navigation.
			return
		if is_instance_valid(scene) and scene.scene_file_path == AdventureSession.MAP_SCENE:
			return # Already viewing the canonical map.
		if not AdventureSession.open_adventure():
			push_warning("Adventure toolbar: " + AdventureSession.entry_error)
		return
	if not _hooks.has(feature_id):
		return
	var entry: Dictionary = _hooks[feature_id]
	if entry.unlock.is_valid() and entry.unlock.call() == true and entry.open.is_valid():
		entry.open.call()
