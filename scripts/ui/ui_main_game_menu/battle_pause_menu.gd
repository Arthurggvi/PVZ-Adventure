## 战斗暂停菜单，提供继续、重开、退出及本局可访问的音量调节。
extends TextureRect
class_name BattlePauseMenu

## 当前战斗的提示弹窗，用于避免抢占暂停键。
@export var dialog: Dialog


## 按当前玩法设置退出文案，并接入原有按钮音效。
func _ready() -> void:
	if AdventureSession.owns_battle(Global.main_game.game_para):
		$Actions/ExitButton/Label.text = "返回地图"
	SoundManager.setup_ui_main_game_sound(self)


## [param event] 为战斗空格键时切换暂停菜单，独立弹窗打开时交还输入。
func _input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"ShortcutKeys_Pause", true, true):
		return
	var game: MainGameManager = Global.main_game # 仅当前正式战斗接管空格。
	if not is_instance_valid(game) or get_tree().current_scene != game \
		or game.main_game_progress != MainGameManager.E_MainGameProgress.MAIN_GAME:
		return
	if (is_instance_valid(dialog) and dialog.visible) or PVZCheat.is_open():
		return
	if not visible and get_tree().paused:
		return
	get_viewport().set_input_as_handled()
	if not event.is_echo():
		_set_menu_open(not visible)


## 等待按钮按下动画后打开菜单。
func appear_menu() -> void:
	await get_tree().create_timer(0.1).timeout
	_set_menu_open(true)

## 等待按钮按下动画后返回游戏。
func return_button_pressed() -> void:
	await get_tree().create_timer(0.1).timeout
	_set_menu_open(false)

## [param is_open] 同步菜单显示与菜单暂停因素，保留其他暂停因素。
func _set_menu_open(is_open: bool) -> void:
	if visible == is_open:
		return
	visible = is_open
	SoundManager.play_other_SFX("pause")
	if is_open:
		TreePauseManager.start_tree_pause(TreePauseManager.E_PauseFactor.Menu)
	else:
		TreePauseManager.end_tree_pause(TreePauseManager.E_PauseFactor.Menu)

## 冒险通过会话重开当前阶段；原版仍重置轮间存档并重载关卡。
func restart_battle() -> void:
	var game: MainGameManager = Global.main_game # 当前暂停菜单所属的战斗。
	if AdventureSession.owns_battle(game.game_para):
		if not AdventureSession.restart_battle(game.game_para):
			push_error(AdventureSession.error_message)
		return

	EventBus.push_event("change_is_mouse_visibel_on_hammer", true)
	game.re_main_game()
	TreePauseManager.end_tree_pause_clear_all_pause_factors()
	Global.time_scale = 1.0
	Engine.time_scale = Global.time_scale
	get_tree().reload_current_scene()


## 冒险战斗返回地图，原版模式返回主菜单。
func return_main_menu() -> void:
	# 冒险内的退出返回世界地图，不触发胜利或原版保存。
	if AdventureSession.owns_battle(Global.main_game.game_para):
		AdventureSession.abandon_battle()
		return
	EventBus.push_event("change_is_mouse_visibel_on_hammer", true)
	TreePauseManager.end_tree_pause_clear_all_pause_factors()
	Global.time_scale = 1.0
	Engine.time_scale = Global.time_scale
	get_tree().change_scene_to_file(Global.main_scene_registry.MainScenesMap[MainSceneRegistry.MainScenes.StartMenu])

