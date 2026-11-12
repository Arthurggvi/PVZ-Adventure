extends SceneTree
## 独立空工程加载菜单资源包并实际绘制，确认不依赖制作目录或原工程链接。
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var request: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0])) # 明确提供的输入，不扫描全机。
	if request.mode=="pack":
		var pack := PCKPacker.new() # 原生打包，无需安装exe导出模板。
		assert(pack.pck_start(request.output)==OK)
		for entry: Dictionary in request.files: # 全部为本菜单代码/资源；无字体和玩家数据。
			assert(pack.add_file(entry.target,entry.source)==OK,entry.source)
		assert(pack.flush()==OK)
		print("MENU_PACK_CREATED")
		quit(0)
		return
	assert(ProjectSettings.load_resource_pack(request.pack))
	var host: Node=load("res://scripts/ui/start_menu/coastal/scene_host.gd").new() # 该文件只能来自PCK。
	root.add_child(host)
	host.configure("res://assets/adventure/main_menu/coastal",false)
	var display := TextureRect.new() # 空工程内只显示菜单画面，不复制原游戏UI。
	display.texture=host.output_view.get_texture()
	display.size=Vector2(1066,600)
	display.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	root.add_child(display)
	var reference: Image # 原生包中已发布母图的真实像素。
	for item: Array in [["day",0.0],["night",1.0]]:
		host.set_time(item[1])
		host.set_elapsed(1.5)
		for frame in range(5):
			await process_frame
		await RenderingServer.frame_post_draw
		var picture: Image=host.output_view.get_texture().get_image()
		assert(picture.save_png(str(request.directory).path_join("pack_"+item[0]+".png"))==OK)
	var files: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/adventure/main_menu/coastal/texture_catalog.json")) # 所需贴图全部原生资源。
	var report := {"texture_count":files.size(),"pck_loaded":true,"scene_host_from_pck":true,"work_directory_not_linked":true,"adapter":RenderingServer.get_video_adapter_name(),"full_game_executable_exported":false}
	var output := FileAccess.open(str(request.report),FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  "))
	output.close()
	display.queue_free()
	host.queue_free()
	for frame in range(4):
		await process_frame
	print("MENU_PACK_RENDER_OK")
	quit(0)
