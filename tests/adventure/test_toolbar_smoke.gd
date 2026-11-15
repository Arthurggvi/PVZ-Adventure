## Map HUD lifecycle, actual viewport anchoring, seven-slot availability and modal isolation.
extends Node

const Layout = preload("res://scripts/adventure/ui/toolbar_layout.gd")

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var bar: CanvasLayer = get_node("/root/AdventureToolbar") # 正式工具栏门面。
	if bar.visible or is_instance_valid(bar._view) or bar.feature_status("settings").allowed:
		return _fail("An unregistered scene must keep the presenter lazy and settings unavailable")
	for path in ["res://scenes/main/01StartMenuCoastal.tscn", AdventureSession.MAP_SCENE]:
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
	get_tree().current_scene = real_menu
	var login: User = real_menu.dialogs.selector # 地图入口要求合法的已加载档案。
	var username := "toolbar-%s" % Time.get_ticks_usec() # 隔离测试档，避免污染开发档案。
	login.panel_create_new_user.line_edit.text = username
	login.panel_create_new_user.button_ok.pressed.emit()
	assert(login.all_user_button.size() == 1)
	login.all_user_button[0].pressed.emit()
	login.texture_button_ok.pressed.emit()
	await real_menu.get_node("SceneTransition").revealed
	bar._apply_host_scene(real_menu)
	await get_tree().process_frame
	if not bar.visible or not bar._interactive:
		return _fail("Coastal menu map entry did not show the persistent toolbar")
	var view: AdventureToolbarView = bar.get_node("ToolbarView") # 注册海滨宿主后才可读取实际七槽视图。
	if view._buttons.size() != 7 or view.get_parent() != bar:
		return _fail("Wrong slot count or persistent layer parent")
	if view._available.get("inventory", false) != bar._can_open_inventory():
		return _fail("Inventory gate must reflect current profile, not outdated test assumptions")
	if view._available.get("research", false) != bar.can_open_research():
		return _fail("Research gate must reflect quest reward claim")
	for id in ["quests"]:
		if view._available.get(id, false) != bar._can_open_quests():
			return _fail("Quest gate must reflect first normal stage clear: " + id)
	if view._available.has("empty"):
		return _fail("Unexpected reserved slot")
	for id: String in view._icons:
		var source: Texture2D = view._icons[id].texture
		if source == null or not source.resource_path.begins_with("res://assets/adventure/ui/bottom_bar/"):
			return _fail("Missing real toolbar art: " + id)
	real_menu.entry_layer.controls["harbor"].activated.emit("harbor")
	await get_tree().create_timer(0.10).timeout
	if not bar._navigation.is_open() or not bar.visible or bar._interactive:
		return _fail("The shared destination picker must block toolbar input without hiding it")
	bar._navigation.close()
	await get_tree().create_timer(0.10).timeout
	if not bar.visible or not bar._interactive:
		return _fail("Coastal menu modal close did not restore toolbar input")
	get_tree().current_scene = null
	real_menu.queue_free()
	await get_tree().process_frame
	var holder := Control.new()
	holder.add_to_group("adventure_toolbar_surface")
	get_tree().root.add_child(holder)
	get_tree().current_scene = holder
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
	get_tree().current_scene = non_map
	bar._apply_host_scene(non_map)
	if bar.visible:
		return _fail("Non-map gameplay scene incorrectly shows toolbar")
	get_tree().current_scene = holder
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
	if not await _wait_for_picker(bar._navigation):
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

## [param navigation] 的请求接受与窗口就绪分离，原地区选择断言必须等待真实纸图展开。
func _wait_for_picker(navigation: Node) -> bool:
	var deadline: int = Time.get_ticks_msec() + 12000 # 保持有界等待，不绕过入场输入锁。
	while Time.get_ticks_msec() < deadline:
		var picker: Control = navigation.get_node_or_null("MapDestinationPicker") as Control # 反馈不属于选择器。
		if picker != null and picker.is_presented():
			return true
		if not navigation.is_open():
			return false
		await get_tree().process_frame
	return false

func _is_flush(view: AdventureToolbarView) -> bool:
	var dimensions := get_viewport().get_visible_rect().size
	return absf(view._handle.position.x + view._handle.size.x * view._handle.scale.x - dimensions.x) <= 1.0 \
		and absf(view._handle.position.y + view._handle.size.y * view._handle.scale.y - dimensions.y) <= 1.0

func _fail(reason: String) -> void:
	push_error("TOOLBAR_SMOKE_FAIL: " + reason)
	get_tree().quit(2)
