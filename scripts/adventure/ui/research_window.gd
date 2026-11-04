## Research visuals only: one window, three tabs and read-only preview selection.
## Never calls progression, material consumption, crafting or save APIs.
extends Control
class_name AdventureResearchWindow

signal closed

const Builder = preload("res://scripts/adventure/ui/research_panel_skin.gd")
const Preview = preload("res://scripts/adventure/ui/research_preview_data.gd")
const View = preload("res://scripts/adventure/ui/research_panel_view.gd")

var mode := "craft"
var choice := 0
var ui: Dictionary = {}
var _closing := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui = Builder.build(self)
	resized.connect(_fit)
	_fit()
	_render()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.18)

func _fit() -> void:
	if ui.is_empty() or size.x <= 0 or size.y <= 0:
		return
	var canvas: Control = ui.canvas
	var scale_factor: float = minf(size.x / Builder.DESIGN.x,
		size.y / Builder.DESIGN.y) * 0.8
	canvas.scale = Vector2.ONE * scale_factor
	canvas.position = (size - Builder.DESIGN * scale_factor) * 0.5

func choose_mode(value: String) -> void:
	if _closing or not Preview.MODES.has(value) or mode == value:
		return
	mode = value
	choice = 0
	_render()

func choose_entry(index: int) -> void:
	if _closing or index < 0 or index >= Preview.records(mode).size():
		return
	choice = index
	_render()

func _render() -> void:
	for key: String in ui.tabs:
		var tab: TextureButton = ui.tabs[key]
		tab.texture_normal = Builder.Art.texture(
			"tabs/tab_selected.png" if key == mode else "tabs/tab_normal.png")
	ui.action_text.text = Preview.title(mode)
	ui.status.text = "美术预览模式 · %s功能尚未接入，不消耗资源" % Preview.title(mode)
	ui.coin.text = "金币：—"
	if Global.global_game_state != null:
		ui.coin.text = "金币：" + str(Global.global_game_state.coin_value)
	View.render(self, ui.content, mode, choice)

func _input(event: InputEvent) -> void:
	if _closing or not is_visible_in_tree():
		return
	if event.is_action_pressed(&"ui_cancel"):
		request_close()
		get_viewport().set_input_as_handled()

func request_close() -> void:
	if _closing:
		return
	_closing = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fade := create_tween()
	fade.tween_property(self, "modulate:a", 0.0, 0.15)
	fade.finished.connect(func():
		closed.emit()
		queue_free())
