extends TextureRect
class_name MainGameMenuOptionDialog

@onready var dialog: Dialog = $"../Dialog"

@onready var music_h_slider: HSlider = $Option/VBoxContainer/Music/HSlider
@onready var sound_h_slider: HSlider = $Option/VBoxContainer/SoundEffect/HSlider
@onready var time_scale_h_slider: HSlider = $Option/VBoxContainer/TimeScale/HSlider
@onready var time_sacle_label: Label = $Option/VBoxContainer/TimeScale/Label
@onready var canvas_layer_console: CanvasLayerConsole = %CanvasLayerConsole
## 图鉴场景所在的画布层
@onready var canvas_layer_almanac: CanvasLayer = %CanvasLayerAlmanac


func _ready() -> void:
	if AdventureSession.owns_battle(Global.main_game.game_para):
		$Option/Button3/Label.text = "返回地图"
	## 为按钮添加音效
	SoundManager.setup_ui_main_game_sound(self)
	## 连接滑轨信号
	music_sound_signal(music_h_slider, AudioServer.get_bus_index("BGM"))
	music_sound_signal(sound_h_slider, AudioServer.get_bus_index("SFX"))
	time_sacle_signal(time_scale_h_slider)
	time_sacle_label.text = "倍速 " + str(Global.time_scale) + " 倍"


## [param event] 为战斗空格键时切换暂停菜单，独立弹窗打开时交还输入。
func _input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"ShortcutKeys_Pause", true, true):
		return
	var game: MainGameManager = Global.main_game # 仅当前正式战斗接管空格。
	if not is_instance_valid(game) or get_tree().current_scene != game \
		or game.main_game_progress != MainGameManager.E_MainGameProgress.MAIN_GAME:
		return
	if dialog.visible or canvas_layer_console.visible or canvas_layer_almanac.get_child_count() > 0 or PVZCheat.is_open():
		return
	if not visible and get_tree().paused:
		return
	get_viewport().set_input_as_handled()
	if not event.is_echo():
		_set_menu_open(not visible)


func music_sound_signal(h_slider: HSlider, bus_index):
	h_slider.value = SoundManager.get_volum(bus_index)
	h_slider.value_changed.connect(func (v:float):
		SoundManager.set_volume(bus_index, v)
		Global.config_service.save_config()
	)


func time_sacle_signal(h_slider: HSlider):
	h_slider.value_changed.connect(func (v:float):
		Global.time_scale = v
		time_sacle_label.text = "倍速 " + str(Global.time_scale) + " 倍"
		Engine.time_scale = Global.time_scale
		)

## 出现菜单
func appear_menu():
	await get_tree().create_timer(0.1).timeout
	_set_menu_open(true)

## 关闭菜单
func return_button_pressed():
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
func encyclopedia():
	var almance_node = load(Global.main_scene_registry.MainScenesMap[MainSceneRegistry.MainScenes.Almanac]).instantiate()
	canvas_layer_almanac.add_child(almance_node)


## 冒险通过会话重开当前阶段；原版仍重置轮间存档并重载关卡。
func resume_game() -> void:
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
func return_main_menu():
	# 冒险内的退出返回世界地图，不触发胜利或原版保存。
	if AdventureSession.owns_battle(Global.main_game.game_para):
		AdventureSession.abandon_battle()
		return
	EventBus.push_event("change_is_mouse_visibel_on_hammer", true)
	TreePauseManager.end_tree_pause_clear_all_pause_factors()
	Global.time_scale = 1.0
	Engine.time_scale = Global.time_scale
	get_tree().change_scene_to_file(Global.main_scene_registry.MainScenesMap[MainSceneRegistry.MainScenes.StartMenu])

## 功能未实现
func _unrealized():
	dialog.appear_dialog()

## 出现控制台
func _on_button_console_pressed() -> void:
	canvas_layer_console.appear_canvas_layer_control()

