## 地区选择真实输入、导航与存档验收；仅允许隔离测试目录，不输出截图。
extends "res://tests/adventure/test_island_flow.gd"

## 覆盖选择器输入、关窗、城镇导航和存档连续性。
func _run() -> void:
	assert(OS.get_user_data_dir().contains("picker-test-user"), "必须隔离 APPDATA")
	assert(ResourceLoader.exists("res://scenes/adventure/AdventureDestinationPicker.tscn"), "首次开发：地区选择场景尚未建立")
	get_tree().change_scene_to_file("res://scenes/main/01StartMenuCoastal.tscn")
	await _frames()
	Global.save_service.stop_autosave()
	assert(get_tree().current_scene.has_node("SceneTransition"), "场景切换遮幕尚未接入")
	# 原生创建和选择玩家后记录身份与完整全局存档基线。
	var menu: Control = get_tree().current_scene # 关闭后必须保留的同一菜单。
	var username := "picker-%s" % Time.get_ticks_usec() # 唯一隔离玩家。
	menu.dialogs.open_profiles()
	var selector := menu.dialogs.selector as User # 海滨菜单的原生档案选择器。
	selector.panel_create_new_user.line_edit.text = username
	selector.panel_create_new_user.button_ok.pressed.emit()
	for button: OneUserButton in selector.all_user_button: # 在真实档案列表中选中本次玩家。
		if button.user_name_on_curr_button == username:
			button.pressed.emit()
			break
	selector.texture_button_ok.pressed.emit()
	assert(Global.user_manager.curr_user_name == username and Global.save_service.is_current_profile_loaded())
	await _frames()
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
	menu.entry_layer.controls["harbor"].activated.emit("harbor")
	var opening := await _wait_for_picker(false) # 资源准备完成但尚未展开的纸图。
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
	assert(_destination_picker() == null)
	assert(not FileAccess.file_exists(path))
	get_tree().root.size = Vector2i(1066, 600)
	for cycle: int in range(2): # X、ESC各验证一次，并检查单实例和重复信号。
		menu.entry_layer.controls["harbor"].activated.emit("harbor")
		await _wait_for_picker()
		var cycle_picker := _destination_picker() # 本次打开的独立场景。
		assert(cycle_picker.has_node("ModalMotion"), "纸图开关动效尚未接入")
		assert(cycle_picker.is_presented() and not cycle_picker.is_animating())
		assert(cycle_picker.get_node("MotionRoot").scale == Vector2.ONE)
		assert(cycle_picker.get_node("MotionRoot").position == Vector2.ZERO)
		assert(is_equal_approx(cycle_picker.get_node("MotionRoot").modulate.a, 1.0))
		assert(get_tree().current_scene == menu and not AdventureSession.adventure_active)
		assert(not FileAccess.file_exists(path) and AdventureSession.progress == null)
		assert(cycle_picker.get_signal_connection_list("destination_selected").size() == 1)
		var cycle_island: TextureButton = cycle_picker.get_node("MotionRoot/DesignCanvas/Cards/zombie_island") # 默认焦点卡片。
		var town_card: TextureButton = cycle_picker.get_node("MotionRoot/DesignCanvas/Cards/town") # 返回海滨主菜单的卡片。
		assert(cycle_island.has_focus() and not cycle_island.disabled)
		assert(not town_card.disabled and town_card.focus_mode == Control.FOCUS_ALL)
		assert(not town_card.get_node("DisabledOverlay").visible)
		assert(cycle_island.position == Vector2(1090, 682) and cycle_island.size == Vector2(304, 184))
		assert(town_card.position == Vector2(808, 447) and town_card.size == Vector2(304, 184))
		assert(cycle_island.get_node("NameBounds/NameLabel").text == "僵尸岛")
		assert(cycle_island.get_node("NameBounds/NameLabel").horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER)
		assert(cycle_island.get_node("NameBounds/NameLabel").vertical_alignment == VERTICAL_ALIGNMENT_CENTER)
		assert(cycle_island.get_node("NameBounds").get_rect() == Rect2(58, 143, 188, 32))
		assert(cycle_island.get_node("NameBounds/NameLabel").get_global_rect().get_center().is_equal_approx(cycle_island.get_node("NameBounds").get_global_rect().get_center()))
		await _key(KEY_TAB)
		assert(town_card.has_focus())
		await _key(KEY_TAB)
		assert(cycle_picker.get_node("MotionRoot/DesignCanvas/Close").has_focus())
		await _key(KEY_TAB)
		assert(cycle_island.has_focus())
		if cycle == 0:
			# 临时移除当前档案身份，走正式僵尸岛导航的失败恢复路径。
			Global.user_manager.curr_user_name = ""
			cycle_island.pressed.emit()
			Global.user_manager.curr_user_name = username # 同步入口已拒绝；避免把错误恢复用例变成跨帧换档取消。
			await _frames()
			assert(not AdventureSession.adventure_active and not cycle_picker.get_node("InputShield").visible)
			assert(cycle_picker.get_node("EntryError").visible)
			cycle_picker.get_node("EntryError").hide()
		for dimensions: Vector2i in [Vector2i(1920,1080), Vector2i(1280,720), Vector2i(1066,600), Vector2i(1024,768)]: # 验证真实窗口的安全区。
			get_tree().root.size = dimensions
			await _frames()
			var canvas: Control = cycle_picker.get_node("MotionRoot/DesignCanvas") # 所有层共用一个等比变换。
			assert(is_equal_approx(canvas.scale.x, canvas.scale.y))
			for item: Control in [cycle_picker.get_node("MotionRoot/DesignCanvas/Paper"), cycle_island, town_card, cycle_picker.get_node("MotionRoot/DesignCanvas/Close")]: # 完整矩形包括边框。
				assert(cycle_picker.get_global_rect().encloses(item.get_global_rect()))
		get_tree().root.size = Vector2i(1066, 600)
		await _frames()
		assert(not AdventureToolbar.request_feature("settings"))
		assert(AdventureToolbar.modal_for("settings") == null)
		if cycle == 0:
			await _mouse_click(cycle_picker.get_node("MotionRoot/DesignCanvas/Close"))
		else:
			await _key(KEY_ESCAPE)
		await _frames()
		assert(_destination_picker() == null)
		assert(menu.entry_layer.controls["harbor"].input_allowed)
		assert(Global.user_manager.curr_user_name == username)
		assert(FileAccess.get_file_as_bytes(native_path) == native_bytes)
		assert(FileAccess.get_file_as_bytes("user://current_user.ini") == identity_bytes)
		assert(player == SoundManager.bgm_play and player.stream == town and player.get_playback_position() >= before)
	# 在主菜单选择城镇应收起纸图，并保留当前场景实例。
	menu.entry_layer.controls["harbor"].activated.emit("harbor")
	await _wait_for_picker()
	await _key(KEY_TAB)
	await _joy_accept()
	assert(_destination_picker() == null and get_tree().current_scene == menu)
	assert(not AdventureSession.adventure_active and AdventureSession.progress == null)
	# 鼠标真实悬停、按下层和释放进入首次地图；之前不能初始化。
	menu.entry_layer.controls["harbor"].activated.emit("harbor")
	await _wait_for_picker()
	var picker := _destination_picker() # 首次实际进入僵尸岛的选择器。
	var island: TextureButton = picker.get_node("MotionRoot/DesignCanvas/Cards/zombie_island") # 开放地区卡片。
	await _mouse_click(island)
	await _wait_for_scene(AdventureSession.MAP_SCENE)
	assert(get_tree().current_scene.scene_file_path == AdventureSession.MAP_SCENE)
	assert(AdventureSession.progress.started and FileAccess.file_exists(native_path) and not FileAccess.file_exists(path))
	assert(get_tree().current_scene.canvas.has_node("Intro"))
	get_tree().current_scene.canvas.get_node("Intro")._finish()
	await _frames()
	assert(AdventureToolbar.request_feature("map"))
	await _wait_for_picker()
	var island_picker := _destination_picker() # 从僵尸岛工具栏打开的同一纸图。
	assert(AdventureSession.progress.record_victory()) # 仅在测试中模拟已通关状态。
	Global.refresh_quests()
	assert(Global.save_service.save_now())
	var saved := FileAccess.get_file_as_bytes(native_path) # 已赠卡、已解锁的字节基线。
	await _mouse_click(island_picker.get_node("MotionRoot/DesignCanvas/Cards/town"))
	await _wait_for_scene("res://scenes/main/01StartMenuCoastal.tscn")
	menu = get_tree().current_scene
	assert(menu.scene_file_path == "res://scenes/main/01StartMenuCoastal.tscn")
	assert(_destination_picker() == null and not AdventureSession.adventure_active)
	assert(Global.user_manager.curr_user_name == username)
	assert(FileAccess.get_file_as_bytes(native_path) == saved)
	assert(FileAccess.get_file_as_bytes("user://current_user.ini") == identity_bytes)
	var prompt: Control = AdventureToolbar._onboarding._spotlight # 首关通关后的教学可选择稍后继续。
	await get_tree().process_frame
	if prompt.is_visible_in_tree():
		prompt._later.pressed.emit()
	menu.entry_layer.controls["harbor"].activated.emit("harbor")
	await _wait_for_picker()
	picker = _destination_picker()
	island = picker.get_node("MotionRoot/DesignCanvas/Cards/zombie_island")
	island.grab_focus()
	await _key(KEY_ENTER)
	await _wait_for_scene(AdventureSession.MAP_SCENE)
	assert(get_tree().current_scene.scene_file_path == AdventureSession.MAP_SCENE)
	assert(AdventureSession.is_unlocked(2) and not get_tree().current_scene.canvas.has_node("Intro"))
	assert(FileAccess.get_file_as_bytes(native_path) == saved)
	assert(FileAccess.get_file_as_bytes(native_path) != native_bytes)
	assert(player.stream == town and player.get_playback_position() >= before)
	# 旧独立文件已废弃；地区选择器不负责数据迁移或旧档恢复。
	assert(not FileAccess.file_exists(path))
	print("PASS: modal interruption/resize/input lock, scene fade/rollback, town and island routes, X/ESC cycles, four viewport bounds, first/existing unified saves, native bytes and continuous town BGM")
	get_tree().quit()

## [param presented] 为 false 时保留原入场中断验收，否则等待资源准备及既有开场动画完成。
func _wait_for_picker(presented: bool = true) -> Control:
	var deadline: int = Time.get_ticks_msec() + 12000 # 后台准备以真实窗口状态为准，不以固定帧数猜测。
	while Time.get_ticks_msec() < deadline:
		var picker: Control = _destination_picker() # 加载反馈不冒充真实地区选择器。
		if picker != null and (not presented or picker.is_presented()):
			return picker
		await get_tree().process_frame
	assert(false, "地区选择器未在资源准备后进入预期状态")
	return null

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
