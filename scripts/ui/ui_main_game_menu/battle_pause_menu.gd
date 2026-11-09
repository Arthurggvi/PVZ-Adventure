## 战斗暂停菜单，管理本局动作和倍速，并在暂停状态下打开共用设置窗口。
extends TextureRect
class_name BattlePauseMenu

## 当前战斗的提示弹窗，用于避免抢占暂停键。
@onready var dialog: Dialog = $"../Dialog"
## 当前战斗的速度控件，离开本局后由战斗流程恢复。
@onready var _speed_slider: HSlider = $Actions/TimeScale/HSlider
## 速度滑块的文字反馈。
@onready var _speed_label: Label = $Actions/TimeScale/Label
## 图鉴场景所在的画布层
@onready var canvas_layer_almanac: CanvasLayer = %CanvasLayerAlmanac
## 设置挂在战斗 UI 层，关闭后回到仍处于暂停状态的菜单。
var _settings: GameSettingsWindow


## 初始化本局动作与倍速显示。
func _ready() -> void:
	if AdventureSession.owns_battle(Global.main_game.game_para):
		$Actions/ExitButton/Label.text = "返回地图"
	SoundManager.setup_ui_main_game_sound(self)
	_speed_slider.set_value_no_signal(Global.time_scale)
	_speed_label.text = "倍速 %s 倍" % Global.time_scale
	_speed_slider.value_changed.connect(_set_battle_speed)


## [param event] 为战斗空格键时切换暂停菜单，独立弹窗打开时交还输入。
func _input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"ShortcutKeys_Pause", true, true):
		return
	var game: MainGameManager = Global.main_game # 仅当前正式战斗接管空格。
	if not is_instance_valid(game) or get_tree().current_scene != game \
		or game.main_game_progress != MainGameManager.E_MainGameProgress.MAIN_GAME:
		return
	if dialog.visible or is_instance_valid(_settings) or canvas_layer_almanac.get_child_count() > 0 or PVZCheat.is_open():
		return
	if not visible and get_tree().paused:
		return
	get_viewport().set_input_as_handled()
	if not event.is_echo():
		_set_menu_open(not visible)


## 将 [param multiplier] 应用于当前战斗，不写入玩家配置。
func _set_battle_speed(multiplier: float) -> void:
	Global.time_scale = multiplier
	_speed_label.text = "倍速 %s 倍" % multiplier
	Engine.time_scale = multiplier

## 出现菜单
func appear_menu() -> void:
	await get_tree().create_timer(0.1).timeout
	_set_menu_open(true)

## 关闭菜单
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

## 图鉴
func encyclopedia() -> void:
	var almance_node = load(Global.main_scene_registry.MainScenesMap[MainSceneRegistry.MainScenes.Almanac]).instantiate() # 在独立画布层显示图鉴。
	canvas_layer_almanac.add_child(almance_node)


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


## 返回主菜单
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

## 在战斗 UI 层打开共用设置，关闭设置时仍保留战斗暂停。
func _open_settings() -> void:
	if not visible or is_instance_valid(_settings):
		return
	var game: MainGameManager = Global.main_game # 保留锤子关卡打开菜单前的鼠标状态。
	var cursor_was_forced := game.is_mouse_visibel_on_hammer # 设置遮罩覆盖整个暂停菜单时仍需显示指针。
	_settings = GameSettingsWindow.new()
	_settings.process_mode = Node.PROCESS_MODE_ALWAYS
	_settings.closed.connect(game.change_is_mouse_visibel_on_hammer.bind(cursor_was_forced))
	game.change_is_mouse_visibel_on_hammer(true)
	if game.game_para.is_hammer:
		game.mouse_appear_have_hammer()
	# 直接挂在画布层，避免继承暂停菜单的旧主题。
	game.canvas_layer_ui.add_child(_settings)

