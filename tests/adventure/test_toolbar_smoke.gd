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
	for id in ["quests", "research", "empty"]:
		if view._available.get(id, true):
			return _fail("Unregistered module became available: " + id)
	for id: String in view._icons:
		var source: Texture2D = view._icons[id].texture
		if source == null or not source.resource_path.begins_with("res://assets/adventure/ui/bottom_bar/"):
			return _fail("Missing real toolbar art: " + id)
	for path in ["res://scenes/main/01StartMenuV8.tscn", AdventureSession.MAP_SCENE]:
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
	var real_menu: Control = (load("res://scenes/main/01StartMenuV8.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(real_menu)
	bar._on_scene_changed(real_menu)
	await get_tree().create_timer(0.10).timeout
	if not bar.visible or not bar._interactive:
		return _fail("Live V8 map entry did not show the persistent toolbar")
	real_menu._on_button_1_pressed()
	await get_tree().create_timer(0.10).timeout
	if real_menu.process_mode != Node.PROCESS_MODE_DISABLED or not bar.visible or bar._interactive:
		return _fail("Live destination picker incorrectly removed the toolbar")
	real_menu._close_destination_picker()
	await get_tree().create_timer(0.10).timeout
	if not bar.visible or not bar._interactive:
		return _fail("Live V8 modal close did not restore toolbar input")
	real_menu.queue_free()
	await get_tree().process_frame
	var holder := Control.new()
	holder.add_to_group("adventure_toolbar_surface")
	get_tree().root.add_child(holder)
	bar._on_scene_changed(holder)
	if not bar.visible or not bar._interactive:
		return _fail("Map root did not activate toolbar")
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
	if not view.expanded or absf(view._panel.position.x - view._panel_x()) > 1.0:
		return _fail("Expanded panel not correctly anchored")
	holder.process_mode = Node.PROCESS_MODE_DISABLED
	await get_tree().create_timer(0.07).timeout
	if not bar.visible or bar._interactive or not view._handle.disabled:
		return _fail("Modal input lock must not hide the map toolbar")
	view._on_pressed("map")
	if not dispatches.is_empty():
		return _fail("Disabled host dispatched navigation")
	holder.process_mode = Node.PROCESS_MODE_INHERIT
	await get_tree().create_timer(0.07).timeout
	if not bar.visible or not bar._interactive or view._handle.disabled:
		return _fail("Toolbar did not recover when modal closed")
	view._toggle()
	await get_tree().create_timer(0.33).timeout
	if view.expanded or not _is_flush(view):
		return _fail("Collapsed toolbar lost right edge")
	var window_size := get_window().size
	get_window().size = Vector2i(1200, 740)
	await get_tree().create_timer(0.08).timeout
	if not _is_flush(view):
		return _fail("Viewport resize lost right edge")
	get_window().size = window_size
	await get_tree().process_frame
	var non_map := Control.new()
	get_tree().root.add_child(non_map)
	bar._on_scene_changed(non_map)
	if bar.visible:
		return _fail("Non-map gameplay scene incorrectly shows toolbar")
	bar._on_scene_changed(holder)
	if not bar.visible or view.get_instance_id() != original_id:
		return _fail("Toolbar was re-created or failed to return after map switch")
	print("TOOLBAR_SMOKE_PASS: persistent host, modal lock, scene switch, viewport edges, 7 slots")
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
