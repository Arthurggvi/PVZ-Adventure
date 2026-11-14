## 验收工具栏的按需模态窗口：Bootstrap 不创建 HUD，菜单首次打开才加载脚本。
extends Node

func _ready() -> void:
	assert(OS.get_user_data_dir().contains("startup-toolbar-test"))
	get_tree().current_scene = null
	get_tree().create_timer(16.0, true, false, true).timeout.connect(func():
		push_error("FAIL: toolbar lazy modal timeout")
		get_tree().quit(1))
	_run.call_deferred()

func _run() -> void:
	if get_tree().change_scene_to_file("res://scenes/main/01StartMenuCoastal.tscn") != OK:
		push_error("FAIL: unable to enter menu")
		get_tree().quit(1)
		return
	var timeout_usec: int = Time.get_ticks_usec() + 10_000_000
	while Time.get_ticks_usec() < timeout_usec:
		var current: Node = get_tree().current_scene
		if current != null and current.scene_file_path == "res://scenes/main/01StartMenuCoastal.tscn" \
				and is_instance_valid(AdventureToolbar._view) and not current.get_node("SceneTransition").busy:
			break
		await get_tree().process_frame
	if not is_instance_valid(AdventureToolbar._view):
		push_error("FAIL: toolbar presenter was not materialized on scene entry")
		get_tree().quit(1)
		return
	if AllCards.is_catalog_materialized():
		push_error("FAIL: toolbar loaded full card catalogue before use")
		get_tree().quit(1)
		return
	# 初次进入菜单没有玩家时，原生档案选择器会占用输入。
	# 经真实用户选择界面创建并选中隔离档案后，再验证工具栏按需窗口。
	var menu: Control = get_tree().current_scene
	menu.dialogs.open_profiles()
	var selector: User = menu.dialogs.selector as User
	var username: String = "toolbar-%d" % Time.get_ticks_usec()
	selector.panel_create_new_user.line_edit.text = username
	selector.panel_create_new_user.button_ok.pressed.emit()
	for button: OneUserButton in selector.all_user_button:
		if button.user_name_on_curr_button == username:
			button.pressed.emit()
			break
	selector.texture_button_ok.pressed.emit()
	var ready_limit: int = Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < ready_limit and not AdventureToolbar.feature_status("settings").allowed:
		await get_tree().process_frame
	if not AdventureToolbar.request_feature("settings"):
		push_error("FAIL: lazy settings action was rejected")
		get_tree().quit(1)
		return
	var modal: Control = AdventureToolbar.modal_for("settings")
	if not is_instance_valid(modal) or not modal is GameSettingsWindow:
		push_error("FAIL: settings module did not materialize via toolbar")
		get_tree().quit(1)
		return
	modal.request_close()
	var close_limit: int = Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < close_limit and is_instance_valid(AdventureToolbar.modal_for("settings")):
		await get_tree().process_frame
	if is_instance_valid(AdventureToolbar.modal_for("settings")) or AllCards.is_catalog_materialized():
		push_error("FAIL: modal lifetime leaked or eagerly loaded cards")
		get_tree().quit(1)
		return
	print("PASS: toolbar lazily creates/releases settings modal without card preloads")
	get_tree().quit(0)
