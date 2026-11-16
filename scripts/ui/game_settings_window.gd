## 工具栏的桌面设置弹窗，提供音量和窗口模式设置。
extends Control
class_name GameSettingsWindow

## 关闭动画完成后通知宿主释放窗口引用。
signal closed

## 复用冒险界面的木纹贴图。
const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")
## 设置首屏只动态读取标题木纹，其他样式由脚本创建。
const ResourcePaths = preload("res://scripts/adventure/ui/ui_resource_paths.gd")

## 返回设置窗口的动态美术依赖。
static func get_initial_resource_paths() -> PackedStringArray:
	return ResourcePaths.skin(PackedStringArray(["panels/wood_ninepatch.png"]))
## 与战斗暂停菜单共用的音量滑块。
const VolumeSlider = preload("res://scripts/ui/audio_volume_slider.gd")
## 弹窗以基准视口像素布局，小窗口下才额外缩放。
const DESIGN := Vector2(468, 296)
## 纸面控件的正文色。
const INK := Color("382719")
## 标题和深色按钮的文字色。
const CREAM := Color("fff0ce")

## 居中的弹窗本体。
var _panel: Panel
## 打开前的控件焦点，关闭时归还给仍有效的入口。
var _previous_focus: Control
## 当前淡入或淡出动画，关闭时覆盖尚未结束的淡入。
var _fade: Tween
## 避免在关闭动画期间重复处理关闭请求。
var _closing := false

## 在全屏输入遮罩内构建紧凑的桌面设置窗。
func _ready() -> void:
	var opener: WeakRef = get_meta("modal_opener_focus") as WeakRef if has_meta("modal_opener_focus") else null # 异步入口保存真正的打开按钮，不返回已释放的加载反馈。
	if opener != null:
		_previous_focus = opener.get_ref() as Control
	elif not has_meta("preparing_modal"):
		_previous_focus = get_viewport().gui_get_focus_owner()
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new() # 保留背景辨识度，由根节点拦截鼠标。
	shade.color = Color(0.035, 0.045, 0.025, 0.46)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_panel = Panel.new()
	_panel.name = "Panel"
	_panel.size = DESIGN
	_panel.theme = _make_theme()
	var frame := _surface(Color("34231a"), Color("a17b4e"), 7) # 细木色边框和投影保持窗口层次。
	frame.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	frame.shadow_size = 12
	frame.shadow_offset = Vector2(0, 5)
	_panel.add_theme_stylebox_override("panel", frame)
	add_child(_panel)
	Art.panel(_panel, "panels/wood_ninepatch.png", Vector2(1, 1), Vector2(DESIGN.x - 2, 54), 21).self_modulate = Color("a17d60")
	_label(_panel, "设置", Rect2(20, 10, 280, 34), 23, CREAM)
	var close := _close_button("×", Rect2(420, 11, 29, 29)) # 标题栏关闭按钮。
	close.tooltip_text = "关闭（Esc）"
	close.accessibility_name = "关闭设置"

	var general := Panel.new() # 音频和窗口模式使用同一纸色内页。
	general.name = "General"
	general.position = Vector2(16, 54)
	general.size = Vector2(436, 188)
	general.add_theme_stylebox_override("panel", _surface(Color("eddbb4"), Color("bda176"), 4))
	_panel.add_child(general)
	_label(general, "音频", Rect2(14, 9, 90, 23), 14, Color("77532e"))
	var music := _add_audio_slider(general, "背景音乐", &"BGM", 35) # 默认键盘焦点。
	var effects := _add_audio_slider(general, "游戏音效", &"SFX", 70) # 与音乐控件共用列宽。
	var divider := ColorRect.new() # 分隔音频与显示设置。
	divider.color = Color("c9ae81")
	divider.position = Vector2(14, 110)
	divider.size = Vector2(408, 1)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	general.add_child(divider)
	_label(general, "显示", Rect2(14, 119, 90, 23), 14, Color("77532e"))
	_label(general, "窗口模式", Rect2(14, 145, 114, 28), 17)
	var fullscreen := _add_fullscreen_toggle(general) # 浏览窗口模式时可用空格切换。
	var done := _close_button("完成", Rect2(354, 252, 98, 32)) # 设置即时应用，按钮只负责关闭。
	_set_focus_order([music, effects, fullscreen, done, close])
	if is_visible_in_tree():
		music.grab_focus()
	else:
		visibility_changed.connect(music.grab_focus, CONNECT_ONE_SHOT) # 隐藏构造完成后，真实显示时再接管键盘焦点。

	resized.connect(_fit)
	_fit()
	modulate.a = 0.0
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", 1.0, 0.12)

