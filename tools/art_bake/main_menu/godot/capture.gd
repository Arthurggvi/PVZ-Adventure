extends SceneTree
## 同一预览入口：可选风场、既有港口、各部件近景；所有帧来自GPU。

func _initialize() -> void:
	_capture.call_deferred()

## 等待 [param view] 的受光、风动、港口三级依赖完成，返回真实像素。
func read_frame(view: SubViewport) -> Image:
	for index in range(3): # 不拿上一相位的中间视口冒充当前帧。
		await process_frame
	await RenderingServer.frame_post_draw
	var image := view.get_texture().get_image() # 实际渲染回读。
	assert(image != null and not image.is_empty())
	return image

## [param image] 写入 [param path]；失败即停止。
func save(image: Image, path: String) -> void:
	assert(image.save_png(path)==OK,path)

## 把 [param values] 的左上/右下坐标转为原像素矩形。
func rectangle(values: Array) -> Rect2i:
	return Rect2i(values[0],values[1],values[2]-values[0],values[3]-values[1])

func _capture() -> void:
	var folder: String = OS.get_cmdline_user_args()[0] # 独立工作根。
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("config/pipeline.json"))) # 捕获设置。
	var host: Node = load(folder.path_join("runtime/scene_host.gd")).new() # 统一宿主，无生产单例。
	root.add_child(host)
	host.configure(folder)
	var has_wind: bool = not host.wind_controller.settings.is_empty() # 兼容历史不含风配置的工作目录。
	var seconds: float = config.capture.get("duration_seconds",float(host.motion.loop_seconds)) # 独立预览长度。
	var count := roundi(seconds*float(config.capture.fps)) if config.capture.animate else 0 # 真正采样帧数。
	var closeups: Dictionary = config.capture.get("closeups",{"harbor":config.preview.crop}) # 多个原尺寸近景。
	var directories: Array[String] = ["renders","frames/day","frames/night"]
	for state: String in config.capture.states:
		for name: String in closeups:
			directories.append("frames/"+name+"_"+state)
	for directory: String in directories:
		DirAccess.make_dir_recursive_absolute(folder.path_join(directory))
		if directory.begins_with("frames/"):
			for filename: String in DirAccess.get_files_at(folder.path_join(directory)):
				if filename.begins_with("frame_") and filename.ends_with(".png"):
					assert(DirAccess.remove_absolute(folder.path_join(directory).path_join(filename))==OK) # 仅清理本工具拥有的派生帧。
	var at := {} # 时态位置来自统一配置。
	for keyframe: Dictionary in host.profile.keyframes:
		at[keyframe.id]=float(keyframe.position)
	for state: String in config.capture.states:
		host.set_time(at[state])
		host.set_motion_enabled(false)
		host.set_wind_enabled(false)
		save(await read_frame(host.output_view),folder.path_join("renders/"+state+"_disabled.png"))
		host.set_motion_enabled(true)
		if has_wind:
			for phase: float in config.capture.static_phases:
				host.set_phase(phase)
				save(await read_frame(host.output_view),folder.path_join("renders/%s_wind_off_%02d.png"%[state,roundi(phase*100)]))
		host.set_wind_enabled(has_wind)
		for phase: float in config.capture.static_phases:
			host.set_phase(phase)
			var image := await read_frame(host.output_view) # 同一母图同时含已通过港口和新风动。
			save(image,folder.path_join("renders/%s_phase_%02d.png"%[state,roundi(phase*100)]))
			for name: String in closeups:
				save(image.get_region(rectangle(closeups[name])),folder.path_join("renders/%s_%s_%02d.png"%[state,name,roundi(phase*100)]))
		host.set_elapsed(seconds)
		save(await read_frame(host.output_view),folder.path_join("renders/"+state+"_loop_end.png"))
		if config.capture.include_ui:
			host.ui_layer.show()
			host.set_phase(0.25)
			save(await read_frame(host.output_view),folder.path_join("renders/"+state+"_ui.png"))
			host.ui_layer.hide()
		for index in range(count):
			host.set_elapsed(float(index)/float(count)*seconds)
			var image := await read_frame(host.output_view) # 帧之间无生成补帧。
			for name: String in closeups:
				save(image.get_region(rectangle(closeups[name])),folder.path_join("frames/%s_%s/frame_%04d.png"%[name,state,index]))
			image.resize(config.capture.dimensions[0],config.capture.dimensions[1],Image.INTERPOLATE_LANCZOS)
			save(image,folder.path_join("frames/%s/frame_%04d.png"%[state,index]))
	host.set_time(float(at["dusk"]))
	host.set_phase(0.25)
	save(await read_frame(host.output_view),folder.path_join("renders/dusk_phase_25.png"))
	var metadata := {"adapter":RenderingServer.get_video_adapter_name(),"engine":Engine.get_version_info(),"states":config.capture.states,"frames_per_state":count,"fps":config.capture.fps,"loop_seconds":seconds,"closeups":closeups,"wind_enabled":has_wind,"wind_loop_seconds":host.wind_controller.settings.get("loop_seconds",0.0),"source":"same live lighting, optional shared wind, approved harbor transform","clock_connected":false,"game_loaded":false,"image_generation_used":false} # 本次执行事实。
	var output := FileAccess.open(folder.path_join("reports/render.json"),FileAccess.WRITE)
	output.store_string(JSON.stringify(metadata,"  "))
	output.close()
	print(JSON.stringify(metadata))
	print("ARTCONTROL_JOB_OK")
	quit(0)
