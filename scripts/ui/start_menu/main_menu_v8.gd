## v8 菜单复用原生档案与音乐；冒险先展示独立地区选择，再调用既有安全入口。
extends "res://scripts/ui/start_menu/main_menu_v6.gd"

## 补偿字体字形与木牌实际牌面的视觉中心差，单位为1920×1080设计像素。
const PLAQUE_TEXT_OFFSET_Y := 10.0
## 解锁与锁定牌匾分别使用暖金色和灰色，和按钮状态贴图对应。
const PLAQUE_UNLOCKED_COLOR := Color(0.95, 0.78, 0.45, 1.0)
## 锁定文字颜色，和禁用贴图及锁图标一起应用。
const PLAQUE_LOCKED_COLOR := Color(0.58, 0.58, 0.58, 1.0)
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
	# 用户索引先发布更新，存档随后在同一调用内加载。延后读取完整的可用状态。
	Global.user_manager.signal_users_update.connect(_sync_research_entry, Object.CONNECT_DEFERRED)
	_align_plaque_titles()
	# Background ownership remains reversible; only interior foliage is distorted.
	$ArtCanvas/EnvironmentFX/FoliageFX.bind_background($ArtCanvas/coastal_yard)
	# Explicit dependency injection: foreground art shares the existing wind controller.
	$ArtCanvas/ForegroundLeaves.bind_wind($ArtCanvas/EnvironmentFX/FoliageFX/Wind)
	_apply_environment()
	_setup_research_entry()

## 只切换纹理引用，不修改原始PNG；复用现有画布与环境子场景。
func _apply_environment() -> void:
	$ArtCanvas/coastal_yard.texture = load("res://assets/adventure/environment_fx/v1/sky_cleanup_v1/backgrounds/main_menu_sky_clean_1920x1080.png" if use_clean_sky else "res://assets/adventure/main_menu/v6/background/coastal_yard.png")
	$ArtCanvas/EnvironmentFX.set_flags(environment_fx_enabled, use_clean_sky)
	$ArtCanvas/EnvironmentFX/FoliageFX.set_environment_state(environment_fx_enabled, use_clean_sky)
	$ArtCanvas/ForegroundLeaves.set_active(environment_fx_enabled)

## 统一微调主入口与功能台文字的垂直居中。
func _align_plaque_titles() -> void:
	for title: Label in get_tree().get_nodes_in_group("v8_plaque_title"): # 仅调整本菜单的木牌文字。
		title.position.y += PLAQUE_TEXT_OFFSET_Y

## 用同一按钮状态更新牌名、字体颜色和锁图标；保留原题名供解锁时恢复。
func _refresh_plaque_states() -> void:
	for id: String in ["home", "ship", "research", "supply"]: # 仅处理四个场景入口，档案名和工具按钮保持原文。
		var button: BaseButton = art_canvas.get_node(id + "_button") # 已实现功能的可用状态仍由原场景决定。
		var title: Label = art_canvas.get_node(id + "_button_title") # 牌面独立文字。
		var locked: bool = button.disabled # 使用和按钮贴图一致的状态，不另存视觉标记。
		if not title.has_meta("unlocked_title"):
			title.set_meta("unlocked_title", title.text)
		title.text = "？" if locked else str(title.get_meta("unlocked_title"))
		title.add_theme_color_override("font_color", PLAQUE_LOCKED_COLOR if locked else PLAQUE_UNLOCKED_COLOR)
		var lock_icon: TextureRect = art_canvas.get_node_or_null(id + "_button_lock") # 冒险入口没有独立锁图标。
		if lock_icon != null:
			lock_icon.visible = locked

## 尚未实装的家园也禁止通过旧程序入口进入。
func _on_item_button_1_pressed() -> void:
	pass

## 尚未实装的补给车也禁止通过旧程序入口进入。
func _on_item_button_3_pressed() -> void:
	pass

## 研究棚入口复用工具栏的开启入口及解锁判定。
func _setup_research_entry() -> void:
	var button: TextureButton = $ArtCanvas/research_button # V8 研究棚牌匾。
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.pressed.connect(AdventureToolbar.open_research)
	Global.quests_changed.connect(_sync_research_entry)
	_sync_research_entry()

## 从当前档案的可用状态同步按钮贴图、点击反馈及牌面显示。
func _sync_research_entry() -> void:
	var button: TextureButton = $ArtCanvas/research_button # 禁用状态驱动两套原有牌匾贴图。
	button.disabled = not AdventureToolbar.can_open_research()
	button.mouse_default_cursor_shape = Control.CURSOR_ARROW if button.disabled else Control.CURSOR_POINTING_HAND
	_refresh_plaque_states()

## Both the ship button and the toolbar use the same persistent map navigation owner.
func _on_button_1_pressed() -> void:
	AdventureToolbar.open_map_navigation()
