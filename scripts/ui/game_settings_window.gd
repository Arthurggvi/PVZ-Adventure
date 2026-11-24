## 工具栏的设置弹窗，提供音量、全屏和桌面快捷键。
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
## 独立的小行组件，仅扩展现有设置页的「显示」区域。
const RenderCompatibility = preload("res://scripts/ui/render_compat_settings_row.gd")
## 安卓游戏内直接导出当前玩家的原始存档，不强制依赖任何外部助手。
const SaveExport = preload("res://scripts/adventure/player/adventure_save_export.gd")
## 桌面版同样提供原始存档导出，用本机文件保存窗口选择位置。
const DesktopExportButton = preload("res://scripts/ui/desktop_save_export_button.gd")
## 仅有异常加载记录时显示的底栏复制按钮，正常设置界面完全不变。
const LoadReportButton = preload("res://scripts/ui/settings_loading_report_button.gd")
## 弹窗以基准视口像素布局，小窗口下才额外缩放。
const DESIGN := Vector2(468, 552)
## 安卓音量与显示设置页的布局尺寸，单位为视口像素。
const ANDROID_DESIGN := Vector2(468, 432)
## 纸面控件的正文色。
const INK := Color("382719")
## 标题和深色按钮的文字色。
const CREAM := Color("fff0ce")
## 纸面分组标题与操作反馈的配色。
const MUTED_INK := Color("77532e")
## 绿色提示表示等待按键或设置已应用。
const GREEN_INK := Color("48602f")
## 红棕提示表示按键冲突或保存失败。
const ERROR_INK := Color("88402d")

## 居中的弹窗本体。
var _panel: Panel
## 打开前的控件焦点，关闭时归还给仍有效的入口。
var _previous_focus: Control
## 当前淡入或淡出动画，关闭时覆盖尚未结束的淡入。
var _fade: Tween
## 避免在关闭动画期间重复处理关闭请求。
var _closing := false
## 正在等待绑定的动作，空名称表示正常浏览设置。
var _capture_action: StringName = &""
## 各战斗动作对应的键帽按钮。
var _shortcut_buttons: Dictionary[StringName, Button] = {}
## 键帽下方的操作提示与反馈。
var _shortcut_hint: Label
## 安卓导出后的状态文字，不保存额外玩家状态。
var _save_export_hint: Label

## 在全屏输入遮罩内构建设置窗，并按平台添加可用选项。
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
	var is_android := OS.has_feature("android") # 安卓与桌面共用音量和全屏操作。
	_panel.size = ANDROID_DESIGN if is_android else DESIGN
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
	close.tooltip_text = "关闭" if is_android else "关闭（Esc）"
	close.accessibility_name = "关闭设置"
	var desktop_export: Button = null # 桌面版的顶部存档按钮，与安卓的内容区按钮互斥。
	if not is_android:
		desktop_export = DesktopExportButton.new() # 只新增一个入口，不改变快捷键布局。
		desktop_export.position = Vector2(275, 11)
		desktop_export.size = Vector2(134, 29)
		_panel.add_child(desktop_export)

	var general := Panel.new() # 音频和窗口模式使用同一纸色内页。
	general.name = "General"
	general.position = Vector2(16, 54)
	general.size = Vector2(436, 324) if is_android else Vector2(436, 264)
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
	_label(general, "显示模式" if is_android else "窗口模式", Rect2(14, 145, 114, 28), 17)
	var fullscreen := _add_fullscreen_toggle(general) # 使用平台当前的全屏状态初始化。
	if is_android:
		fullscreen.position.y = 141
		fullscreen.size = Vector2(144, 36)
	var compat_divider := ColorRect.new() # 在原显示区域下方留一条轻巧分界，不新建设置页。
	compat_divider.color = Color("c9ae81")
	compat_divider.position = Vector2(14, 184)
	compat_divider.size = Vector2(408, 1)
	compat_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	general.add_child(compat_divider)
	var compatibility := RenderCompatibility.new() # ? 说明与 8 秒自测由独立组件管理。
	compatibility.position = Vector2(14, 193)
	compatibility.size = Vector2(409, 72)
	general.add_child(compatibility)
	var focus_order: Array[Control] = [music, effects, fullscreen]
	if desktop_export != null:
		focus_order.push_front(desktop_export) # Tab 从顶部导出按钮开始，保持视觉顺序。
	focus_order.append_array(compatibility.focus_controls())
	if is_android:
		focus_order.append_array(_add_save_export(general))
	if not is_android:
		focus_order.append_array(_add_shortcuts())
	if LoadReportButton.available(): # 只复用底栏空位，不增加测试页或弹窗。
		var report_button: Button = LoadReportButton.new()
		_panel.add_child(report_button)
		report_button.position = Vector2(18, _panel.size.y - 44)
		focus_order.append(report_button)
	var done := _close_button("完成", Rect2(354, _panel.size.y - 44, 98, 32)) # 设置即时应用，按钮只负责关闭。
	focus_order.append(done)
	focus_order.append(close)
	_set_focus_order(focus_order)
	if is_visible_in_tree():
		music.grab_focus()
	else:
		visibility_changed.connect(music.grab_focus, CONNECT_ONE_SHOT) # 隐藏构造完成后，真实显示时再接管键盘焦点。

	resized.connect(_fit)
	_fit()
	modulate.a = 0.0
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", 1.0, 0.12)

