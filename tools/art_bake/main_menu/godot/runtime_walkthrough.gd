extends Node
## 正式菜单的隔离流程录像：用真实控件点击，不在UI之后伪造已打开状态。
## 当前录制辅助与场景引用，跨场景后必须重新取实际current_scene。
var io: Node
var scene: Control

## [param root] 为正式菜单；[param folder] 是交付目录；[param profiles] 是本次隔离档案。
func run(root: Control, folder: String, profiles: Array[String]) -> void:
	scene=root
	io=preload("res://tools/art_bake/main_menu/godot/runtime_review_io.gd").new()
	add_child(io)
	io.configure(folder)
	var metrics: Dictionary={} # 已有完整交付之外，可单独做退出引用诊断。
	if not OS.get_cmdline_user_args().has("--runtime-quick"):
		metrics=await preload("res://tools/art_bake/main_menu/godot/runtime_cycle_record.gd").new().capture(scene,io)
	await io.hold(12,"本机当地时间启动 · 真实头像、等级和存档")
	await io.snapshot("local_time_runtime")
	scene.set_preview_hour(7.5)
	await io.hold(12,"清晨 · 原有素材的统一参数受光")
	await io.hover(scene,Vector2(660,170))
	await io.snapshot("morning_library_hover")
	await io.click_at(io.driver.position)
	await io.hold(20,"图书馆 → 现有图鉴")
	assert(AdventureToolbar._modal_feature=="almanac")
	await io.snapshot("real_almanac")
	await io.escape()
	await io.hold(12)
	await io.click_control(scene.console.buttons.settings)
	await io.hold(18,"功能台选项 → 与工具栏共用设置窗口")
	assert(AdventureToolbar._modal_feature=="settings")
	await io.snapshot("real_settings")
	await io.escape()
	await io.hold(12)
	await io.click_control(scene.console.buttons.help)
	await io.hold(12,"帮助 → 当前建筑操作说明")
	assert(scene.dialogs.mode=="help")
	await io.hover(scene,Vector2(980,350))
	assert(scene.entry_layer.hovered_id.is_empty())
	await io.snapshot("real_help_blocking")
	await io.click_control(scene.dialogs.panel.get_node("Close"))
	await io.hold(10)
	await _switch_profile(profiles[1])
	assert(not AdventureToolbar.feature_status("research").unlocked)
	scene.set_preview_hour(21.5)
	await io.hover(scene,Vector2(980,350))
	await io.snapshot("profile_B_research_locked")
	await _switch_profile(profiles[0])
	assert(AdventureToolbar.feature_status("research").unlocked)
	await io.hover(scene,Vector2(980,350))
	await io.click_at(io.driver.position)
	await io.hold(25,"切回档案A → 研究室条件和真实功能一起恢复")
	assert(AdventureToolbar._modal_feature=="research")
	await io.snapshot("profile_A_real_research")
	await io.escape()
	await io.hold(15)
	# 地图往返复用现有导航和当前注册表；不新建第二份地图状态。
	var old_host: WeakRef=weakref(scene.host) # 只观测释放，不延长生命周期。
	var previous_path: String=Global.main_scene_registry.MainScenesMap[MainSceneRegistry.MainScenes.StartMenu]
	Global.main_scene_registry.MainScenesMap[MainSceneRegistry.MainScenes.StartMenu]="res://scenes/main/01StartMenuCoastal.tscn" # 隔离候选验证返回目标；正式切换后该值已相同。
	await io.hover(scene,Vector2(1500,380))
	await io.click_at(io.driver.position)
	await io.hold(16,"港口 → 真实地区选择")
	var picker: Control=AdventureToolbar._navigation._picker
	assert(picker!=null)
	while picker.is_animating():
		await io.hold(1)
	await io.snapshot("real_destination_picker")
	await io.click_control(picker.canvas.get_node("Cards/zombie_island"))
	while get_tree().current_scene==scene or get_tree().current_scene==null:
		await io.hold(1)
	scene=get_tree().current_scene
	while scene.get_node("SceneTransition").busy:
		await io.hold(1)
	assert(scene.scene_file_path==AdventureSession.MAP_SCENE)
	await io.hold(12,"进入僵尸岛地图 · 不进入战斗")
	await io.snapshot("actual_map_entered")
	metrics["old_menu_host_released_on_map"]=old_host.get_ref()==null
	assert(metrics.old_menu_host_released_on_map)
	await io.click_control(scene.get_node("AdventureProfileHud/Action"))
	while get_tree().current_scene==scene or get_tree().current_scene==null:
		await io.hold(1)
	scene=get_tree().current_scene
	while not scene.initialized or scene.get_node("SceneTransition").busy:
		await io.hold(1)
	assert(scene.scene_file_path=="res://scenes/main/01StartMenuCoastal.tscn")
	await io.hold(16,"返回同一个正式菜单入口 · 不回旧版")
	await io.snapshot("returned_to_new_menu")
	Global.main_scene_registry.MainScenesMap[MainSceneRegistry.MainScenes.StartMenu]=previous_path
	metrics["toolbar_instances"]=get_tree().get_nodes_in_group("adventure_toolbar_surface").size()
	metrics["return_profile_unchanged"]=Global.user_manager.curr_user_name==profiles[0]
	# 宽/高窗口仍使用同一原画坐标，不给建筑追加硬编码偏移。
	for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(1066,800)]:
		DisplayServer.window_set_size(dimensions)
		await io.hold(10,"窗口变化：建筑命中、工具栏和头像共用当前布局")
		await io.hover(scene,Vector2(660,170))
		assert(scene.entry_layer.hovered_id=="library")
		await io.snapshot("layout_%dx%d"%[dimensions.x,dimensions.y])
	DisplayServer.window_set_size(Vector2i(1066,600))
	await io.hold(12)
	await io.click_control(scene.console.buttons.exit)
	await io.hold(12,"退出确认 · 保存当前隔离档案后结束")
	assert(scene.dialogs.mode=="exit")
	await io.snapshot("exit_confirmation")
	io.write_report(metrics)
	print("MENU9B_RECORD_OK "+JSON.stringify({"frames":io.frame_index,"metrics":metrics}))
	# 最后真实点击确认。退出前的SaveService结果可在隔离日志及文件回执核对。
	io.driver.move(scene.dialogs.confirm.get_global_rect().get_center())
	io.driver.button(true)
	await get_tree().process_frame
	io.driver.button(false)
	io.dispose()

## [param target] 只选择录制器预先创建的隔离档案，经原User确认事务切换。
func _switch_profile(target: String) -> void:
	await io.click_control(scene.profile_hud.get_node("Action"))
	await io.hold(8,"原档案选择器 · 切换后同步头像、等级与入口状态")
	assert(scene.dialogs.selector.visible)
	await io.snapshot("profile_selector_"+("B" if target.contains("_B_") else "A"))
	var selector: Control=scene.dialogs.selector # 原场景中的真实User组件。
	var chosen: Control
	for button: Control in selector.all_user_button:
		if button.user_name_on_curr_button==target:
			chosen=button
	assert(chosen!=null)
	selector.get_node("Panel/PanelContainer/ScrollContainer").ensure_control_visible(chosen)
	await io.hold(3)
	await io.click_control(chosen)
	await io.click_control(selector.texture_button_ok)
	await io.hold(12)
	assert(not selector.visible and Global.user_manager.curr_user_name==target)
	assert(Global.save_service.is_current_profile_loaded())
	assert(scene.profile_hud.get_node("PlayerName").text==target)