## 在 [param page] 的 [param y] 处添加 [param caption] 和对应 [param bus_name] 的滑块，并返回焦点控件。
func _add_audio_slider(page: Control, caption: String, bus_name: StringName, y: float) -> HSlider:
	_label(page, caption, Rect2(14, y, 114, 30), 17)
	var slider := VolumeSlider.new() # 调节指定总线的线性音量。
	slider.name = bus_name
	slider.bus_name = bus_name
	slider.accessibility_name = caption
	slider.position = Vector2(138, y)
	slider.size = Vector2(222, 30)
	slider.focus_mode = Control.FOCUS_ALL
	slider.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	page.add_child(slider)
	var percent := _label(page, "%d%%" % roundi(slider.value * 100.0), Rect2(366, y, 54, 30), 16) # 显示总线当前百分比。
	percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	slider.value_changed.connect(func(value: float) -> void:
		percent.text = "%d%%" % roundi(value * 100.0)
	)
	return slider

## 在 [param page] 的显示区添加全屏复选框并返回控件，初始值取实际窗口模式。
func _add_fullscreen_toggle(page: Control) -> CheckBox:
	var toggle := CheckBox.new() # 在同一个控件上绘制勾选状态和全屏标签。
	toggle.text = "全屏"
	toggle.position = Vector2(134, 145)
	toggle.size = Vector2(88, 28)
	toggle.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var mode := DisplayServer.window_get_mode() # 同时识别系统当前使用的两种全屏方式。
	toggle.button_pressed = mode in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
	toggle.toggled.connect(_set_fullscreen)
	page.add_child(toggle)
	return toggle

## 根据 [param enabled] 切换当前窗口模式，沿用全屏仅作用于当前运行的行为。
func _set_fullscreen(enabled: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED)

## 在 [param parent] 的 [param rect] 绘制 [param caption]，字号为 [param font_size]，颜色为 [param color]。
func _label(parent: Control, caption: String, rect: Rect2, font_size: int, color: Color = INK) -> Label:
	var label := Label.new() # 静态标签不参与鼠标命中。
	label.text = caption
	label.position = rect.position
	label.size = rect.size
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

## 在 [param rect] 添加文字为 [param caption] 的按钮，按下时关闭设置并返回按钮供焦点导航。
func _close_button(caption: String, rect: Rect2) -> Button:
	var button := Button.new() # 标题栏和页脚按钮沿用相同的悬停与键盘反馈。
	button.text = caption
	button.position = rect.position
	button.size = rect.size
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(request_close)
	_panel.add_child(button)
	return button

## 让 [param controls] 按视觉阅读顺序循环导航，保持焦点留在弹窗中。
func _set_focus_order(controls: Array[Control]) -> void:
	for index: int in controls.size(): # 首尾相连，支持 Tab 和 Shift+Tab。
		var control := controls[index] # 当前要连线的交互控件。
		control.focus_previous = control.get_path_to(controls[posmod(index - 1, controls.size())])
		control.focus_next = control.get_path_to(controls[(index + 1) % controls.size()])
		control.focus_neighbor_top = control.focus_previous
		control.focus_neighbor_bottom = control.focus_next
		control.focus_neighbor_left = NodePath(".")
		control.focus_neighbor_right = NodePath(".")

