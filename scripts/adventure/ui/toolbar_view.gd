## Reusable right-anchored toolbar view. State and navigation live in the controller.
extends Control
class_name AdventureToolbarView

signal feature_pressed(feature_id: String)

const Features = preload("res://scripts/adventure/ui/toolbar_features.gd")
const SlotSkin = preload("res://scripts/adventure/ui/toolbar_slot_skin.gd")
const Layout = preload("res://scripts/adventure/ui/toolbar_layout.gd")
## 与角色面板共享深棕色悬停提示。
const HoverTip = preload("res://scripts/adventure/ui/hover_tip_skin.gd")
const LOCKED_SHADER := preload("res://shaders/adventure/toolbar_locked.gdshader")
var expanded := false
var _panel: Control
var _handle: Button
var _tip: PanelContainer
var _tip_text: Label
var _icons: Dictionary = {}
var _buttons: Dictionary = {}
var _available: Dictionary = {}
var _anim: Tween
var _hover_id := ""
var _interactive := true
var _locked_materials: Dictionary = {}
## 各按钮当前的悬停缩放动画，状态变为不可用时立即终止。
var _hover_tweens: Dictionary = {}
## 任务可领奖时的独立高亮层，不与悬停缩放共用补间。
var _quest_badge: Label
## 可领取提示的呼吸动画，关闭提示时立即回收。
var _quest_pulse: Tween
## 当前是否显示可领奖提示，避免每次刷新重复启动动画。
var _quest_attention := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_panel()
	_build_handle()
	_build_quest_badge()
	get_viewport().size_changed.connect(_place)
	_place()

func _build_panel() -> void:
	_panel = Control.new()
	_panel.name = "SlidePanel"
	_panel.size = Layout.BAR_SIZE
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = expanded
	add_child(_panel)
	var backdrop := TextureRect.new()
	backdrop.size = _panel.size
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	backdrop.texture = SlotSkin.asset("bg/toolbar_normal.png")
	if backdrop.texture == null:
		backdrop.texture = load("res://assets/adventure/main_menu/v8/art/ui/utility_console_body.png")
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(backdrop)
	for i in Features.ENTRIES.size():
		_add_slot(Features.ENTRIES[i], i)
	_tip = HoverTip.panel()
	_tip.visible = false
	_tip.size = Vector2(170, 56)
	_panel.add_child(_tip)
	_tip_text = Label.new()
	_tip_text.custom_minimum_size = Vector2(160, 48)
	_tip_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tip_text.add_theme_font_size_override("font_size", 22)
	_tip_text.add_theme_color_override("font_color", HoverTip.TEXT_COLOR)
	_tip.add_child(_tip_text)

func _add_slot(entry: Dictionary, index: int) -> void:
	var slot: Dictionary = SlotSkin.make_slot(
		_panel, entry, index, _on_hover, _off_hover, _on_pressed)
	_icons[entry.id] = slot.icon
	_buttons[entry.id] = slot.button

func _build_handle() -> void:
	_handle = Button.new()
	_handle.name = "ExpandHandle"
	_handle.size = Vector2(Layout.HANDLE_WIDTH, Layout.BAR_SIZE.y)
	_handle.flat = true
	_handle.expand_icon = true
	_handle.focus_mode = Control.FOCUS_NONE
	_handle.pressed.connect(_toggle)
	_handle.button_down.connect(func(): _handle.icon = SlotSkin.asset("handle/handle_pressed.png"))
	_handle.button_up.connect(_set_handle_image)
	_handle.mouse_entered.connect(_handle_hover)
	_handle.mouse_exited.connect(_set_handle_image)
	add_child(_handle)
	_set_handle_image()

func _set_handle_image() -> void:
	_handle.icon = SlotSkin.asset("handle/handle_expanded.png" if expanded else "handle/handle_collapsed.png")
	_handle.text = "" if _handle.icon != null else ("▶" if expanded else "◀")
	_handle.add_theme_font_size_override("font_size", 56)
	_handle.add_theme_color_override("font_color", Color("e8c47d"))

func _handle_hover() -> void:
	SoundManager.play_other_SFX(&"bleep")
	var hover_image := SlotSkin.asset("handle/handle_hover.png")
	if hover_image != null:
		_handle.icon = hover_image

func _toggle() -> void:
	if not _interactive:
		return
	expanded = not expanded
	_tip.hide()
	_hover_id = ""
	_set_handle_image()
	SoundManager.play_other_SFX(&"buttonclick")
	if is_instance_valid(_anim):
		_anim.kill()
	if expanded:
		_panel.position.x = float(Layout.calculate(get_viewport().get_visible_rect().size, false).panel.x)
		_panel.show()
	_anim = create_tween()
	_anim.tween_property(_panel, "position:x", _panel_x(), 0.26).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if not expanded:
		_anim.finished.connect(func():
			if not expanded:
				_panel.hide())

func _panel_x() -> float:
	return float(Layout.calculate(get_viewport().get_visible_rect().size, expanded).panel.x)

