## Map HUD lifecycle, actual viewport anchoring, seven-slot availability and modal isolation.
extends Node

const Layout = preload("res://scripts/adventure/ui/toolbar_layout.gd")

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var bar: CanvasLayer = get_node("/root/AdventureToolbar")
	var view: AdventureToolbarView = bar.get_node("ToolbarView")
	if bar.visible or view._buttons.size() != 7 or view.get_parent() != bar:
		return _fail("Unregistered scene or seven-slot persistent layer")
	if view._available.get("inventory", false) != bar._can_open_inventory():
		return _fail("Inventory gate must reflect current profile, not outdated test assumptions")
	if view._available.get("research", false) != bar.can_open_research():
		return _fail("Research gate must reflect quest reward claim")
	for id in ["quests"]:
		if view._available.get(id, false) != bar._can_open_quests():
			return _fail("Quest gate must reflect first normal stage clear: " + id)
	for id in ["empty"]:
		if view._available.get(id, true):
			return _fail("Unregistered module became available: " + id)
	for id: String in view._icons:
		var source: Texture2D = view._icons[id].texture
		if source == null or not source.resource_path.begins_with("res://assets/adventure/ui/bottom_bar/"):
			return _fail("Missing real toolbar art: " + id)
	for path in ["res://scenes/main/01StartMenu.tscn", "res://scenes/main/01StartMenuCoastal.tscn", AdventureSession.MAP_SCENE]:
		var scene := (load(path) as PackedScene).instantiate()
		var registered := scene.is_in_group("adventure_toolbar_surface")
		scene.free()
		if not registered:
			return _fail("Real map scene missing shared toolbar contract: " + path)
	for dimensions in [Vector2(1920, 1080), Vector2(1280, 720), Vector2(800, 600), Vector2(3440, 1440)]:
		for expanded in [false, true]:
			var box: Dictionary = Layout.calculate(dimensions, expanded)
			var scale: float = box.scale
			if absf(box.handle.x + Layout.HANDLE_WIDTH * scale - dimensions.x) > 0.01 \
				or absf(box.handle.y + Layout.BAR_SIZE.y * scale - dimensions.y) > 0.01:
				return _fail("Not flush to right/bottom screen edge: " + str(dimensions))
			if expanded and (absf(box.panel.x + Layout.BAR_SIZE.x * scale - box.handle.x) > 0.01 or box.panel.x < -0.01):
				return _fail("Expanded panel clips the viewport: " + str(dimensions))
	# F6 launch emits a zero-argument scene_changed notification on some editor paths.
	bar._on_scene_changed()
	await get_tree().process_frame
	var real_menu: Control = (load("res://scenes/main/01StartMenuCoastal.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(real_menu)
	bar._apply_host_scene(real_menu)
	await get_tree().create_timer(0.10).timeout
	if not bar.visible or not bar._interactive:
		return _fail("Live V8 map entry did not show the persistent toolbar")
	real_menu._on_button_1_pressed()
	await get_tree().create_timer(0.10).timeout
	if not bar._navigation.is_open() or not bar.visible or bar._interactive:
		return _fail("The shared destination picker must block toolbar input without hiding it")
	bar._navigation.close()
	await get_tree().create_timer(0.10).timeout
	if not bar.visible or not bar._interactive:
		return _fail("Live V8 modal close did not restore toolbar input")
	real_menu.queue_free()
	await get_tree().process_frame
	var holder := Control.new()
	holder.add_to_group("adventure_toolbar_surface")
	get_tree().root.add_child(holder)
	bar._apply_host_scene(holder)
	if not bar.visible or not bar._interactive:
		return _fail("Map root did not activate toolbar")
	if view._available.get("map", false):
		bar._on_feature_pressed("map")
		await get_tree().process_frame
		if not bar._navigation.is_open() or bar._interactive:
			return _fail("Map slot cannot reopen the shared selector after a host change")
		bar._navigation.close()
		await get_tree().process_frame
		if not bar._interactive:
			return _fail("Map slot remained locked after dismissing the selector")
	var original_id := view.get_instance_id()
	if not _is_flush(view):
		return _fail("Live viewport handle does not touch right/bottom edge")
	var dispatches: Array[String] = []
	view.feature_pressed.connect(func(feature_id: String): dispatches.append(feature_id))
	view._on_pressed("empty")
	if not dispatches.is_empty():
		return _fail("Locked reserved slot dispatched")
	view._toggle()
	await get_tree().create_timer(0.33).timeout
	if not view.expanded or not view._panel.visible or absf(view._panel.position.x - view._panel_x()) > 1.0:
		return _fail("Expanded panel not correctly anchored")
	holder.process_mode = Node.PROCESS_MODE_DISABLED
	await get_tree().create_timer(0.07).timeout
	if not bar.visible or not bar._interactive or view._handle.disabled:
		return _fail("Map process mode incorrectly locked persistent toolbar input")
	holder.process_mode = Node.PROCESS_MODE_INHERIT
	await get_tree().create_timer(0.07).timeout
	if not bar.visible or not bar._interactive or view._handle.disabled:
		return _fail("Toolbar did not recover when modal closed")
	view._toggle()
	await get_tree().create_timer(0.33).timeout
	if view.expanded or view._panel.visible or view._panel.position.x < get_viewport().get_visible_rect().size.x - 1.0 or not _is_flush(view):
		return _fail("Collapsed toolbar leaked panel or lost right edge")
	var window_size := get_window().size
	get_window().size = Vector2i(1200, 740)
	await get_tree().create_timer(0.08).timeout
	if not _is_flush(view):
		return _fail("Viewport resize lost right edge")
	get_window().size = window_size
	await get_tree().process_frame
	var non_map := Control.new()
	get_tree().root.add_child(non_map)
	bar._apply_host_scene(non_map)
	if bar.visible:
		return _fail("Non-map gameplay scene incorrectly shows toolbar")
	bar._apply_host_scene(holder)
	if not bar.visible or view.get_instance_id() != original_id:
		return _fail("Toolbar was re-created or failed to return after map switch")
	# Actual regional map, no saving: selecting the current region must close, not disable navigation.
	var previous_progress: RefCounted = AdventureSession.progress
	var previous_active: bool = AdventureSession.adventure_active
	AdventureSession.progress = load("res://scripts/adventure/island_progress.gd").new(
		Global.global_game_state.adventure_state)
	var actual_map: Control = (load(AdventureSession.MAP_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child(actual_map)
	get_tree().current_scene = actual_map
	bar._apply_host_scene(actual_map)
	await get_tree().create_timer(0.4).timeout
	bar._on_feature_pressed("map")
	await get_tree().create_timer(0.6).timeout
	if not bar._navigation.is_open():
		return _fail("Actual zombie-island map did not open the shared picker")
	bar._navigation._navigate("zombie_island")
	await get_tree().process_frame
	if bar._navigation.is_open() or get_tree().current_scene != actual_map or not bar._interactive:
		return _fail("Selecting the current map must dismiss the picker without replacing scene")
	bar._on_feature_pressed("map")
	await get_tree().process_frame
	if not bar._navigation.is_open():
		return _fail("Map slot failed to reopen after a map selection")
	bar._navigation.close()
	get_tree().current_scene = self
	actual_map.queue_free()
	AdventureSession.progress = previous_progress
	AdventureSession.adventure_active = previous_active
	print("TOOLBAR_SMOKE_PASS: current-region route, reopen, persistent HUD and modal input")
	holder.queue_free()
	non_map.queue_free()
	get_tree().quit(0)

func _is_flush(view: AdventureToolbarView) -> bool:
	var dimensions := get_viewport().get_visible_rect().size
	return absf(view._handle.position.x + view._handle.size.x * view._handle.scale.x - dimensions.x) <= 1.0 \
		and absf(view._handle.position.y + view._handle.size.y * view._handle.scale.y - dimensions.y) <= 1.0

func _fail(reason: String) -> void:
	push_error("TOOLBAR_SMOKE_FAIL: " + reason)
	get_tree().quit(2)
