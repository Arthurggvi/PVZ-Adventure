## v8 菜单复用原生档案与音乐；冒险先展示独立地区选择，再调用既有安全入口。
extends "res://scripts/ui/start_menu/main_menu_v6.gd"

## 补偿字体字形与木牌实际牌面的视觉中心差，单位为1920×1080设计像素。
const PLAQUE_TEXT_OFFSET_Y := 10.0
## 存档名牌沿用原按钮交互，只追加可复用的悬停反馈组件。
const PLAQUE_HOVER = preload("res://scripts/ui/start_menu/plaque_hover_feedback.gd")
## 本次首次实装的地区界面，关闭时保留同一个 V8 实例。
const DESTINATION_PICKER = preload("res://scenes/adventure/AdventureDestinationPicker.tscn")
## 当前唯一弹层；场景离开时随菜单自动释放。
var _destination_picker: Control
## 打开弹层前的处理模式，关闭时原样恢复。
var _menu_process_mode: ProcessMode

## 总环境动效开关，不控制既有乌鸦、按钮和音乐。
@export var environment_fx_enabled := true:
	set(value):
		environment_fx_enabled = value
		if is_node_ready():
			_apply_environment()
## 可逆候选天空引用；关闭时恢复原版背景并停用动态云。
@export var use_clean_sky := true:
	set(value):
		use_clean_sky = value
		if is_node_ready():
			_apply_environment()

## 保持统一画布适配，隐藏旧辅助按钮，新功能台调用原有回调。
func _ready() -> void:
	super._ready()
	SoundManager.play_town_bgm()
	$ArtCanvas/Option.hide()
	Global.user_manager.signal_users_update.connect(_fit_profile_name)
	_fit_profile_name()
	_align_plaque_titles()
	# Background ownership remains reversible; only interior foliage is distorted.
	$ArtCanvas/EnvironmentFX/FoliageFX.bind_background($ArtCanvas/coastal_yard)
	# Explicit dependency injection: foreground art shares the existing wind controller.
	$ArtCanvas/ForegroundLeaves.bind_wind($ArtCanvas/EnvironmentFX/FoliageFX/Wind)
	_apply_environment()

## 只切换纹理引用，不修改原始PNG；复用现有画布与环境子场景。
func _apply_environment() -> void:
	$ArtCanvas/coastal_yard.texture = load("res://assets/adventure/environment_fx/v1/sky_cleanup_v1/backgrounds/main_menu_sky_clean_1920x1080.png" if use_clean_sky else "res://assets/adventure/main_menu/v6/background/coastal_yard.png")
	$ArtCanvas/EnvironmentFX.set_flags(environment_fx_enabled, use_clean_sky)
	$ArtCanvas/EnvironmentFX/FoliageFX.set_environment_state(environment_fx_enabled, use_clean_sky)
	$ArtCanvas/ForegroundLeaves.set_active(environment_fx_enabled)

## 仅替换原生名牌外观，保留玩家名 Label、档案按钮及事件连接。
func _layout_native_profile() -> void:
	var profile: Control = $ArtCanvas/WoodSign # 原生玩家名牌控制器。
	var name_label: Label = profile.label # 原控制器负责更新当前玩家名。
	var button: TextureButton = profile.get_node("ButtonUserUpdate") # 原生档案入口。
	for child: CanvasItem in profile.get_children(): # 隐藏旧灰条和旧装饰。
		child.hide()
	profile.position = Vector2(48, 4)
	button.position = Vector2.ZERO
	button.size = Vector2(358, 166)
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	button.texture_normal = load("res://assets/adventure/main_menu/v8/art/ui/profile_tree_sign.png")
	button.texture_hover = button.texture_normal
	button.texture_pressed = button.texture_normal
	button.texture_click_mask = null
	button.tooltip_text = ""
	button.add_child(PLAQUE_HOVER.new())
	button.show()
	name_label.reparent(button)
	name_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	name_label.position = Vector2(62, 72)
	name_label.size = Vector2(236, 74)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.label_settings = name_label.label_settings.duplicate()
	name_label.label_settings.font_color = Color("efd5a2")
	name_label.label_settings.outline_color = Color("322012")
	name_label.label_settings.outline_size = 4
	name_label.add_to_group("v8_plaque_title")

