## Tiny autoload entrypoint; release builds hide the console unless explicitly opted in.
extends CanvasLayer
const CheatWindow = preload("res://addons/pvz_cheat/cheat_window.gd")
const Commands = preload("res://addons/pvz_cheat/cheat_commands.gd")
var enabled := false
var window: Control
var commands: RefCounted

func _ready() -> void:
	layer = 90 # Below scene transition (100), above the regular toolbar (50).
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Loader authorizes development builds or an explicitly installed release pack.
	enabled = enabled or OS.has_feature("debug")
	set_process_input(enabled)
	commands = Commands.new()

func _input(event: InputEvent) -> void:
	if not enabled or not event is InputEventKey:
		return
	var key: InputEventKey = event as InputEventKey
	if key.pressed and not key.echo and (key.physical_keycode == KEY_F9 or key.keycode == KEY_F9):
		toggle()
		get_viewport().set_input_as_handled()

func toggle() -> void:
	if not enabled:
		return
	if is_instance_valid(window):
		window.queue_free()
		window = null
		return
	window = CheatWindow.new()
	window.name = "PVZCheatWindow"
	window.initialize(commands)
	add_child(window)
	window.close_requested.connect(toggle)

func is_open() -> bool:
	return is_instance_valid(window)
