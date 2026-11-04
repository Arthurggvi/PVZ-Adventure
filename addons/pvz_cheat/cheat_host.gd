## Optional cheat plugin host. Only one window, managed independently of page data.
extends CanvasLayer

const CheatWindow = preload("res://addons/pvz_cheat/cheat_window.gd")
const Commands = preload("res://addons/pvz_cheat/cheat_commands.gd")

var enabled := false
var window: Control
var commands: RefCounted
var _requested_open := false
var _creating := false

func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	enabled = enabled or OS.has_feature("debug")
	set_process_input(enabled)
	commands = Commands.new()

func _input(event: InputEvent) -> void:
	if not enabled or not event is InputEventKey:
		return
	var key := event as InputEventKey
	if key.pressed and not key.echo and (key.physical_keycode == KEY_F9 or key.keycode == KEY_F9):
		toggle()
		get_viewport().set_input_as_handled()

func toggle() -> void:
	set_open(not _requested_open)

func set_open(should_open: bool) -> void:
	if should_open and not enabled:
		return
	_requested_open = should_open
	if is_instance_valid(window):
		window.call("set_presented", should_open)
		return
	if should_open and not _creating:
		_creating = true
		_create_window.call_deferred()

func _create_window() -> void:
	_creating = false
	if not _requested_open or not enabled or is_instance_valid(window):
		return
	var panel := CheatWindow.new()
	panel.name = "PVZCheatWindow"
	panel.initialize(commands)
	panel.visible = false
	add_child(panel)
	panel.close_requested.connect(set_open.bind(false))
	window = panel
	panel.set_presented(true)

func set_enabled(value: bool) -> void:
	enabled = value
	set_process_input(value)
	if not value:
		set_open(false)

func is_open() -> bool:
	return _requested_open

func _exit_tree() -> void:
	_requested_open = false
