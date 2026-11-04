## Permanent, dependency-free bridge. Release users opt in by installing PVZ_Cheat.pck.
extends Node
const PLUGIN_SCRIPT := "res://addons/pvz_cheat/cheat_host.gd"
const RELEASE_PACK := "PVZ_Cheat.pck"
var implementation: CanvasLayer

func _ready() -> void:
	var allowed := OS.has_feature("debug")
	if not allowed:
		var path: String = OS.get_executable_path().get_base_dir().path_join(RELEASE_PACK)
		allowed = FileAccess.file_exists(path) and ProjectSettings.load_resource_pack(path)
	if not allowed:
		return
	if not ResourceLoader.exists(PLUGIN_SCRIPT):
		push_warning("Cheat pack enabled, but plugin script is missing.")
		return
	var script: Script = load(PLUGIN_SCRIPT) as Script
	if script == null:
		return
	implementation = script.new() as CanvasLayer
	if implementation == null:
		return
	implementation.enabled = true
	add_child(implementation)

func toggle() -> void:
	if is_instance_valid(implementation):
		implementation.toggle()

func set_enabled(value: bool) -> bool:
	if not is_instance_valid(implementation):
		return false
	implementation.enabled = value
	implementation.set_process_input(value)
	if not value and implementation.is_open():
		implementation.toggle()
	return true

func is_open() -> bool:
	return is_instance_valid(implementation) and implementation.is_open()