## 统一微调玩家名、主入口与功能台文字，保持原有水平/垂直居中及长姓名换行。
func _align_plaque_titles() -> void:
	for title: Label in get_tree().get_nodes_in_group("v8_plaque_title"): # 仅调整本菜单的木牌文字。
		title.position.y += PLAQUE_TEXT_OFFSET_Y

## 在原生姓名更新后调整字号，较长中文名允许换行。
func _fit_profile_name() -> void:
	var name_label: Label = $ArtCanvas/WoodSign.label # 不另存身份与姓名。
	name_label.label_settings.font_size = 24 if name_label.text.length() > 10 else 32
	_refresh_plaque_titles()

## 只改变显示文字，不改变控件禁用状态或解锁规则；保存原题名供解锁后恢复。
func _refresh_plaque_titles() -> void:
	for id: String in ["home", "ship", "research", "supply"]: # 仅处理四个场景入口，档案名和工具按钮保持原文。
		var button: BaseButton = art_canvas.get_node(id + "_button") # 已实现功能的可用状态仍由原场景决定。
		var title: Label = art_canvas.get_node(id + "_button_title") # 牌面独立文字。
		if not title.has_meta("unlocked_title"):
			title.set_meta("unlocked_title", title.text)
		title.text = "？" if button.disabled else str(title.get_meta("unlocked_title"))

## 尚未实装的家园也禁止通过旧程序入口进入。
func _on_item_button_1_pressed() -> void:
	pass

## 尚未实装的补给车也禁止通过旧程序入口进入。
func _on_item_button_3_pressed() -> void:
	pass

## Shared toolbar navigation contract: use the existing region picker rather than bypassing it.
func is_adventure_toolbar_blocked() -> bool:
	return is_instance_valid(_destination_picker)

func open_adventure_toolbar_map() -> void:
	_on_button_1_pressed()

## 正式冒险按钮只打开地区选择器；重复点击不叠加界面，也不读取或初始化进度。
func _on_button_1_pressed() -> void:
	if is_instance_valid(_destination_picker):
		return
	_destination_picker = DESTINATION_PICKER.instantiate()
	_destination_picker.close_requested.connect(_close_destination_picker)
	_destination_picker.destination_selected.connect(_enter_destination)
	_menu_process_mode = process_mode
	process_mode = Node.PROCESS_MODE_DISABLED
	get_viewport().gui_release_focus()
	add_child(_destination_picker)

## 释放唯一弹层，恢复菜单输入及出发按钮焦点；不重建菜单或更换玩家。
func _close_destination_picker() -> void:
	if not is_instance_valid(_destination_picker):
		return
	_destination_picker.hide()
	_destination_picker.queue_free()
	_destination_picker = null
	process_mode = _menu_process_mode
	$ArtCanvas/ship_button.grab_focus()

## [param destination_id] 是选择意图；只有真实已实现的僵尸岛能进入原安全入口。
func _enter_destination(destination_id: String) -> void:
	if not is_instance_valid(_destination_picker) or not _destination_picker.is_presented() \
		or not _destination_picker.can_select(destination_id):
		return
	match destination_id:
		"zombie_island":
			if not $SceneTransition.run(_open_zombie_island):
				_destination_picker.set_navigation_pending(false)

## 遮幕完成后才调用原安全入口；失败返回 false 让组件揭幕并恢复原界面。
func _open_zombie_island() -> bool:
	if not is_instance_valid(_destination_picker):
		return false
	if AdventureSession.open_adventure():
		return true
	_destination_picker.show_entry_error(AdventureSession.entry_error)
	return false

## 原入口报成功却未离场时，撤回本次会话锁并允许重试；不改进度对象或任何文件。
func _on_scene_transition_failed() -> void:
	if not is_instance_valid(_destination_picker):
		return
	AdventureSession.adventure_active = false
	_destination_picker.recover_navigation_error("僵尸岛场景加载失败，请检查工程资源后重试。")
