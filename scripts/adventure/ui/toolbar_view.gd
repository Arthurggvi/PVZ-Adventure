## 可复用的右下工具栏；海滨场景可选择紧凑停靠，状态和导航仍由控制器管理。
extends Control
class_name AdventureToolbarView

## 真实功能按钮被点击时通知控制器，视图不直接打开业务窗口。
signal feature_pressed(feature_id: String)

## 共用功能标识、名称及原版图标。
const Features = preload("res://scripts/adventure/ui/toolbar_features.gd")
## 既有原生图标与命中控件工厂。
const SlotSkin = preload("res://scripts/adventure/ui/toolbar_slot_skin.gd")
## 地图和战斗原有的展开、收起几何布局。
const Layout = preload("res://scripts/adventure/ui/toolbar_layout.gd")
## 与角色面板共享深棕色悬停提示。
const HoverTip = preload("res://scripts/adventure/ui/hover_tip_skin.gd")
## 未解锁功能的既有图标灰显材质。
const LOCKED_SHADER := preload("res://shaders/adventure/toolbar_locked.gdshader")
## 海滨常驻功能顺序；保留研究室真实按钮以延续首关后的教学定位。
const COASTAL_FEATURES: Array[String] = ["player", "inventory", "quests", "research", "settings"]
## 以1920×1080设计视口计量的紧凑停靠区，含五个图标、间距与短标签。
const COASTAL_SIZE := Vector2(498, 120)
## 原图标仍为132像素，由公共父级缩成90像素，悬停动画无需改变基准。
const COASTAL_ICON_SCALE := 90.0 / 132.0
## 原版工具栏的展开状态；海滨常驻模式不修改此状态的含义。
var expanded := false
## 图标、悬停提示及当前底板的共同缩放父级。
var _panel: Control
## 原版可展开工具栏的木质底板。
var _backdrop: TextureRect
## 海滨专用的低对比暖色底板。
var _coastal_backdrop: Panel
## 海滨短标签与原始功能标识的映射。
var _coastal_labels: Dictionary = {}
## 仅显式声明 uses_coastal_dock 的宿主启用紧凑表现。
var _coastal_presentation := false
## 原版工具栏的展开柄，海滨模式隐藏并禁用。
var _handle: Button
## 共用悬停提示容器。
var _tip: PanelContainer
## 当前悬停功能的完整名称。
var _tip_text: Label
## 功能标识到既有插画图标的映射。
var _icons: Dictionary = {}
## 功能标识到真实命中按钮的映射。
var _buttons: Dictionary = {}
## 控制器提供的实时解锁状态，不在视图中推导业务条件。
var _available: Dictionary = {}
## 原版工具栏的横向展开补间。
var _anim: Tween
## 当前悬停功能，用于清理提示与动画。
var _hover_id := ""
## 宿主和模态窗口共同决定的输入开关。
var _interactive := true
## 各图标独立的灰显材质，避免共享状态污染。
var _locked_materials: Dictionary = {}
## 各按钮当前的悬停缩放动画，状态变为不可用时立即终止。
var _hover_tweens: Dictionary = {}
## 任务可领奖时的独立高亮层，不与悬停缩放共用补间。
var _quest_badge: Label
## 可领取提示的呼吸动画，关闭提示时立即回收。
var _quest_pulse: Tween
## 当前是否显示可领奖提示，避免每次刷新重复启动动画。
var _quest_attention := false

## 创建共用图标后应用当前表现；初次入树和之后切场使用同一布局入口。
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_panel()
	_build_handle()
	_build_quest_badge()
	_apply_presentation()
	get_viewport().size_changed.connect(_place)
	_place()

## 创建原版底板、海滨底板与共用功能节点，只有当前表现对应的底板可见。
func _build_panel() -> void:
	_panel = Control.new()
	_panel.name = "SlidePanel"
	_panel.size = Layout.BAR_SIZE
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = expanded
	add_child(_panel)
	_backdrop = TextureRect.new()
	_backdrop.size = _panel.size
	_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	_backdrop.texture = SlotSkin.asset("bg/toolbar_normal.png")
	if _backdrop.texture == null:
		_backdrop.texture = load("res://assets/adventure/main_menu/v8/art/ui/utility_console_body.png")
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_backdrop)
	_build_coastal_backdrop()
	for i in Features.ENTRIES.size(): # 原版顺序保留，紧凑模式只改局部位置和可见性。
		_add_slot(Features.ENTRIES[i], i)
	_build_coastal_labels()
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