func _place() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var bounds: Dictionary = Layout.calculate(viewport_size, expanded)
	if is_instance_valid(_anim):
		_anim.kill()
	_panel.scale = Vector2.ONE * float(bounds.scale)
	_panel.position = bounds.panel
	_panel.visible = expanded
	_handle.scale = Vector2.ONE * float(bounds.scale)
	_handle.position = bounds.handle
## A modal can block toolbar input without hiding the persistent map HUD.
func reset_for_scene() -> void:
	if is_instance_valid(_anim):
		_anim.kill()
	expanded = false
	_panel.hide()
	_tip.hide()
	_hover_id = ""
	_set_handle_image()
	_place()

func set_interaction_enabled(enabled: bool) -> void:
	if _interactive == enabled:
		return
	_interactive = enabled
	_handle.disabled = not enabled
	for button: Button in _buttons.values():
		button.disabled = not enabled
	if not enabled:
		_tip.hide()
		_hover_id = ""

func refresh(availability: Dictionary) -> void:
	for id: String in _icons:
		var enabled: bool = availability.get(id, false) == true
		_available[id] = enabled
		var icon: TextureRect = _icons[id]
		if not enabled and not _locked_materials.has(id):
			var locked := ShaderMaterial.new()
			locked.shader = LOCKED_SHADER
			_locked_materials[id] = locked
		icon.material = null if enabled else _locked_materials[id]
		_buttons[id].mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if enabled else Control.CURSOR_ARROW
		if not enabled:
			if is_instance_valid(_hover_tweens.get(id)):
				_hover_tweens[id].kill()
			icon.scale = Vector2.ONE
			if _hover_id == id:
				_tip.hide()
				_hover_id = ""

func _on_hover(feature_id: String, index: int) -> void:
	if not _interactive or not _available.get(feature_id, false):
		return
	_hover_id = feature_id
	var name: String = Features.ENTRIES[index].label
	_tip_text.text = name
	_tip.position = Vector2(24.0 + index * 141.0, -56.0)
	_tip.show()
	_pulse(feature_id, Vector2.ONE * 1.07)
	SoundManager.play_other_SFX(&"bleep")

func _off_hover(feature_id: String) -> void:
	if _hover_id == feature_id:
		_tip.hide()
		_hover_id = ""
	if not _interactive or not _available.get(feature_id, false):
		return
	_pulse(feature_id, Vector2.ONE)

func _pulse(feature_id: String, target: Vector2) -> void:
	var icon: TextureRect = _icons[feature_id]
	if is_instance_valid(_hover_tweens.get(feature_id)):
		_hover_tweens[feature_id].kill()
	var tween := create_tween() # 同一图标只保留最新的悬停动画，避免反复进出时叠加。
	_hover_tweens[feature_id] = tween
	tween.tween_property(icon, "scale", target, 0.12).set_trans(Tween.TRANS_QUAD)

func _on_pressed(feature_id: String) -> void:
	if not _interactive or not _available.get(feature_id, false):
		return
	var bounce := create_tween()
	bounce.tween_property(_icons[feature_id], "scale", Vector2.ONE * 0.92, 0.065)
	bounce.tween_property(_icons[feature_id], "scale", Vector2.ONE, 0.13)
	SoundManager.play_other_SFX(&"tap")
	feature_pressed.emit(feature_id)

## 添加醒目的任务叹号，随任务图标定位和缩放，不拦截点击。
func _build_quest_badge() -> void:
	_quest_badge = Label.new()
	_quest_badge.text = "!"
	_quest_badge.position = Vector2(93, -8)
	_quest_badge.size = Vector2(36, 50)
	_quest_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quest_badge.add_theme_font_size_override("font_size", 44)
	_quest_badge.add_theme_color_override("font_color", Color("ffe46b"))
	_quest_badge.add_theme_color_override("font_outline_color", Color("71351c"))
	_quest_badge.add_theme_constant_override("outline_size", 9)
	_quest_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icons["quests"].add_child(_quest_badge)
	_quest_badge.hide()

## [param enabled] 由当前档案可领奖状态派生；收起工具栏时把提示延续到展开柄。
func set_quest_attention(enabled: bool) -> void:
	if _quest_attention == enabled:
		return
	_quest_attention = enabled
	_quest_badge.visible = enabled
	if is_instance_valid(_quest_pulse):
		_quest_pulse.kill()
	_icons["quests"].self_modulate = Color.WHITE
	_handle.self_modulate = Color.WHITE
	if enabled:
		_quest_pulse = create_tween().set_loops()
		_quest_pulse.tween_property(_icons["quests"], "self_modulate", Color(1.4, 1.25, 0.65), 0.65)
		_quest_pulse.parallel().tween_property(_handle, "self_modulate", Color(1.3, 1.15, 0.65), 0.65)
		_quest_pulse.tween_property(_icons["quests"], "self_modulate", Color.WHITE, 0.65)
		_quest_pulse.parallel().tween_property(_handle, "self_modulate", Color.WHITE, 0.65)

## 展开工具栏并返回 [param feature_id] 的真实按钮，教学不模拟点击。
func guide_feature(feature_id: String) -> Control:
	if not expanded:
		_toggle()
	return _buttons.get(feature_id)
