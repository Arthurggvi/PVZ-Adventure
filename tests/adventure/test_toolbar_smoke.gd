## Short targeted smoke test; never writes player files or launches a battle.
extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var bar: CanvasLayer = get_node("/root/AdventureToolbar")
	var view: AdventureToolbarView = bar.get_node("ToolbarView")
	if bar.visible or view._buttons.size() != 7:
		_fail("Non-map screen visibility or count")
		return
	if view._available.get("quests", true) or view._available.get("inventory", true) \
		or view._available.get("research", true):
		_fail("Not-implemented screen is unlocked")
		return
	for id: String in view._icons:
		var image: Texture2D = view._icons[id].texture
		if image == null or not image.resource_path.begins_with("res://assets/adventure/ui/bottom_bar/"):
			_fail("Source PNG not loaded: " + id)
			return
	for idx in [2, 3, 4]:
		var feature: Dictionary = AdventureToolbarFeatures.ENTRIES[idx]
		view._on_hover(feature.id, idx)
		if not view._tip_text.text.contains(feature.label):
			_fail("Missing Chinese hover label: " + feature.id)
			return
		view._off_hover(feature.id)
	var dispatches: Array[String] = []
	view.feature_pressed.connect(func(feature_id: String): dispatches.append(feature_id))
	view._on_pressed("inventory")
	if not dispatches.is_empty():
		_fail("Locked button dispatched a click")
		return
	for scene_path in ["res://scenes/main/01StartMenuV8.tscn", "res://scenes/adventure/zombie_island.tscn"]:
		var packed := load(scene_path) as PackedScene
		var preview_scene := packed.instantiate()
		if not preview_scene.is_in_group("adventure_toolbar_surface"):
			_fail("Missing real scene toolbar group: " + scene_path)
			preview_scene.free()
			return
		preview_scene.free()
	var holder := Control.new()
	holder.add_to_group("adventure_toolbar_surface")
	get_tree().root.add_child(holder)
	bar._on_scene_changed(holder)
	if not bar.visible:
		_fail("Reusable map group is ignored")
		return
	view._toggle()
	await get_tree().create_timer(0.35).timeout
	if not view.expanded or view._panel.position.x > get_viewport().get_visible_rect().size.x:
		_fail("Right-to-left expansion")
		return
	holder.process_mode = Node.PROCESS_MODE_DISABLED
	await get_tree().create_timer(0.06).timeout
	if bar.visible:
		_fail("Disabled modal host leaked toolbar")
		return
	holder.process_mode = Node.PROCESS_MODE_INHERIT
	await get_tree().create_timer(0.06).timeout
	if not bar.visible:
		_fail("Toolbar failed to recover")
		return
	view._toggle()
	await get_tree().create_timer(0.35).timeout
	if view.expanded:
		_fail("Collapse state")
		return
	print("TOOLBAR_SMOKE_PASS 7 slots, locked gates, map group, modal isolation, expand/collapse")
	holder.queue_free()
	get_tree().quit(0)

func _fail(reason: String) -> void:
	push_error("TOOLBAR_SMOKE_FAIL: " + reason)
	get_tree().quit(2)
