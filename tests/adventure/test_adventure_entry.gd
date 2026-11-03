## 单一入口与原生档案生命周期验收；必须隔离 APPDATA。
extends "res://tests/adventure/test_island_flow.gd"

## 经正式V8菜单按钮进入，覆盖匿名拒绝、串档、损坏与首次保存失败。
func _run() -> void:
	assert(OS.get_user_data_dir().contains("entry-test-user"), "必须使用隔离 APPDATA")
	get_tree().change_scene_to_file("res://scenes/main/01StartMenuV8.tscn")
	await _frames()
	if OS.get_cmdline_user_args().has("--resume-probe"):
		_click_entry()
		await _frames()
		assert(AdventureSession.progress.stage_1_cleared)
		assert(not get_tree().current_scene.canvas.has_node("Intro"))
		print("PASS: process restart opens persisted current native profile")
		get_tree().quit()
		return
	# 旧游客档只作保留哨兵，普通入口不得读取、删除或迁移。
	var guest := "user://adventure_guest/zombie_island_v1.json" # 测试游客文件。
	_write(guest, "legacy guest sentinel")
	Global.user_manager.set_current_user("")
	_click_entry()
	assert(AdventureSession.progress == null and not AdventureSession.adventure_active)
	assert(get_tree().current_scene.has_node("AdventureError"))
	assert(FileAccess.get_file_as_string(guest) == "legacy guest sentinel")
	var user_a := "entry-a-%s" % Time.get_ticks_usec() # 原生玩家 A。
	var user_b := user_a + "-b" # 原生玩家 B。
	_create_user(user_a)
	_create_user(user_b)
	_select_user(user_a)
	# 同一帧重复点击同一个真实按钮；场景切换后 current_scene 暂时为空。
	var entry_button: BaseButton = get_tree().current_scene.get_node("ArtCanvas/ship_button")
	entry_button.pressed.emit()
	entry_button.pressed.emit()
	await _frames()
	var path_a: String = AdventureSession.progress.save_path # A 的固定版本路径。
	assert(AdventureSession.progress.started and not AdventureSession.progress.intro_completed)
	# 赠卡句之后退出，重新进入仍由intro_completed决定显示引导。
	var intro: Control = get_tree().current_scene.canvas.get_node("Intro") # 未完成引导。
	await _wait_intro_ready(intro)
	for index: int in range(intro.GIFT_LINE): # 沿原生十一句流程走到实际赠卡句。
		await _advance_intro(intro)
	assert(AdventureSession.progress.cards.size() == 2)
	var interrupted := FileAccess.get_file_as_bytes(path_a) # 已赠卡未完成的文件。
	await _menu()
	_click_entry()
	await _frames()
	assert(FileAccess.get_file_as_bytes(path_a) == interrupted)
	assert(get_tree().current_scene.canvas.has_node("Intro"))
	get_tree().current_scene.canvas.get_node("Intro")._finish()
	assert(AdventureSession.progress.cards == {"sunflower": 1, "peashooter": 1})
	# 状态层准备已通关档案；真实战斗胜利另由 test_island_flow 验收。
	assert(AdventureSession.progress.record_victory())
	var completed := FileAccess.get_file_as_bytes(path_a) # 已完成状态原字节。
	await _menu()
	_select_user(user_b)
	assert(AdventureSession.progress == null)
	_click_entry()
	await _frames()
	assert(not AdventureSession.progress.stage_1_cleared and AdventureSession.progress.cards.is_empty())
	await _menu()
	_select_user(user_a)
	_click_entry()
	await _frames()
	assert(FileAccess.get_file_as_bytes(path_a) == completed)
	assert(AdventureSession.is_unlocked(2) and not get_tree().current_scene.canvas.has_node("Intro"))
	await _menu()
	_select_user(user_b)
	var path_b := "user://%s/adventure/zombie_island_v1.json" % user_b # 只破坏测试 B。
	for invalid: String in ["{broken", '{"version":999}']: # 损坏与不兼容版本都阻止进入。
		_write(path_b, invalid)
		_click_entry()
		assert(not AdventureSession.adventure_active and AdventureSession.progress == null)
		assert(not AdventureSession.entry_error.is_empty())
		assert(FileAccess.get_file_as_string(path_b) == invalid)
	# 首次保存失败由真实文件系统制造，不增加生产测试开关。
	var failing := user_a + "-io" # 独立的写入失败玩家。
	_create_user(failing)
	_select_user(failing)
	var failing_path := "user://%s/adventure/zombie_island_v1.json" % failing # 新档路径。
	assert(DirAccess.make_dir_recursive_absolute(failing_path + ".tmp") == OK)
	_click_entry()
	assert(AdventureSession.progress == null and not AdventureSession.adventure_active)
	assert(not FileAccess.file_exists(failing_path))
	assert(not AdventureSession.entry_error.is_empty())
	assert(DirAccess.remove_absolute(failing_path + ".tmp") == OK)
	_click_entry()
	await _frames()
	assert(AdventureSession.progress.started and FileAccess.file_exists(failing_path))
	await _menu()
	_select_user(user_a)
	# 原生改名界面迁移目录，删除非当前玩家沿用原生删除确认处理。
	var native: User = get_tree().current_scene.user # 原生档案管理控件。
	native.panel_rename_user.line_edit.text = user_a + "-renamed"
	native.panel_rename_user.button_ok.pressed.emit()
	assert(Global.user_manager.curr_user_name == user_a + "-renamed")
	for button: OneUserButton in native.all_user_button: # 只删除测试 B，A 的进度不受影响。
		if button.user_name_on_curr_button == user_b:
			button.pressed.emit()
			break
	native._on_delete_confirmed()
	assert(not DirAccess.dir_exists_absolute("user://" + user_b))
	_click_entry()
	await _frames()
	assert(AdventureSession.progress.stage_1_cleared)
	assert(FileAccess.get_file_as_string(guest) == "legacy guest sentinel")
	await _menu()
	# 原菜单其余三种模式继续使用原选关场景。
	for mode: int in range(2, 5): # 迷你、解密、生存按钮编号。
		get_tree().current_scene.get_node("BG_Right/Menu/Button%d" % mode).pressed.emit()
		await _frames()
		assert(not AdventureSession.adventure_active)
		assert(not get_tree().current_scene is StartMenuRoot)
		get_tree().change_scene_to_file("res://scenes/main/01StartMenuV8.tscn")
		await _frames()
	print("PASS: single menu entry, native A/B/A, rename/delete, interrupted intro, unchanged existing bytes, corrupt/version refusal, IO retry, guest preservation")
	get_tree().quit()

## 点击真实冒险按钮，不调用旧新游戏或继续接口。
func _click_entry() -> void:
	get_tree().current_scene.get_node("ArtCanvas/ship_button").pressed.emit()

## 经地图返回主菜单。
func _menu() -> void:
	get_tree().current_scene._return_menu()
	await _frames()

## 通过原生创建档案面板创建 [param username]。
func _create_user(username: String) -> void:
	var native: User = get_tree().current_scene.user # 原生创建面板。
	native.panel_create_new_user.line_edit.text = username
	native.panel_create_new_user.button_ok.pressed.emit()

## 只写测试专用文件 [param path]，内容为 [param content]。
func _write(path: String, content: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE) # 测试故障哨兵。
	assert(file != null)
	file.store_string(content)
	file.close()
