## v8 分层菜单、原生档案与单播放器音乐集成验收；仅运行于隔离 APPDATA。
extends "res://tests/adventure/test_island_flow.gd"

## 通过真实场景、按钮输入、音频播放位置与持久文件检查本轮需求。
func _run() -> void:
	assert(OS.get_user_data_dir().contains("v8-test-user"))
	get_tree().change_scene_to_file("res://scenes/main/01StartMenuV8.tscn")
	await _frames()
	var menu: Control = get_tree().current_scene # 当前分层菜单。
	var username := "较长中文玩家名字甲乙丙丁-v8-%s" % Time.get_ticks_usec() # 唯一测试玩家。
	menu.user.panel_create_new_user.line_edit.text = username
	menu.user.panel_create_new_user.button_ok.pressed.emit()
	_select_user(username)
	for id: String in ["home", "research", "supply"]: # 禁用主体、牌面与文字同时灰显。
		var button: TextureButton = menu.art_canvas.get_node(id + "_button")
		assert(button.disabled and button.focus_mode == Control.FOCUS_NONE)
		assert(menu.art_canvas.get_node(id).material == null)
		assert(menu.art_canvas.get_node(id + "_button_title").get_theme_color("font_color").r < 0.7)
		var click := InputEventMouseButton.new() # 在牌面发送真实鼠标输入。
		click.position = button.get_global_rect().get_center()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		Input.parse_input_event(click)
		click = click.duplicate()
		click.pressed = false
		Input.parse_input_event(click)
		button.grab_focus()
		Input.action_press("ui_accept")
		await _frames()
		Input.action_release("ui_accept")
		assert(get_tree().current_scene == menu)
	assert(not menu.art_canvas.get_node("ship_button").disabled)
	# 原生功能回调必须保持可用；禁用建筑的旧程序入口也不允许跳场景。
	menu._on_item_button_1_pressed()
	menu._on_item_button_3_pressed()
	assert(get_tree().current_scene == menu)
	for name: String in ["options", "help"]: # 新功能台中的真实鼠标悬停、按下和释放。
		var utility: TextureButton = menu.art_canvas.get_node(name + "_button") # 当前被验收的功能台按钮。
		var motion := InputEventMouseMotion.new() # 视口中的真实悬停输入。
		motion.position = utility.get_global_rect().get_center()
		Input.parse_input_event(motion)
		await _frames()
		assert(utility.is_hovered())
		var down := InputEventMouseButton.new() # 按下后再释放以触发原回调。
		down.position = motion.position
		down.button_index = MOUSE_BUTTON_LEFT
		down.pressed = true
		Input.parse_input_event(down)
		await _frames()
		assert(utility.is_pressed())
		down = down.duplicate()
		down.pressed = false
		Input.parse_input_event(down)
		await get_tree().create_timer(0.3).timeout
		var panel: Control = menu.get_node("StartMenuOptionDialog" if name == "options" else "Dialog_Help") # 原设置或帮助面板。
		assert(panel.visible)
		if name == "options":
			panel.return_button_pressed()
		else:
			panel._on_button_pressed()
		await get_tree().create_timer(0.2).timeout
		assert(not panel.visible)
	# 精简自检仅核对单实例、正式时序与四帧资源，不等待或录制动画。
	var bird: Node2D = menu.art_canvas.get_node("CrowFlyby") # 唯一装饰实例。
	assert(bird.interval_min_seconds == 14.0 and bird.interval_max_seconds == 26.0 and bird.flap_fps == 7.0)
	for index: int in range(4): # 仅检查允许使用的四张运行帧。
		assert(ResourceLoader.exists("res://assets/adventure/main_menu/v8/art/crow/flyby/frames/fly_%02d.png" % index))
	var player := SoundManager.bgm_play # 始终是已有的唯一播放器。
	var town := player.stream # 缓存中的城镇曲目。
	assert(town.resource_path.ends_with("mus_town.wav") and player.playing)
	await get_tree().create_timer(0.5).timeout
	var before := player.get_playback_position() # 切场景前的真实播放位置。
	_enter_island_from_menu()
	await _frames()
	assert(player == SoundManager.bgm_play and player.stream == town)
	assert(player.get_playback_position() >= before)
	assert(get_tree().current_scene.canvas.has_node("Intro"))
	get_tree().current_scene.canvas.get_node("Intro")._finish()
	await _frames()
	var path: String = AdventureSession.progress.save_path # A 玩家冒险文件。
	var saved := FileAccess.get_file_as_bytes(path) # 赠卡后文件基线。
	for index: int in range(2,7): # 锁定关卡禁止鼠标和键盘触发。
		var stage: TextureButton = get_tree().current_scene.canvas.get_node("Stage%d" % index)
		assert(stage.disabled and stage.focus_mode == Control.FOCUS_NONE and stage.material != null)
	before = player.get_playback_position()
	get_tree().current_scene._return_menu()
	await _frames()
	assert(player.stream == town and player.get_playback_position() >= before)
	# 原生设置滑块继续控制原 BGM 总线，静音与总音量不会被切场景重置。
	var bus := AudioServer.get_bus_index("BGM") # 既有音乐总线。
	var master := AudioServer.get_bus_index("Master") # 既有总音量总线。
	get_tree().current_scene.get_node("StartMenuOptionDialog/Option/Music/HSlider").value = 0.3
	var volume := AudioServer.get_bus_volume_db(bus) # 滑块设置后的实际音量。
	AudioServer.set_bus_mute(bus, true)
	AudioServer.set_bus_volume_db(master, -8.0)
	Global.config_service.save_config()
	# 第二玩家用原生列表创建、选择，不继承 A 的卡片或引导状态。
	menu = get_tree().current_scene
	menu.user.panel_create_new_user.line_edit.text = username + "-b"
	menu.user.panel_create_new_user.button_ok.pressed.emit()
	_select_user(username + "-b")
	_enter_island_from_menu()
	await _frames()
	assert(AdventureSession.progress.cards.is_empty() and not AdventureSession.progress.intro_completed)
	get_tree().current_scene._return_menu()
	await _frames()
	_select_user(username)
	_enter_island_from_menu()
	await _frames()
	assert(FileAccess.get_file_as_bytes(path) == saved)
	assert(not get_tree().current_scene.canvas.has_node("Intro"))
	assert(AudioServer.is_bus_mute(bus) and is_equal_approx(AudioServer.get_bus_volume_db(bus), volume))
	assert(is_equal_approx(AudioServer.get_bus_volume_db(master), -8.0))
	AudioServer.set_bus_mute(bus, false)
	print("PASS: v8 callbacks, disabled entries, native profiles, shared town music and volume")
	# 最后通过新功能台的退出按钮实际执行既有退出回调。
	get_tree().current_scene._return_menu()
	await _frames()
	assert(get_tree().current_scene.art_canvas.get_node("CrowFlyby") != null)
	get_tree().current_scene.art_canvas.get_node("exit_button").pressed.emit()
