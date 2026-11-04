## Responsive in-game modal; controls are built from modules, without a duplicate data store.
extends Control
signal close_requested
const Pages = preload("res://addons/pvz_cheat/cheat_pages.gd")
const SECTIONS := [
	{"id": "cards", "title": "植物卡牌"},
	{"id": "items", "title": "物品材料"},
	{"id": "coins", "title": "金币"},
	{"id": "stages", "title": "关卡进度"},
	{"id": "saves", "title": "存档备份"}
]
var service: RefCounted
var content: VBoxContainer
var feedback: Label
var _section := "cards"
var _tab_buttons: Dictionary = {}

func initialize(commands: RefCounted) -> void:
	service = commands

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.045, 0.035, 0.022, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var panel := PanelContainer.new()
	panel.name = "CheatConsolePanel"
	panel.anchor_left = 0.065
	panel.anchor_top = 0.07
	panel.anchor_right = 0.935
	panel.anchor_bottom = 0.93
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _style())
	add_child(panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	panel.add_child(outer)
	var top := HBoxContainer.new()
	outer.add_child(top)
	var title := Label.new()
	title.text = "PVZ · CHEAT CONSOLE"
	title.add_theme_font_size_override("font_size", 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var exit := Button.new()
	exit.text = "关闭  F9"
	exit.custom_minimum_size = Vector2(126, 42)
	exit.pressed.connect(func(): close_requested.emit())
	top.add_child(exit)
	var divider := HSeparator.new()
	outer.add_child(divider)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	outer.add_child(body)
	var tabs := VBoxContainer.new()
	tabs.custom_minimum_size = Vector2(155, 0)
	body.add_child(tabs)
	for entry: Dictionary in SECTIONS:
		var id: String = entry.id
		var tab := Button.new()
		tab.text = str(entry.title)
		tab.custom_minimum_size = Vector2(151, 44)
		tab.toggle_mode = true
		tab.pressed.connect(func(): select_section(id))
		tabs.add_child(tab)
		_tab_buttons[id] = tab
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	feedback = Label.new()
	feedback.text = "开发者功能已启用。操作会写入当前玩家存档，请先创建备份。"
	feedback.add_theme_font_size_override("font_size", 16)
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer.add_child(feedback)
	select_section(_section)

func _style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("302a22") # Keep built-in light control text readable.
	style.border_color = Color("a88243")
	style.set_border_width_all(5)
	style.set_corner_radius_all(13)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	return style

func select_section(value: String) -> void:
	if not is_instance_valid(content):
		return
	_section = value
	for key: String in _tab_buttons:
		(_tab_buttons[key] as Button).button_pressed = key == value
	for node: Node in content.get_children():
		content.remove_child(node)
		node.queue_free()
	Pages.build(content, value, service, Callable(self, "report"))

func report(result: Dictionary) -> void:
	if not is_instance_valid(feedback):
		return
	feedback.text = ("✓ " if result.get("ok", false) else "✕ ") + str(result.get("message", "操作没有返回结果。"))
	if result.get("ok", false) and result.get("navigate", false):
		close_requested.emit()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		close_requested.emit()
		get_viewport().set_input_as_handled()