## 安卓导出：先提交当前存档，再保存公共下载副本并打开系统分享面板。
func _add_save_export(general: Control) -> Array[Control]:
	var send := Button.new() # 游戏设置只保留一个导出入口，不增加技术配置控件。
	send.text = "导出当前存档"
	send.position = Vector2(14, 269)
	send.size = Vector2(408, 30)
	send.theme_type_variation = &"Keycap"
	send.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	send.accessibility_name = "导出当前玩家存档文件"
	send.disabled = Global.save_service == null or not Global.save_service.is_current_profile_loaded()
	general.add_child(send)
	_save_export_hint = _label(general, "导出后可直接发给作者", Rect2(14, 301, 408, 19), 12, MUTED_INK)
	send.pressed.connect(func() -> void:
		send.disabled = true # 防止连续点击产生重叠的分享流程。
		var outcome: Dictionary = SaveExport.export_current() # 单独完成平台操作，不修改存档协议。
		_save_export_hint.text = str(outcome.get("message", "无法导出存档，请重试。"))
		_save_export_hint.add_theme_color_override("font_color", GREEN_INK if outcome.get("ok", false) else ERROR_INK)
		send.disabled = false)
	return [send]

## 构建快捷键区，返回键帽与恢复默认按钮供焦点导航。
func _add_shortcuts() -> Array[Control]:
	var page := Panel.new() # 和音频区使用一致的纸色与内边距。
	page.name = "Shortcuts"
	page.position = Vector2(16, 328)
	page.size = Vector2(436, 164)
	page.add_theme_stylebox_override("panel", _surface(Color("eddbb4"), Color("bda176"), 4))
	_panel.add_child(page)
	_label(page, "战斗快捷键", Rect2(14, 8, 128, 24), 14, MUTED_INK)
	var reset := Button.new() # 浅色次按钮与深色的完成按钮区分操作层级。
	reset.text = "恢复默认"
	reset.position = Vector2(332, 7)
	reset.size = Vector2(90, 26)
	reset.theme_type_variation = &"Keycap"
	reset.add_theme_font_size_override("font_size", 13)
	reset.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	reset.pressed.connect(_reset_shortcuts)
	page.add_child(reset)
	var shovel := _add_keycap(page, "铲子", ConfigService.SHOVEL_ACTION, 14) # 左列对应战斗栏左侧工具。
	var glove := _add_keycap(page, "手套", ConfigService.GLOVE_ACTION, 224) # 右列与左列保持同宽。
	var skill := _add_keycap(page, "角色技能", ConfigService.SKILL_ACTION, 14, 86) # 与现有工具共用键帽、改键和冲突校验。
	var battle_speed := _add_keycap(page, "二倍速", ConfigService.BATTLE_SPEED_ACTION, 224, 86) # 放在角色技能右侧。
	_shortcut_hint = _label(page, "点击键帽修改 · 字母、F1–F12、鼠标侧键，二倍速可用 Shift", Rect2(14, 132, 408, 24), 13, MUTED_INK)
	Global.config_service.tool_shortcuts_changed.connect(_refresh_shortcuts)
	_refresh_shortcuts()
	return [shovel, glove, skill, battle_speed, reset]

## 在 [param page] 的 [param x]、[param y] 坐标处添加 [param caption] 和 [param action] 键帽。
func _add_keycap(page: Control, caption: String, action: StringName, x: float, y: float = 39) -> Button:
	var tile := Panel.new() # 将工具名称与键帽放在同一张浅色卡片上。
	tile.position = Vector2(x, y)
	tile.size = Vector2(198, 40)
	tile.add_theme_stylebox_override("panel", _surface(Color("f7e9ca"), Color("d0b78b"), 4))
	page.add_child(tile)
	_label(tile, caption, Rect2(12, 0, 82, 40), 17)
	var button := Button.new() # 按下样式只在等待按键时保留。
	button.position = Vector2(99, 5)
	button.size = Vector2(92, 30)
	button.theme_type_variation = &"Keycap"
	button.toggle_mode = true
	button.accessibility_name = "绑定%s快捷键" % caption
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(_begin_shortcut_capture.bind(action))
	tile.add_child(button)
	_shortcut_buttons[action] = button
	return button

## 监听 [param action] 的新键位，再次点击同一键帽则取消。
func _begin_shortcut_capture(action: StringName) -> void:
	if _capture_action == action:
		_finish_shortcut_capture("已取消修改", MUTED_INK)
		return
	_capture_action = action
	_show_shortcut_hint("按下新键或鼠标侧键，Esc 取消", GREEN_INK)
	_refresh_shortcuts()

