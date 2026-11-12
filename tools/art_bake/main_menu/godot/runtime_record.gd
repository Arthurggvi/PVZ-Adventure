extends Node
## 9B原生录制入口，仅由隔离manifest注入；正式场景不引用录制代码。
## 当前交付目录，不允许写正式存档。
var folder := ""
## 演示档案由原服务建立，分别展示真实已解锁/锁定。
var names: Array[String]=[]

func _ready() -> void:
	assert(OS.get_user_data_dir().contains("PVZ-Menu9B-Isolated-20261112"))
	folder=str(ProjectSettings.get_setting("menu_runtime_preview/workspace",""))
	assert(not folder.is_empty())
	Global.save_service.stop_autosave()
	for index: int in 2: # 只操作本次隔离用户目录。
		var name := "Menu9B_"+("A_" if index==0 else "B_")+str(Time.get_ticks_msec())
		assert(Global.user_manager.add_user(name).is_empty())
		assert(Global.user_manager.set_current_user(name))
		assert(Global.reload_session_for_current_user())
		var state: AdventureState=Global.global_game_state.adventure_state # 仅用于演示的独立档案。
		if index==0:
			state.quests.records["first_expedition"]={"status":"claimed","period":"","progress":1}
			state.quests.records["first_craft"]={"status":"claimed","period":"","progress":1}
			state.discover_character("plant",1)
			state.discover_character("zombie",1)
			state.experience=PlayerProgression.threshold(5)
			state.player_level=5
			var progress := preload("res://scripts/adventure/island_progress.gd").new(state) # 演示档案已完成地图入场说明，不涉及正式玩家。
			progress.start()
			assert(progress.complete_intro())
		assert(Global.save_service.save_now())
		names.append(name)
	assert(Global.user_manager.set_current_user(names[0]))
	assert(Global.reload_session_for_current_user())
	_record.call_deferred()

func _record() -> void:
	var scene: Control=get_tree().current_scene # 已实例化的正式候选，而不是另画的预览菜单。
	while scene==null or not scene.initialized or not scene.visible:
		await get_tree().process_frame
		scene=get_tree().current_scene
	while scene.get_node("SceneTransition").busy: # 原场景揭幕完成后截图，不能把过渡黑幕当最终夜景。
		await get_tree().process_frame
	for frame in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image() # 实际游戏视口。
	assert(image.save_png(folder.path_join("renders/boot_local_time.png"))==OK)
	var report := {"scene":scene.scene_file_path,"local_hour":scene.clock.current_hour,"user_data_dir":OS.get_user_data_dir(),"profile":Global.user_manager.curr_user_name,"loaded":Global.save_service.is_current_profile_loaded(),"research":AdventureToolbar.feature_status("research"),"adapter":RenderingServer.get_video_adapter_name()} # 同帧业务状态。
	var output := FileAccess.open(folder.path_join("reports/boot.json"),FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  "))
	output.close()
	print("MENU9B_BOOT_OK "+JSON.stringify(report))
	if OS.get_cmdline_user_args().has("--runtime-smoke"):
		scene.queue_free()
		scene=null
		for frame in range(4): # 等待材质、离屏纹理和交互引用释放后结束。
			await get_tree().process_frame
		get_tree().quit(0)
		return
	var suite: Node=load("res://tools/art_bake/main_menu/godot/runtime_walkthrough.gd").new() # 仅明确录制时加载。
	add_child(suite)
	await suite.run(scene,folder,names)