## 返回弹窗自己的紧凑主题，保留场景中其他控件的样式。
func _make_theme() -> Theme:
	var style := Theme.new() # 供标题栏、页脚与设置内页继承。
	var font := SystemFont.new() # 优先使用适合较小字号的桌面中文字体。
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	style.default_font = font
	style.default_font_size = 16
	style.set_stylebox("normal", "Button", _surface(Color("60412a"), Color("a17b4e"), 4))
	style.set_stylebox("hover", "Button", _surface(Color("785336"), Color("d1a469"), 4))
	style.set_stylebox("pressed", "Button", _surface(Color("48301f"), Color("a17b4e"), 4))
	var focus := _surface(Color.TRANSPARENT, Color("ba7f31"), 4) # 只画轮廓，保留控件自身内容。
	focus.set_border_width_all(2)
	style.set_stylebox("focus", "Button", focus)
	style.set_stylebox("focus", "CheckBox", focus)
	var checkbox_background := StyleBoxEmpty.new() # 复选框置于纸面上，去掉继承的深色按钮底板。
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]: # 勾选标记由原生 CheckBox 绘制。
		style.set_stylebox(state, "CheckBox", checkbox_background)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]: # 保持不同交互状态下的对比度。
		style.set_color(state, "Button", CREAM)
		style.set_color(state, "CheckBox", INK)
	style.set_stylebox("slider", "HSlider", _slider_track(Color("ae9370"), Color("876b4e")))
	style.set_stylebox("grabber_area", "HSlider", _slider_track(Color("886037"), Color("74502d")))
	style.set_stylebox("grabber_area_highlight", "HSlider", _slider_track(Color("9a6b37"), Color("74502d")))
	style.set_icon("grabber", "HSlider", _slider_thumb(Color("74502d"), Color("ae8255")))
	style.set_icon("grabber_highlight", "HSlider", _slider_thumb(Color("74502d"), Color("e1b46e")))
	return style

## 返回由 [param fill]、[param edge] 和 [param radius] 定义的低圆角样式。
func _surface(fill: Color, edge: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new() # 每一处保留独立的边框配置。
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	return style

## 以 [param fill] 和 [param edge] 生成可伸缩的六像素滑轨。
func _slider_track(fill: Color, edge: Color) -> StyleBoxFlat:
	var track := _surface(fill, edge, 2) # 保持细轨道与横向桌面滑块的比例。
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	return track

## 以 [param edge] 描边、[param fill] 填色，返回桌面滑块的矩形滑片贴图。
func _slider_thumb(edge: Color, fill: Color) -> ImageTexture:
	var thumb := Image.create(12, 18, false, Image.FORMAT_RGBA8) # 小滑片独立于滑块命中区。
	thumb.fill(edge)
	thumb.fill_rect(Rect2i(1, 1, 10, 16), fill)
	thumb.fill_rect(Rect2i(2, 2, 8, 1), fill.lightened(0.33))
	return ImageTexture.create_from_image(thumb)

## 视口变化时维持居中，在空间不足时缩小并留出边距。
func _fit() -> void:
	var available := size - Vector2(32, 32) # 基准视口像素留边。
	var factor := clampf(minf(available.x / DESIGN.x, available.y / DESIGN.y), 0.1, 1.0) # 大窗口不额外放大弹窗。
	_panel.scale = Vector2.ONE * factor
	_panel.position = ((size - DESIGN * factor) * 0.5).round()

## [param event] 为取消操作时优先关闭设置，避免焦点控件和宿主处理同一次按键。
func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		request_close()

## 关闭窗口，归还键盘焦点，并在淡出结束后释放实例。
func request_close() -> void:
	if _closing:
		return
	_closing = true
	_fade.kill()
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", 0.0, 0.10)
	_fade.tween_callback(func() -> void:
		closed.emit()
		var focus: Control = get_viewport().gui_get_focus_owner() # 更上层对话框可能已接管焦点。
		if (focus == null or is_ancestor_of(focus)) \
				and is_instance_valid(_previous_focus) and _previous_focus.is_visible_in_tree():
			_previous_focus.grab_focus()
		queue_free()
	)
