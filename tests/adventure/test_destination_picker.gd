## 地区选择真实输入、导航与存档验收；仅允许隔离测试目录，不输出截图。
extends "res://tests/adventure/test_island_flow.gd"

## 覆盖绕过选择器、锁定误入、开关写盘和路由覆档这些实际回归。
func _run() -> void:
	assert(OS.get_user_data_dir().contains("picker-test-user"), "必须隔离 APPDATA")
	assert(ResourceLoader.exists("res://scenes/adventure/AdventureDestinationPicker.tscn"), "首次开发：地区选择场景尚未建立")
	get_tree().change_scene_to_file("res://scenes/main/01StartMenuV8.tscn")
	await _frames()
	Global.save_service.stop_autosave()
	assert(get_tree().current_scene.has_node("SceneTransition"), "场景切换遮幕尚未接入")
	# 原生创建和选择玩家后记录身份与完整全局存档基线。
	var menu: Control = get_tree().current_scene # 关闭后必须保留的同一菜单。
	var username := "picker-%s" % Time.get_ticks_usec() # 唯一隔离玩家。
	menu.user.panel_create_new_user.line_edit.text = username
	menu.user.panel_create_new_user.button_ok.pressed.emit()
	_select_user(username)
	Global.save_service.save_now()
	var path := "user://%s/adventure/zombie_island_v1.json" % username # 废弃格式哨兵：新流程不得再写此文件。
	var native_path := "user://%s/GlobalSaveGame.json" % username # 原全局文件。
	var native_bytes := FileAccess.get_file_as_bytes(native_path) # 原存档不可被导航重写。
	var identity_bytes := FileAccess.get_file_as_bytes("user://current_user.ini") # 原生身份不可变化。
	var player := SoundManager.bgm_play # 既有唯一音乐播放器。
	var town := player.stream # 相同曲目应连续播放。
	await get_tree().create_timer(0.2).timeout
	var before := player.get_playback_position() # 首次打开前的播放位置。
	# 旧入口可能返回成功却没有真正离场，遮幕必须自行恢复，不能永久黑屏。
	var transition: Node = menu.get_node("SceneTransition") # 真实可复用组件，不替换场景路由或存档服务。
	assert(transition.run(func() -> bool: return true))
	assert(not transition.run(func() -> bool: return true))
	await get_tree().create_timer(transition.cover_seconds + transition.reveal_seconds + 0.15).timeout
	assert(not transition.busy and not transition.curtain.visible, "成功返回却未切场景时必须揭幕恢复")
	# 快速取消可打断入场；动画期间的程序选择同样不能抢跑或创建进度。
	menu.get_node("ArtCanvas/ship_button").pressed.emit()
	var opening: Control = menu.get_node("AdventureDestinationPicker") # 尚未展开的纸图。
	assert(opening.is_animating() and not opening.is_presented())
	opening._select_destination("zombie_island")
	opening.destination_selected.emit("zombie_island")
	assert(not FileAccess.file_exists(path) and not AdventureSession.adventure_active)
	await get_tree().create_timer(0.06).timeout
	assert(opening.get_node("MotionRoot").modulate.a > 0.0 and opening.get_node("MotionRoot").modulate.a < 1.0)
	get_tree().root.size = Vector2i(1280, 720)
	var cancel := InputEventKey.new() # 在真正入场中发送 ESC，随后重复关闭仍只退场一次。
	cancel.keycode = KEY_ESCAPE
	cancel.pressed = true
	Input.parse_input_event(cancel)
	opening._close()
	cancel = cancel.duplicate()
	cancel.pressed = false
	Input.parse_input_event(cancel)
	await _frames()
	assert(not menu.has_node("AdventureDestinationPicker"))
	assert(not FileAccess.file_exists(path))
	get_tree().root.size = Vector2i(1066, 600)
	for cycle: int in range(2): # X、ESC各验证一次，并检查单实例和重复信号。
		await _mouse_click(menu.get_node("ArtCanvas/ship_button"))
		menu.get_node("ArtCanvas/ship_button").pressed.emit()
		await _frames()
		var cycle_picker: Control = menu.get_node("AdventureDestinationPicker") # 本次打开的独立场景。
		assert(cycle_picker.has_node("ModalMotion"), "纸图开关动效尚未接入")
		assert(cycle_picker.is_presented() and not cycle_picker.is_animating())
		assert(cycle_picker.get_node("MotionRoot").scale == Vector2.ONE)
		assert(cycle_picker.get_node("MotionRoot").position == Vector2.ZERO)
		assert(is_equal_approx(cycle_picker.get_node("MotionRoot").modulate.a, 1.0))
		assert(get_tree().current_scene == menu and not AdventureSession.adventure_active)
		assert(not FileAccess.file_exists(path) and AdventureSession.progress == null)
		assert(cycle_picker.get_signal_connection_list("destination_selected").size() == 1)
		var cycle_island: TextureButton = cycle_picker.get_node("MotionRoot/DesignCanvas/Cards/zombie_island") # 唯一开放卡片。
		var locked: TextureButton = cycle_picker.get_node("MotionRoot/DesignCanvas/Cards/town") # 始终锁定的未来地区。
		assert(cycle_island.has_focus() and not cycle_island.disabled)
		assert(locked.disabled and locked.focus_mode == Control.FOCUS_NONE)
		assert(locked.get_node("DisabledOverlay").visible)
		assert(cycle_island.position == Vector2(1090, 682) and cycle_island.size == Vector2(304, 184))
		assert(locked.position == Vector2(808, 447) and locked.size == Vector2(304, 184))
		assert(cycle_island.get_node("NameBounds/NameLabel").text == "僵尸岛")
		assert(cycle_island.get_node("NameBounds/NameLabel").horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER)
		assert(cycle_island.get_node("NameBounds/NameLabel").vertical_alignment == VERTICAL_ALIGNMENT_CENTER)
		assert(cycle_island.get_node("NameBounds").get_rect() == Rect2(58, 143, 188, 32))
		assert(cycle_island.get_node("NameBounds/NameLabel").get_global_rect().get_center().is_equal_approx(cycle_island.get_node("NameBounds").get_global_rect().get_center()))
		await _key(KEY_TAB)
		assert(cycle_picker.get_node("MotionRoot/DesignCanvas/Close").has_focus())
		await _key(KEY_TAB)
		assert(cycle_island.has_focus())
		if cycle == 0:
			# 模拟旧入口已置会话锁但没有离场；必须解除界面和会话锁，错误能关闭后重试。
			cycle_picker.set_navigation_pending(true)
			AdventureSession.adventure_active = true
			assert(transition.run(func() -> bool: return true))
			await _frames()
			assert(not AdventureSession.adventure_active and not cycle_picker.get_node("InputShield").visible)
			assert(cycle_picker.get_node("EntryError").visible)
			cycle_picker.get_node("EntryError").hide()
		for dimensions: Vector2i in [Vector2i(1920,1080), Vector2i(1280,720), Vector2i(1066,600), Vector2i(1024,768)]: # 验证真实窗口的安全区。
			get_tree().root.size = dimensions
			await _frames()
			var canvas: Control = cycle_picker.get_node("MotionRoot/DesignCanvas") # 所有层共用一个等比变换。
			assert(is_equal_approx(canvas.scale.x, canvas.scale.y))
			for item: Control in [cycle_picker.get_node("MotionRoot/DesignCanvas/Paper"), cycle_island, locked, cycle_picker.get_node("MotionRoot/DesignCanvas/Close")]: # 完整矩形包括边框。
				assert(cycle_picker.get_global_rect().encloses(item.get_global_rect()))
		get_tree().root.size = Vector2i(1066, 600)
		await _frames()
		await _mouse_click(menu.get_node("ArtCanvas/options_button"))
		assert(AdventureToolbar.modal_for("settings") == null)
		await _mouse_click(locked)
		get_viewport().gui_release_focus()
		locked.grab_focus()
		for key: int in [KEY_ENTER, KEY_SPACE]: # 键盘确认不能聚焦或进入城镇。
			await _key(key)
		await _joy_accept()
		cycle_picker.destination_selected.emit("town") # 路由边界也拒绝伪造的锁定选择。
		assert(get_tree().current_scene == menu and not AdventureSession.adventure_active)
		assert(not FileAccess.file_exists(path))
		if cycle == 0:
			await _mouse_click(cycle_picker.get_node("MotionRoot/DesignCanvas/Close"))
		else:
			await _key(KEY_ESCAPE)
		await _frames()
		assert(not menu.has_node("AdventureDestinationPicker"))
		assert(menu.get_node("ArtCanvas/ship_button").has_focus())
		assert(Global.user_manager.curr_user_name == username)
		assert(FileAccess.get_file_as_bytes(native_path) == native_bytes)
		assert(FileAccess.get_file_as_bytes("user://current_user.ini") == identity_bytes)
		assert(player == SoundManager.bgm_play and player.stream == town and player.get_playback_position() >= before)
	# 鼠标真实悬停、按下层和释放进入首次地图；之前不能初始化。
	menu.get_node("ArtCanvas/ship_button").pressed.emit()
	await _frames()
	var picker: Control = menu.get_node("AdventureDestinationPicker") # 首次实际进入的选择器。
	var island: TextureButton = picker.get_node("MotionRoot/DesignCanvas/Cards/zombie_island") # 开放地区卡片。
	await _mouse_click(island)
	await _frames()
	assert(get_tree().current_scene.scene_file_path == AdventureSession.MAP_SCENE)
	assert(AdventureSession.progress.started and FileAccess.file_exists(native_path) and not FileAccess.file_exists(path))
	assert(get_tree().current_scene.canvas.has_node("Intro"))
	get_tree().current_scene.canvas.get_node("Intro")._finish()
	assert(AdventureSession.progress.record_victory()) # 仅在测试中模拟已通关状态。
	assert(Global.save_service.save_now())
	var saved := FileAccess.get_file_as_bytes(native_path) # 已赠卡、已解锁的字节基线。
	get_tree().current_scene._return_menu()
	await _frames()
	menu = get_tree().current_scene
	menu.get_node("ArtCanvas/ship_button").pressed.emit()
	await _frames()
	picker = menu.get_node("AdventureDestinationPicker")
	island = picker.get_node("MotionRoot/DesignCanvas/Cards/zombie_island")
	island.grab_focus()
	await _key(KEY_ENTER)
	await _frames()
	assert(get_tree().current_scene.scene_file_path == AdventureSession.MAP_SCENE)
	assert(AdventureSession.is_unlocked(2) and not get_tree().current_scene.canvas.has_node("Intro"))
	assert(FileAccess.get_file_as_bytes(native_path) == saved)
	assert(FileAccess.get_file_as_bytes(native_path) != native_bytes)
	assert(player.stream == town and player.get_playback_position() >= before)
	# 旧独立文件已废弃；地区选择器不负责数据迁移或旧档恢复。
	assert(not FileAccess.file_exists(path))
	print("PASS: modal interruption/resize/input lock, scene fade/rollback, picker real inputs, locked routes, X/ESC cycles, four viewport bounds, first/existing unified saves, native bytes and continuous town BGM")
	get_tree().quit()

