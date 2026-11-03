## v8 只扩展菜单美术；档案、冒险与城镇音乐沿用已实现的 v6 接入。
extends "res://scripts/ui/start_menu/main_menu_v6.gd"

## 补偿字体字形与木牌实际牌面的视觉中心差，单位为1920×1080设计像素。
const PLAQUE_TEXT_OFFSET_Y := 10.0

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
	_apply_environment()

## 只切换纹理引用，不修改原始PNG；复用现有画布与环境子场景。
func _apply_environment() -> void:
	$ArtCanvas/coastal_yard.texture = load("res://assets/adventure/environment_fx/v1/sky_cleanup_v1/backgrounds/main_menu_sky_clean_1920x1080.png" if use_clean_sky else "res://assets/adventure/main_menu/v6/background/coastal_yard.png")
	$ArtCanvas/EnvironmentFX.set_flags(environment_fx_enabled, use_clean_sky)

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
	button.tooltip_text = "玩家档案：点击创建或选择"
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

## 尚未实装的家园也禁止通过旧程序入口进入。
func _on_item_button_1_pressed() -> void:
	pass

## 尚未实装的补给车也禁止通过旧程序入口进入。
func _on_item_button_3_pressed() -> void:
	pass