## 用键盘或鼠标侧键事件 [param event] 绑定当前动作，遇到非法键或冲突时继续等待。
func _capture_shortcut(event: InputEventWithModifiers) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		_finish_shortcut_capture("已取消修改", MUTED_INK)
		return
	# 键盘取物理键码，鼠标取侧键编号。
	var code: int = event.physical_keycode if event is InputEventKey else (event as InputEventMouseButton).button_index
	var invalid_key_hint := "请按单个字母、F1–F12 或鼠标侧键" # 提示当前动作可用的键。
	if _capture_action == ConfigService.BATTLE_SPEED_ACTION:
		invalid_key_hint += "，也可以按 Shift"
	if event.alt_pressed or event.ctrl_pressed or event.meta_pressed or (event.shift_pressed and code != KEY_SHIFT):
		_show_shortcut_hint(invalid_key_hint, ERROR_INK)
		return
	var result := Global.config_service.set_tool_shortcut(_capture_action, code) # 统一校验并保存当前绑定。
	match result:
		OK:
			_finish_shortcut_capture("快捷键已更新", GREEN_INK)
		ERR_ALREADY_IN_USE:
			_show_shortcut_hint("该按键已绑定另一项操作，请换一个键", ERROR_INK)
		ERR_INVALID_PARAMETER:
			_show_shortcut_hint(invalid_key_hint, ERROR_INK)
		_:
			_finish_shortcut_capture("保存失败，请重试", ERROR_INK)

## 恢复所有战斗快捷键的默认值并退出按键监听。
func _reset_shortcuts() -> void:
	if Global.config_service.reset_tool_shortcuts() == OK:
		_finish_shortcut_capture("已恢复默认快捷键", GREEN_INK)
	else:
		_finish_shortcut_capture("保存失败，请重试", ERROR_INK)

## 结束监听，并以 [param color] 显示操作结果 [param message]。
func _finish_shortcut_capture(message: String, color: Color) -> void:
	_capture_action = &""
	_show_shortcut_hint(message, color)
	_refresh_shortcuts()

## 在快捷键卡片下方用 [param color] 显示 [param message]，保持布局稳定。
func _show_shortcut_hint(message: String, color: Color) -> void:
	_shortcut_hint.text = message
	_shortcut_hint.add_theme_color_override("font_color", color)

## 刷新键帽文字与监听状态。
func _refresh_shortcuts() -> void:
	for action: StringName in _shortcut_buttons: # 每个按钮始终读取实际生效的键位。
		var button := _shortcut_buttons[action] # 当前动作的键帽。
		var listening := action == _capture_action # 只突出正在改键的动作。
		button.set_pressed_no_signal(listening)
		button.text = "按键…" if listening else Global.config_service.get_tool_shortcut_label(action)

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

## 根据 [param enabled] 切换本次运行的全屏状态；安卓由显示服务器显示或隐藏系统栏。
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
	style.set_type_variation(&"Keycap", &"Button")
	var keycap := _surface(Color("ebd5a8"), Color("b99561"), 4) # 加厚下沿来表现实体键帽。
	keycap.border_width_bottom = 2
	style.set_stylebox("normal", "Keycap", keycap)
	style.set_stylebox("hover", "Keycap", _surface(Color("fff0ce"), Color("b99561"), 4))
	var listening := _surface(Color("d9e5b7"), Color("82975b"), 4) # 绿色表示正在等待快捷键输入。
	style.set_stylebox("pressed", "Keycap", listening)
	style.set_stylebox("hover_pressed", "Keycap", listening)
	var checkbox_background := StyleBoxEmpty.new() # 复选框置于纸面上，去掉继承的深色按钮底板。
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]: # 勾选标记由原生 CheckBox 绘制。
		style.set_stylebox(state, "CheckBox", checkbox_background)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]: # 保持不同交互状态下的对比度。
		style.set_color(state, "Button", CREAM)
		style.set_color(state, "CheckBox", INK)
		style.set_color(state, "Keycap", INK)
	style.set_color("font_hover_pressed_color", "Keycap", INK)
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
	var factor := clampf(minf(available.x / _panel.size.x, available.y / _panel.size.y), 0.1, 1.0) # 大窗口不额外放大弹窗。
	_panel.scale = Vector2.ONE * factor
	_panel.position = ((size - _panel.size * factor) * 0.5).round()

## 优先捕获用于改键的 [param event]；浏览设置时取消键关闭窗口。
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _closing:
		return
	if _capture_action != &"" and (event is InputEventKey \
			or (event is InputEventMouseButton and ConfigService.is_tool_shortcut_mouse_button(event.button_index))):
		get_viewport().set_input_as_handled()
		if event.is_pressed() and not event.is_echo():
			_capture_shortcut(event as InputEventWithModifiers)
		return
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
