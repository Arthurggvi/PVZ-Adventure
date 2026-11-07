## 冒险工具栏设置窗口：复用游戏的 BGM/SFX 总线与配置保存，不维护额外设置状态。
extends Control
class_name AdventureSettingsWindow

signal closed

const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")
const DESIGN := Vector2(720.0, 450.0)
var _panel: Control
var _closing := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.035, 0.045, 0.025, 0.72)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = Control.new()
	_panel.size = DESIGN
	add_child(_panel)
	Art.panel(_panel, "panels/wood_ninepatch.png", Vector2.ZERO, DESIGN, 35)
	Art.panel(_panel, "panels/outer_frame_ninepatch.png", Vector2.ZERO, DESIGN, 35)
	Art.panel(_panel, "panels/parchment_ninepatch.png", Vector2(30, 108), Vector2(660, 300), 30)
	Art.image(_panel, "res://assets/adventure/ui/bottom_bar/icons/icon_settings.png", Vector2(28, 22), Vector2(66, 66))
	Art.label(_panel, "设置", Vector2(110, 24), Vector2(320, 64), 39, Color("ffe8b0"))
	Art.button(_panel, "controls/close", Vector2(627, 22), Vector2(67, 67), request_close)
	_add_audio_slider("背景音乐", "BGM", 155.0)
	_add_audio_slider("游戏音效", "SFX", 275.0)
	resized.connect(_fit)
	_fit()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.15)

func _add_audio_slider(caption: String, bus_name: String, y: float) -> void:
	var bus: int = AudioServer.get_bus_index(bus_name)
	if bus < 0:
		push_warning("Settings: audio bus missing: " + bus_name)
		return
	Art.label(_panel, caption, Vector2(67, y), Vector2(200, 45), 25)
	var slider := HSlider.new()
	slider.position = Vector2(255, y + 7)
	slider.size = Vector2(290, 36)
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = clampf(SoundManager.get_volum(bus), 0.0, 1.0)
	_panel.add_child(slider)
	var percent := Art.label(_panel, "%d%%" % int(round(slider.value * 100.0)), Vector2(560, y), Vector2(95, 45), 24)
	percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slider.value_changed.connect(func(value: float) -> void:
		SoundManager.set_volume(bus, value)
		Global.config_service.save_config()
		percent.text = "%d%%" % int(round(value * 100.0))
	)

func _fit() -> void:
	var factor: float = maxf(0.1, minf((size.x - 48.0) / DESIGN.x, (size.y - 48.0) / DESIGN.y))
	_panel.scale = Vector2.ONE * factor
	_panel.position = (size - DESIGN * factor) * 0.5

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and not _closing:
		request_close()
		get_viewport().set_input_as_handled()

func request_close() -> void:
	if _closing:
		return
	_closing = true
	var fade := create_tween()
	fade.tween_property(self, "modulate:a", 0.0, 0.13)
	fade.tween_callback(func() -> void:
		closed.emit()
		queue_free()
	)