## 创建海滨专用底板；在图标之前加入，间隙区域阻止点穿到背景入口。
func _build_coastal_backdrop() -> void:
	_coastal_backdrop = Panel.new()
	_coastal_backdrop.name = "CoastalDockBackdrop"
	_coastal_backdrop.size = COASTAL_SIZE / COASTAL_ICON_SCALE
	_coastal_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new() # 暖黑低透明底只托住图标，不继续横跨中央营地。
	style.bg_color = Color(0.075, 0.064, 0.045, 0.72)
	style.border_color = Color(0.60, 0.47, 0.28, 0.45)
	style.set_border_width_all(1)
	style.set_corner_radius_all(22)
	_coastal_backdrop.add_theme_stylebox_override("panel", style)
	_panel.add_child(_coastal_backdrop)

## 海滨短标签随公共父级缩放，22像素字号最终约为15设计像素。
func _build_coastal_labels() -> void:
	for entry: Dictionary in Features.ENTRIES: # 标签仍采用同一份功能元数据。
		if not COASTAL_FEATURES.has(str(entry.id)):
			continue
		var label := Label.new() # 文字不捕获鼠标，点击仍落到原生功能按钮。
		label.text = str(entry.label)
		label.size = Vector2(132, 27)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 22)
		label.add_theme_color_override("font_color", Color("eadcc1"))
		label.add_theme_color_override("font_outline_color", Color("231b12"))
		label.add_theme_constant_override("outline_size", 2)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.add_child(label)
		_coastal_labels[str(entry.id)] = label

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
	if not _interactive or _coastal_presentation:
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

## 按当前视口等比定位；海滨留出24设计像素边距，其他宿主保留既有右侧展开布局。
func _place() -> void:
	var viewport_size := get_viewport().get_visible_rect().size # 全局工具栏使用视口坐标，不进入场景原画画布。
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	if is_instance_valid(_anim):
		_anim.kill()
	if _coastal_presentation:
		var factor := minf(viewport_size.x / Layout.DESIGN_SIZE.x, viewport_size.y / Layout.DESIGN_SIZE.y) # 与原工具栏共用1920×1080缩放基准。
		_panel.scale = Vector2.ONE * factor * COASTAL_ICON_SCALE
		_panel.position = viewport_size - (COASTAL_SIZE + Vector2(24, 24)) * factor
		_panel.show()
		_handle.hide()
		return
	var bounds: Dictionary = Layout.calculate(viewport_size, expanded) # 原版布局计算完全保留。
	_panel.scale = Vector2.ONE * float(bounds.scale)
	_panel.position = bounds.panel
	_panel.visible = expanded
	_handle.scale = Vector2.ONE * float(bounds.scale)
	_handle.position = bounds.handle

## [param enabled] 显式选择海滨常驻停靠；退出时恢复原图标位置、底板及展开柄。
func set_coastal_presentation(enabled: bool) -> void:
	if _coastal_presentation == enabled:
		return
	_coastal_presentation = enabled
	if not is_node_ready():
		return
	_apply_presentation()
	_place()

