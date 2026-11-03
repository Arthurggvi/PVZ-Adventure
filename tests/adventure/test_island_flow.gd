## 真实场景集成验收；测试专用存档，原版刷怪与判胜不替换。
extends Node

## 状态实现，用于模拟进程重启读取同一文件。
const Progress = preload("res://scripts/adventure/island_progress.gd")
## 是否已经观察到自然生成的僵尸。
var saw_zombies := false

## 保留驱动节点，后续场景切换不释放验收协程。
func _ready() -> void:
	get_tree().current_scene = null
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 真实时间超时，断言失败也会明确以失败退出。
	get_tree().create_timer(100, true, false, true).timeout.connect(func():
		push_error("FAIL: flow timed out")
		get_tree().quit(1))
	_run.call_deferred()

## 验证菜单、对话、缩放、种植、失败、自然波次胜利及重启。
func _run() -> void:
	# 登录唯一测试用户并记录原版存档快照，确认冒险不会写入原关卡进度。
	var username := "phase1-flow-%s" % Time.get_ticks_usec()
	get_tree().change_scene_to_file("res://scenes/main/01StartMenuV8.tscn")
	await _frames()
	var native_user: User = get_tree().current_scene.user # 原生档案界面。
	native_user.panel_create_new_user.line_edit.text = username
	native_user.panel_create_new_user.button_ok.pressed.emit()
	_select_user(username)
	Global.save_service.stop_autosave()
	Global.save_service.save_now()
	Global.save_service.start_autosave(0.1)
	var original_path := "user://%s/GlobalSaveGame.json" % username # 原版文件。
	var original_bytes := FileAccess.get_file_as_bytes(original_path) # 原版字节基线。
	assert(not get_tree().current_scene.has_node("AdventureMenu"))
	get_tree().current_scene.get_node("ArtCanvas/ship_button").pressed.emit()
	var path: String = AdventureSession.progress.save_path # 新入口实际初始化的路径。
	await _frames()
	var map: Control = get_tree().current_scene # 当前地图。
	var intro: Control = map.canvas.get_node("Intro") # 首次引导。
	await _wait_intro_ready(intro)
	assert(intro.conversation.dialogue_resource.dialog_detail_list.size() == 7)
	await _screenshot("intro-1")
	for index: int in range(6): # 逐句走到最终台词，第四句检查赠卡。
		intro.conversation.request_advance()
		await get_tree().create_timer(0.9).timeout
		assert(intro.conversation.actor.speech_text_label.text == intro.conversation.dialogue_resource.dialog_detail_list[index + 1].text)
		if index == 2:
			assert(AdventureSession.progress.cards == {"sunflower": 1, "peashooter": 1})
			await _screenshot("intro-4")
	intro.conversation.request_advance()
	await intro.completed
	await _frames()
	assert(AdventureSession.progress.intro_completed)
	assert(not map.canvas.has_node("Intro"))
	assert(not AdventureSession.is_unlocked(2))
	# 改动待保存的运行态，确保自动保存若泄漏会改变文件字节。
	Global.global_game_state.coin_value += 1
	await get_tree().create_timer(0.3).timeout
	assert(FileAccess.get_file_as_bytes(original_path) == original_bytes)
	map._select_stage(2)
	assert(get_tree().current_scene == map)
	assert(map.notice_label.text.contains("通关草坪"))
	for dimensions: Vector2 in [Vector2(1280, 720), Vector2(1920, 1080), Vector2(1024, 768)]: # 同比例与留边。
		map.size = dimensions
		map._fit_canvas()
		assert(is_equal_approx(map.canvas.scale.x, map.canvas.scale.y))
		assert((map.canvas.position + map.canvas.size * map.canvas.scale / 2).is_equal_approx(dimensions / 2))
	map.size = get_viewport().get_visible_rect().size
	map._fit_canvas()
	await _screenshot("map")
	map._select_stage(1)
	await _wait_battle()
	var battle: MainGameManager = Global.main_game # 原版草坪管理器。
	assert(FileAccess.get_file_as_bytes(original_path) == original_bytes)
	assert(battle.card_manager.card_slot_battle.curr_cards.size() == 2)
	assert(not battle.is_test)
	# 无胜利依据时的伪造结算事件必须被拒绝。
	battle.win_main_game()
	assert(not AdventureSession.progress.stage_1_cleared)
	for index: int in range(2): # 走实际手持卡与格子创建、费用扣除流程。
		var card: Card = battle.card_manager.card_slot_battle.curr_cards[index]
		var cell: PlantCell = battle.plant_cell_manager.all_plant_cells[2][index]
		assert(card.is_can_click)
		battle.hand_manager._click_card(card)
		battle.hand_manager._on_cell_mouse_enter(cell)
		battle.hand_manager._on_click_cell(cell)
		await _frames()
	assert(battle.plant_cell_manager.get_cell_have_plant().size() == 2)
	assert(battle.card_manager.card_slot_battle.sun_value == 0)
	await _screenshot("battle")
	# 用原生成器创建实体，调用真实进屋入口并等待原失败演出。
	var intruder := battle.zombie_manager.create_skill_zombie(CharacterRegistry.ZombieType.Z001Norm, 0, 80)
	assert(intruder != null)
	battle.on_zombie_go_home(intruder)
	await get_tree().create_timer(6.0, true, false, true).timeout
	assert(get_tree().current_scene.scene_file_path == AdventureSession.MAP_SCENE)
	assert(not AdventureSession.progress.stage_1_cleared and not AdventureSession.is_unlocked(2))
	assert(not get_tree().paused)
	AdventureSession.enter_lawn()
	await _wait_battle()
	battle = Global.main_game
	# 加速自然十波，用原项目调试清怪入口缩短验收，不直接写胜利标记。
	Engine.time_scale = 6.0
	while battle.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME:
		if battle.zombie_manager.curr_zombie_num > 0:
			saw_zombies = true
			battle.zombie_manager.death_all_zombie()
		await get_tree().create_timer(0.5).timeout
	assert(saw_zombies and battle.zombie_manager.is_end_wave)
	assert(battle.zombie_manager.curr_zombie_num == 0)
	assert(not AdventureSession.progress.stage_1_cleared)
	var trophy: Trophy # 原清场逻辑创建的奖杯。
	for item: Node in battle.canvas_layer_temp.get_children(): # 查找真实奖杯。
		if item is Trophy:
			trophy = item
	assert(trophy != null)
	trophy._on_trophy_button_pressed()
	await get_tree().create_timer(6.0).timeout
	await _frames()
	assert(get_tree().current_scene.scene_file_path == AdventureSession.MAP_SCENE)
	assert(AdventureSession.progress.stage_1_cleared and AdventureSession.is_unlocked(2))
	await _screenshot("victory-map")
	var cleared_bytes := FileAccess.get_file_as_bytes(path) # 胜利文件不可因入口重写。
	get_tree().current_scene._return_menu()
	await _frames()
	get_tree().current_scene.get_node("ArtCanvas/ship_button").pressed.emit()
	await _frames()
	assert(FileAccess.get_file_as_bytes(path) == cleared_bytes)
	assert(not get_tree().current_scene.canvas.has_node("Intro"))
	assert(AdventureSession.is_unlocked(2))
	# 用另一个原生玩家验证未完成引导的第三句跳过，绝不调用旧重开流程。
	get_tree().current_scene._return_menu()
	await _frames()
	native_user = get_tree().current_scene.user
	native_user.panel_create_new_user.line_edit.text = username + "-skip"
	native_user.panel_create_new_user.button_ok.pressed.emit()
	_select_user(username + "-skip")
	Global.save_service.save_now()
	original_path = "user://%s-skip/GlobalSaveGame.json" % username
	original_bytes = FileAccess.get_file_as_bytes(original_path)
	get_tree().current_scene.get_node("ArtCanvas/ship_button").pressed.emit()
	await _frames()
	var skipping: Control = get_tree().current_scene.canvas.get_node("Intro") # 第三句等待中的对话。
	await _wait_intro_ready(skipping)
	skipping.conversation.request_advance()
	skipping.conversation.request_advance()
	assert(not skipping.conversation.hold_timer.is_stopped())
	skipping._finish()
	await get_tree().create_timer(1.0).timeout
	assert(not is_instance_valid(skipping))
	await _frames()
	assert(AdventureSession.progress.intro_completed and AdventureSession.progress.cards.size() == 2)
	# 未判胜时主动退出，不能解锁；菜单按钮文字与真实目的地一致。
	AdventureSession.enter_lawn()
	await _wait_battle()
	var battle_menu := Global.main_game.get_node("CanvasLayerUI/All_UI/MainGameMenuOptionDialog") # 原战斗菜单。
	assert(battle_menu.get_node("Option/Button3/Label").text == "返回地图")
	battle_menu.return_main_menu()
	await _frames()
	assert(not AdventureSession.progress.stage_1_cleared)
	assert(FileAccess.get_file_as_bytes(original_path) == original_bytes)
	get_tree().current_scene._return_menu()
	await _frames()
	await get_tree().create_timer(0.3).timeout
	assert(not AdventureSession.adventure_active)
	Global.global_game_state.coin_value += 1
	await get_tree().create_timer(0.3).timeout
	assert(FileAccess.get_file_as_bytes(original_path) != original_bytes)
	# 沿用用户改名接口迁移冒险文件，之后真正调用继续入口。
	assert(Global.user_manager.rename_user(username + "-skip", username + "-renamed").is_empty())
	get_tree().current_scene.get_node("ArtCanvas/ship_button").pressed.emit()
	await _frames()
	assert(AdventureSession.progress.intro_completed)
	assert(not get_tree().current_scene.canvas.has_node("Intro"))
	assert(AdventureSession.progress.cards == {"sunflower": 1, "peashooter": 1})
	print("PASS: menu, seven lines, third-line immediate skip lifecycle, gift, layout, planting, defeat, natural waves, trophy victory, restart, abandon, live autosave isolation and restoration, rename, continue")
	get_tree().quit(0)

## 等待场景入树与布局完成。
func _frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

## 等待原版开战演出、卡槽入场及刷怪启动。
func _wait_battle() -> void:
	await _frames()
	while Global.main_game == null or Global.main_game.main_game_progress != MainGameManager.E_MainGameProgress.MAIN_GAME:
		await get_tree().process_frame
	await get_tree().create_timer(1.2).timeout

## [param label] 为截图文件名；只有图形运行时导出供人工视觉检查。
func _screenshot(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://.godot/phase1-%s.png" % label)

## 从原生左上角玩家按钮选择并点击好，沿用保存、身份切换与全局加载链路。
## [param username] 必须是测试创建的已有玩家。
func _select_user(username: String) -> void:
	var native_user: User = get_tree().current_scene.user # 原生档案界面。
	for button: OneUserButton in native_user.all_user_button: # 选择真实列表中的按钮。
		if button.user_name_on_curr_button == username:
			button.pressed.emit()
			native_user.texture_button_ok.pressed.emit()
			return
	assert(false, "测试玩家不在原生档案列表")

## 等待 [param intro] 的原版进场动画结束，不手动启动对话或播放动画。
func _wait_intro_ready(intro: Control) -> void:
	while intro.conversation.line_index < 0:
		await get_tree().process_frame