## 向 [param button] 中心发送真实鼠标输入并检查开放卡片状态层。
func _mouse_click(button: BaseButton) -> void:
	var motion := InputEventMouseMotion.new() # 触发真实 hover 状态。
	motion.position = button.get_global_rect().get_center()
	Input.parse_input_event(motion)
	await _frames()
	var down := InputEventMouseButton.new() # 按下再释放触发按钮。
	down.position = motion.position
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	Input.parse_input_event(down)
	await _frames()
	if button.name == &"zombie_island":
		assert(button.is_hovered() and button.is_pressed())
		assert(button.get_node("ActiveState").texture.resource_path.ends_with("island_pressed.png"))
	down = down.duplicate()
	down.pressed = false
	Input.parse_input_event(down)
	await _frames()

## [param code] 是真实键码，交给 Godot GUI 路由确认与取消。
func _key(code: int) -> void:
	var event := InputEventKey.new() # 每次独立的键盘按下/释放事件。
	event.keycode = code as Key
	event.pressed = true
	Input.parse_input_event(event)
	await _frames()
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await _frames()

## 手柄确认使用现有 ui_accept 默认绑定，不为生产逻辑增加测试开关。
func _joy_accept() -> void:
	var event := InputEventJoypadButton.new() # 默认手柄 A 按键。
	event.button_index = JOY_BUTTON_A
	event.pressed = true
	Input.parse_input_event(event)
	await _frames()
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await _frames()