## 只变更显示布局与命中可见性，不改变功能解锁、窗口路由或原版展开状态。
func _apply_presentation() -> void:
	_tip.hide()
	_hover_id = ""
	_backdrop.visible = not _coastal_presentation
	_coastal_backdrop.visible = _coastal_presentation
	_panel.size = COASTAL_SIZE / COASTAL_ICON_SCALE if _coastal_presentation else Layout.BAR_SIZE
	_handle.visible = not _coastal_presentation
	_handle.disabled = not _interactive or _coastal_presentation
	_handle.mouse_filter = Control.MOUSE_FILTER_IGNORE if _coastal_presentation else Control.MOUSE_FILTER_STOP
	for index: int in Features.ENTRIES.size(): # 保存原始节点和回调，只根据当前表现重新摆放。
		var feature_id: String = Features.ENTRIES[index].id # 共用功能标识。
		var coastal_index: int = COASTAL_FEATURES.find(feature_id) # -1表示由海滨场景自身提供的重复入口。
		var shown: bool = not _coastal_presentation or coastal_index >= 0 # 隐藏入口同时移除命中，不能留下透明按钮。
		var icon: TextureRect = _icons[feature_id] # 原132像素插画及其子级继续复用。
		var button: Button = _buttons[feature_id] # 原生功能按钮，保持既有无键盘焦点设置。
		if is_instance_valid(_hover_tweens.get(feature_id)):
			_hover_tweens[feature_id].kill()
		icon.scale = Vector2.ONE
		icon.visible = shown
		button.visible = shown
		button.disabled = not _interactive or not shown
		button.mouse_filter = Control.MOUSE_FILTER_STOP if shown else Control.MOUSE_FILTER_IGNORE
		icon.position = Vector2(45.0 + float(index) * 141.0, 22.0)
		if _coastal_presentation and shown:
			icon.position = Vector2(8.0 + float(coastal_index) * 98.0, 4.0) / COASTAL_ICON_SCALE
		button.position = icon.position
		# 紧凑入口的文字也属于同一按钮；离开菜单时恢复原132像素命中框。
		button.size = Vector2(132, 112.0 / COASTAL_ICON_SCALE) if _coastal_presentation and shown else Vector2(132, 132)
		if _coastal_labels.has(feature_id):
			var label: Label = _coastal_labels[feature_id] # 紧凑模式的图标下方短名称。
			label.visible = _coastal_presentation
			label.position = Vector2(icon.position.x, 96.0 / COASTAL_ICON_SCALE)
	_quest_badge.position = Vector2(93, -2) if _coastal_presentation else Vector2(93, -8)

## 每次切场都收起原版工具栏；海滨模式仍由布局保持常驻，不受展开状态影响。
func reset_for_scene() -> void:
	if is_instance_valid(_anim):
		_anim.kill()
	expanded = false
	_panel.hide()
	_tip.hide()
	_hover_id = ""
	_set_handle_image()
	_place()

## [param enabled] 由控制器的真实模态状态决定；隐藏入口始终保持禁用。
func set_interaction_enabled(enabled: bool) -> void:
	if _interactive == enabled:
		return
	_interactive = enabled
	_handle.disabled = not enabled or _coastal_presentation
	for button: Button in _buttons.values(): # 隐藏的重复入口即使恢复输入也仍保持禁用。
		button.disabled = not enabled or not button.visible
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

## [param feature_id] 仅在可见且解锁时显示提示；[param index] 仍指向共用功能元数据。
func _on_hover(feature_id: String, index: int) -> void:
	if not _interactive or not _available.get(feature_id, false) or not _buttons[feature_id].visible:
		return
	_hover_id = feature_id
	var feature_label: String = Features.ENTRIES[index].label # 悬停使用原始完整功能名称。
	_tip_text.text = feature_label
	_tip.position = Vector2(24.0 + index * 141.0, -56.0)
	if _coastal_presentation:
		var icon: TextureRect = _icons[feature_id] # 提示跟随实际紧凑位置，末端标签不超出右边缘。
		_tip.position = Vector2(clampf(icon.position.x + 66.0 - _tip.size.x * 0.5, 0.0, _panel.size.x - _tip.size.x), -_tip.size.y - 10.0)
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

## [param feature_id] 必须来自可见且允许输入的真实按钮；业务请求仍交由控制器。
func _on_pressed(feature_id: String) -> void:
	if not _interactive or not _available.get(feature_id, false) or not _buttons[feature_id].visible:
		return
	var bounce := create_tween() # 图标以单位缩放轻弹，紧凑比例由父级统一承担。
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
	if _coastal_presentation:
		return _buttons.get(feature_id) if COASTAL_FEATURES.has(feature_id) else null
	if not expanded:
		_toggle()
	return _buttons.get(feature_id)
