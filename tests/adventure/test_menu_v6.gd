## v6 分层菜单、原生档案与单播放器音乐集成验收；仅运行于隔离 APPDATA。
extends "res://tests/adventure/test_island_flow.gd"

## 通过真实场景、按钮输入、音频播放位置与持久文件检查本轮需求。
func _run() -> void:
	assert(OS.get_user_data_dir().contains("v6-test-user"))
	get_tree().change_scene_to_file("res://scenes/main/01StartMenuV6.tscn")
	await _frames()
	var menu: Control = get_tree().current_scene # 当前分层菜单。
	var username := "v6-%s" % Time.get_ticks_usec() # 唯一测试玩家。
	menu.user.panel_create_new_user.line_edit.text = username
	menu.user.panel_create_new_user.button_ok.pressed.emit()
	_select_user(username)
	for dimensions: Vector2i in [Vector2i(1920,1080), Vector2i(1280,720), Vector2i(1066,600)]: # 实际窗口尺寸。
		get_tree().root.size = dimensions
		await _frames()
		assert(is_equal_approx(menu.art_canvas.scale.x, menu.art_canvas.scale.y))
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.godot/v6-%dx%d.png" % [dimensions.x, dimensions.y])
	for id: String in ["home", "research", "supply"]: # 禁用主体、牌面与文字同时灰显。
		var button: TextureButton = menu.art_canvas.get_node(id + "_button")
		assert(button.disabled and button.focus_mode == Control.FOCUS_NONE)
		assert(menu.art_canvas.get_node(id).material != null)
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
	var player := SoundManager.bgm_play # 始终是已有的唯一播放器。
	var town := player.stream # 缓存中的城镇曲目。
	assert(town.resource_path.ends_with("mus_town.wav") and player.playing)
	await get_tree().create_timer(0.5).timeout
	var before := player.get_playback_position() # 切场景前的真实播放位置。
	menu.art_canvas.get_node("ship_button").pressed.emit()
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
	menu.art_canvas.get_node("ship_button").pressed.emit()
	await _frames()
	assert(AdventureSession.progress.cards.is_empty() and not AdventureSession.progress.intro_completed)
	get_tree().current_scene._return_menu()
	await _frames()
	_select_user(username)
	get_tree().current_scene.art_canvas.get_node("ship_button").pressed.emit()
	await _frames()
	assert(FileAccess.get_file_as_bytes(path) == saved)
	assert(not get_tree().current_scene.canvas.has_node("Intro"))
	assert(AudioServer.is_bus_mute(bus) and is_equal_approx(AudioServer.get_bus_volume_db(bus), volume))
	assert(is_equal_approx(AudioServer.get_bus_volume_db(master), -8.0))
	AudioServer.set_bus_mute(bus, false)
	AdventureSession.enter_lawn()
	await _wait_battle()
	assert(player.stream != town)
	var battle: MainGameManager = Global.main_game # 现有战斗管理器。
	Engine.time_scale = 6.0
	while battle.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME:
		battle.zombie_manager.death_all_zombie()
		await get_tree().create_timer(0.5).timeout
	for item: Node in battle.canvas_layer_temp.get_children(): # 点击真实清场奖杯。
		if item is Trophy:
			item._on_trophy_button_pressed()
	await get_tree().create_timer(6.0).timeout
	await _frames()
	assert(player.stream == town and player.playing)
	assert(AdventureSession.progress.stage_1_cleared)
	assert(get_tree().current_scene.canvas.get_node("Stage2").disabled)
	print("PASS: v6 three resolutions, disabled input, native profiles, town continuity, volume/mute, battle and victory return")
	get_tree().quit()
