## No-save regression: F9 lifecycle, lazy page build and hidden input isolation.
extends Node

func _ready() -> void:
	call_deferred("_check")

func _check() -> void:
	var f9 := InputEventKey.new()
	f9.physical_keycode = KEY_F9
	f9.pressed = true
	get_viewport().push_input(f9)
	await get_tree().process_frame
	var window: Control = PVZCheat.implementation.window
	assert(is_instance_valid(window) and PVZCheat.is_open())
	assert(window.is_visible_in_tree() and window.is_processing_input())
	assert(window.content.get_child_count() == 1, "F9 must not build plant catalog eagerly")
	var original := window.get_instance_id()
	window.select_section("cards")
	assert(window.content.get_child_count() > 2)
	PVZCheat.toggle()
	assert(not PVZCheat.is_open() and not window.visible and not window.is_processing_input())
	PVZCheat.toggle()
	assert(PVZCheat.is_open() and window.get_instance_id() == original)
	assert(window.content.get_child_count() == 1)
	assert(PVZCheat.set_enabled(false))
	assert(not PVZCheat.is_open() and not window.is_processing_input())
	assert(PVZCheat.set_enabled(true))
	print("CHEAT_UI_LIFECYCLE_PASS F9, lazy modules, singleton, Esc isolation, disable")
	get_tree().quit(0)
