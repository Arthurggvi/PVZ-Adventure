## Single persistent UI layer for any scene advertising the toolbar surface group.
extends CanvasLayer

const View = preload("res://scripts/adventure/ui/toolbar_view.gd")
const Features = preload("res://scripts/adventure/ui/toolbar_features.gd")
const Inventory = preload("res://scripts/adventure/ui/inventory_window.gd")
const Research = preload("res://scripts/adventure/ui/research_lab_stage.gd")
const MapNavigation = preload("res://scripts/adventure/ui/map_navigation.gd")
const HOST_GROUP := &"adventure_toolbar_surface"
var _view: AdventureToolbarView
var _hooks: Dictionary = {}
var _host_allowed := false
var _interactive := false
var _host_scene: Node
var _inventory: AdventureInventoryWindow
var _research: AdventureResearchLabStage
var _navigation: Node

func _ready() -> void:
	layer = 50 # Below existing SceneTransition (100), above ordinary map art.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_view = View.new()
	_view.name = "ToolbarView"
	add_child(_view)
	_view.feature_pressed.connect(_on_feature_pressed)
	_navigation = MapNavigation.new()
	_navigation.name = "MapNavigation"
	add_child(_navigation)
	_navigation.navigation_state_changed.connect(_sync_input)
	get_tree().scene_changed.connect(_on_scene_changed)
	Global.user_manager.signal_users_update.connect(_refresh)
	register_feature("inventory", Callable(self, "_can_open_inventory"), Callable(self, "_open_inventory"))
	register_feature("research", Callable(self, "can_open_research_preview"), Callable(self, "_open_research"))
	_on_scene_changed()

func _process(_delta: float) -> void:
	# Scene ownership controls visibility; temporary modal input locks never hide the HUD.
	_sync_input()
	if _host_allowed and _view._available.get("inventory", false) != _can_open_inventory():
		_refresh()

func _sync_input() -> void:
	var allowed: bool = _host_allowed and is_instance_valid(_host_scene) and not get_tree().paused \
		and not _navigation.is_open()
	if allowed and _host_scene.has_method("is_adventure_toolbar_blocked"):
		allowed = not bool(_host_scene.call("is_adventure_toolbar_blocked"))
	if allowed == _interactive:
		return
	_interactive = allowed
	_view.set_interaction_enabled(allowed)

## SceneTree.scene_changed can be delivered with zero or one argument across launch paths.
## Resolve the authoritative current scene after the notification, not from its payload.
func _on_scene_changed(_signal_scene: Node = null) -> void:
	_sync_scene_from_tree.call_deferred()

func _sync_scene_from_tree() -> void:
	_apply_host_scene(get_tree().current_scene)

func _apply_host_scene(scene: Node) -> void:
	_navigation.close()
	if is_instance_valid(_inventory):
		_inventory.queue_free()
	_inventory = null
	if is_instance_valid(_research):
		_research.queue_free()
	_research = null
	_host_scene = scene
	_view.reset_for_scene()
	_host_allowed = is_instance_valid(scene) and scene.is_in_group(HOST_GROUP)
	visible = _host_allowed
	_sync_input()
	_refresh()

## Same navigation entry for the menu ship and any map toolbar.
func open_map_navigation() -> bool:
	if not _host_allowed or not is_instance_valid(_host_scene):
		return false
	return _navigation.open_from(_host_scene)

func _can_open_inventory() -> bool:
	return Global.save_service != null and Global.save_service.is_current_profile_loaded() \
		and Global.adventure_inventory != null and Global.global_game_state.adventure_state != null

func _open_inventory() -> void:
	if is_instance_valid(_research):
		return
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

## The research front-end is preview-only and must not mutate player progression.
func can_open_research_preview() -> bool:
	return Features.can_open_map()

func open_research_preview() -> void:
	if _host_allowed and _interactive and can_open_research_preview():
		_open_research()

func _open_research() -> void:
	if is_instance_valid(_research):
		_research.request_close()
		return
	if is_instance_valid(_inventory) or not can_open_research_preview():
		return
	_research = Research.new()
	_research.name = "AdventureResearchWindow"
	add_child(_research)
	move_child(_view, get_child_count() - 1)
	_research.closed.connect(func(): _research = null)

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
	if not _host_allowed or not _interactive:
		return
	# Modal window blocks map and unrelated navigation; inventory remains a toggle.
	if is_instance_valid(_inventory) and feature_id != "inventory":
		return
	if is_instance_valid(_research) and feature_id != "research":
		return
	if feature_id == "map":
		if Features.can_open_map():
			open_map_navigation()
		return
	if not _hooks.has(feature_id):
		return
	var entry: Dictionary = _hooks[feature_id]
	if entry.unlock.is_valid() and entry.unlock.call() == true and entry.open.is_valid():
		entry.open.call()
