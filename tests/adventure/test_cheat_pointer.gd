## Temporary real-pointer hit test: console button and underlying game button.
extends Node

func _ready() -> void:
	call_deferred("_check")

func _check() -> void:
	var scene: Control = (load("res://scenes/main/01StartMenuV8.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	var game_button := Button.new()
	game_button.text = "Game interaction probe"
	game_button.position = Vector2(14, 300)
	game_button.size = Vector2(190, 55)
	scene.add_child(game_button)
	var clicks: Array[int] = []
	game_button.pressed.connect(func(): clicks.append(1))
	await get_tree().create_timer(0.9).timeout
	var old_key := InputEventKey.new()
	old_key.keycode = KEY_F9
	old_key.pressed = true
	get_viewport().push_input(old_key, true)
	await get_tree().process_frame
	assert(not PVZCheat.is_open(), "F9 must remain unbound")
	var tab_key := InputEventKey.new()
	tab_key.physical_keycode = KEY_TAB
	tab_key.pressed = true
	get_viewport().push_input(tab_key, true)
	var shortcut := InputEventKey.new()
	shortcut.physical_keycode = KEY_O
	shortcut.pressed = true
	get_viewport().push_input(shortcut,true)
	await get_tree().create_timer(0.15).timeout
	var win: Control = PVZCheat.implementation.window
	assert(PVZCheat.is_open() and win.visible and win.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	var panel: Control = win.get_node("CheatConsolePanel")
	print("Tab+O_HIT visible=",win.visible," panel=",panel.get_global_rect()," game=",game_button.get_global_rect())
	await _click(game_button.get_global_rect().get_center())
	var hovered := get_viewport().gui_get_hovered_control()
	print("Tab+O_HIT game_pressed=",clicks.size()," hovered=", str(hovered.name) if hovered != null else "none")
	assert(clicks.size() == 1,"Game-side click must pass through non-modal debug root")
	var tab: Button = win._tab_buttons["items"]
	await _click(tab.get_global_rect().get_center())
	print("Tab+O_HIT tab_selected=",win._section)
	assert(win._section == "items","Cheat tab must be clickable at first Tab+O")
	PVZCheat.toggle()
	assert(not PVZCheat.is_open())
	print("Tab+O_HIT_PASS first-open panel clicks + live game pass-through")
	get_tree().quit(0)

func _click(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	get_viewport().push_input(motion,true)
	await get_tree().process_frame
	var press := InputEventMouseButton.new()
	press.position = position
	press.global_position = position
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	get_viewport().push_input(press,true)
	press.pressed = false
	get_viewport().push_input(press,true)
	await get_tree().process_frame
