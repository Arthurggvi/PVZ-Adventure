## 主菜单、工具栏与战斗共用的游戏设置窗口，实时应用并保存现有玩家配置。
extends Control
class_name GameSettingsWindow

## 关闭动画完成后通知宿主释放窗口引用。
signal closed

## 木框、纸面与按钮复用现有面板素材。
const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")
## 以统一尺寸布局，随视口等比缩放。
const DESIGN := Vector2(720.0, 450.0)
## 高级页的显示名与 ConfigService 现有属性对应，沿用其信号及持久化字段。
const GAMEPLAY_OPTIONS := {
	&"disappear_spare_card_Placeholder": "隐藏未选植物卡槽",
	&"display_plant_HP_label": "显示植物血量",
	&"display_zombie_HP_label": "显示僵尸血量",
	&"card_slot_top_mouse_focus": "焦点卡槽自动置顶",
	&"fog_is_static": "静态浓雾",
	&"plant_be_shovel_front": "预铲除植物置顶",
	&"open_all_level": "开放所有关卡",
	&"track_bullet_mouse": "追踪子弹跟随鼠标",
}
## 承载缩放布局的统一面板。
var _panel: Control
## 避免在关闭动画期间重复处理关闭请求。
var _closing := false

## 构建共用外框和设置页，默认显示音量和窗口模式。
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new() # 遮暗下方界面，由窗口根节点拦截输入。
	shade.color = Color(0.035, 0.045, 0.025, 0.72)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = Control.new()
	_panel.name = "Panel"
	_panel.size = DESIGN
	add_child(_panel)
	Art.panel(_panel, "panels/wood_ninepatch.png", Vector2.ZERO, DESIGN, 35)
	Art.panel(_panel, "panels/outer_frame_ninepatch.png", Vector2.ZERO, DESIGN, 35)
	Art.panel(_panel, "panels/parchment_ninepatch.png", Vector2(30, 108), Vector2(660, 300), 30)
	Art.image(_panel, "res://assets/adventure/ui/bottom_bar/icons/icon_settings.png", Vector2(28, 22), Vector2(66, 66))
	Art.label(_panel, "设置", Vector2(110, 24), Vector2(320, 64), 39, Color("ffe8b0"))
	Art.button(_panel, "controls/close", Vector2(627, 22), Vector2(67, 67), request_close)
	var general := Control.new() # 常规页和高级页共用纸面及外框。
	general.name = "General"
	general.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(general)
	_add_audio_slider(general, "背景音乐", "BGM", 150.0)
	_add_audio_slider(general, "游戏音效", "SFX", 220.0)
	_add_toggle(general, "游戏全屏", Vector2(67, 290),
		DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, _set_fullscreen)

	var advanced := Control.new() # 同一窗口中的战斗与显示偏好。
	advanced.name = "Advanced"
	advanced.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(advanced)
	advanced.hide()
	var index := 0 # 每列四个开关，按定义顺序从左列排到右列。
	for key: StringName in GAMEPLAY_OPTIONS: # 属性名直接交给现有配置服务。
		var pos := Vector2(67 + 310 * floori(index / 4.0), 137 + 53 * (index % 4)) # 开关在当前页的位置。
		_add_toggle(advanced, GAMEPLAY_OPTIONS[key], pos, bool(Global.config_service.get(key)), _set_gameplay_option.bind(key))
		index += 1
	var page_button := Art.action_button(_panel, "高级选项", "buttons/action_neutral", Vector2(488, 346), Vector2(155, 46), Callable()) # 在同一窗口切换设置页。
	page_button.name = "PageButton"
	page_button.pressed.connect(func() -> void:
		advanced.visible = not advanced.visible
		general.visible = not advanced.visible
		page_button.text = "常规设置" if advanced.visible else "高级选项"
	)
	resized.connect(_fit)
	_fit()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.15)

## 在 [param page] 的 [param y] 处添加 [param caption]，使用 [param bus_name] 对应的音频总线。
func _add_audio_slider(page: Control, caption: String, bus_name: String, y: float) -> void:
	var bus: int = AudioServer.get_bus_index(bus_name) # 配置仍由游戏已有的音频总线管理。
	if bus < 0:
		push_warning("Settings: audio bus missing: " + bus_name)
		return
	Art.label(page, caption, Vector2(67, y), Vector2(200, 45), 25)
	var slider := HSlider.new() # 调节总线的线性音量。
	slider.name = bus_name
	slider.position = Vector2(255, y + 7)
	slider.size = Vector2(290, 36)
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = clampf(SoundManager.get_volum(bus), 0.0, 1.0)
	page.add_child(slider)
	var percent := Art.label(page, "%d%%" % int(round(slider.value * 100.0)), Vector2(560, y), Vector2(95, 45), 24) # 显示总线当前百分比。
	percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slider.value_changed.connect(func(value: float) -> void:
		SoundManager.set_volume(bus, value)
		Global.config_service.save_config()
		percent.text = "%d%%" % int(round(value * 100.0))
	)

## 在 [param page] 的 [param pos] 放置 [param caption]，用 [param enabled] 初始化后连接 [param on_toggled]。
func _add_toggle(page: Control, caption: String, pos: Vector2, enabled: bool, on_toggled: Callable) -> void:
	var toggle := CheckBox.new() # 标签与勾选区共同响应鼠标和键盘。
	toggle.text = caption
	toggle.position = pos
	toggle.add_theme_font_size_override("font_size", 23)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]: # 纸面上的文字使用相同深色。
		toggle.add_theme_color_override(state, Color("382719"))
	toggle.button_pressed = enabled
	toggle.toggled.connect(on_toggled)
	page.add_child(toggle)

## 根据 [param enabled] 切换当前窗口模式，沿用全屏仅作用于当前运行的行为。
func _set_fullscreen(enabled: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED)

## 将 [param enabled] 写入 [param key] 对应的配置属性并保存到当前档案。
func _set_gameplay_option(enabled: bool, key: StringName) -> void:
	Global.config_service.set(key, enabled)
	Global.config_service.save_config()

## 视口变化时维持面板居中和等比缩放。
func _fit() -> void:
	var factor: float = maxf(0.1, minf((size.x - 48.0) / DESIGN.x, (size.y - 48.0) / DESIGN.y)) # 预留视口边距。
	_panel.scale = Vector2.ONE * factor
	_panel.position = (size - DESIGN * factor) * 0.5

## [param event] 为取消操作时只关闭当前设置窗口。
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and not _closing:
		request_close()
		get_viewport().set_input_as_handled()

## 关闭窗口并在淡出结束后释放实例。
func request_close() -> void:
	if _closing:
		return
	_closing = true
	var fade := create_tween() # 宿主收到通知前保持模态阻挡。
	fade.tween_property(self, "modulate:a", 0.0, 0.13)
	fade.tween_callback(func() -> void:
		closed.emit()
		queue_free()
	)
