extends Control
class_name StartMenuRoot

@onready var dialog: Dialog = $Dialog
@export var bgm:AudioStream
@onready var user: User = $User


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	AdventureSession.adventure_active = false
	$Cloud/AnimationPlayer.play("Idle")
	$BG_Right/Leaf/AnimationPlayer.play("Idle")
	$AnimationPlayer.play("Idle")

	SoundManager.setup_ui_start_menu_sound(self)
	SoundManager.play_bgm(bgm)

	Global.time_scale = 1.0
	Engine.time_scale = Global.time_scale

## 花园需要浇水
var garden_need_water:=true

## 功能未实现
func _unrealized():
	dialog.appear_dialog()

## 原冒险按钮直接打开当前玩家冒险；错误时留在菜单，不提供覆盖或重开操作。
func _on_button_1_pressed() -> void:
	if AdventureSession.open_adventure():
		return
	# 复用单个错误窗口，重复点击不会堆积弹窗。
	var error_dialog := get_node_or_null("AdventureError") as AcceptDialog
	if error_dialog == null:
		error_dialog = AcceptDialog.new()
		error_dialog.name = "AdventureError"
		error_dialog.title = "无法进入冒险"
		add_child(error_dialog)
	error_dialog.dialog_text = AdventureSession.entry_error
	error_dialog.popup_centered(Vector2i(620, 160))


## 迷你游戏
func _on_button_2_pressed() -> void:
	Global.game_para = null
	get_tree().change_scene_to_file(Global.main_scene_registry.MainScenesMap[MainSceneRegistry.MainScenes.ChooseLevelMiniGame])

## 解密模式
func _on_button_3_pressed() -> void:
	Global.game_para = null
	get_tree().change_scene_to_file(Global.main_scene_registry.MainScenesMap[MainSceneRegistry.MainScenes.ChooseLevelPuzzle])

## 生存模式
func _on_button_4_pressed() -> void:
	Global.game_para = null
	get_tree().change_scene_to_file(Global.main_scene_registry.MainScenesMap[MainSceneRegistry.MainScenes.ChooseLevelSurvival])

## 自定义关卡
func _on_custom_button_pressed() -> void:
	Global.game_para = null
	get_tree().change_scene_to_file(Global.main_scene_registry.MainScenesMap[MainSceneRegistry.MainScenes.ChooseLevelCustom])

#region 选项
func _on_option_button_1_pressed() -> void:
	$StartMenuOptionDialog.appear_menu()


func _on_option_button_2_pressed() -> void:
	$Dialog_Help.appear_dialog()

## 退出游戏
func _on_option_button_3_pressed() -> void:
	get_tree().quit()


func _on_full_screen_button_toggled(toggled_on: bool) -> void:
	if toggled_on:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
#endregion


## 花园
func _on_item_button_1_pressed() -> void:
	get_tree().change_scene_to_file(Global.main_scene_registry.MainScenesMap[MainSceneRegistry.MainScenes.Garden])

## 图鉴
func _on_item_button_2_pressed() -> void:
	get_tree().change_scene_to_file(Global.main_scene_registry.MainScenesMap[MainSceneRegistry.MainScenes.Almanac])

## 商店
func _on_item_button_3_pressed() -> void:
	get_tree().change_scene_to_file(Global.main_scene_registry.MainScenesMap[MainSceneRegistry.MainScenes.Store])

## 点击用户更新时
func _on_button_update_user_pressed() -> void:
	user.visible = true


