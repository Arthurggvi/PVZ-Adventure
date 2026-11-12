extends SceneTree
## 统一预览入口：实际渲染静帧、昼夜循环与港口原像素近景，不生成式补帧。

func _initialize() -> void:
	_capture.call_deferred()

## 返回 [param view] 当前真实 GPU 像素；先等待依赖视口。
func read_frame(view: SubViewport) -> Image:
	for index in range(2): # 确保源受光与最终采样都更新。
		await process_frame
	await RenderingServer.frame_post_draw
	var image := view.get_texture().get_image() # 不读取原贴图冒充渲染。
	assert(image != null and not image.is_empty())
	return image

## [param image] 写入 [param path]，写失败直接结束任务。
func save(image: Image, path: String) -> void:
	assert(image.save_png(path) == OK,path)

func _capture() -> void:
	var folder: String = OS.get_cmdline_user_args()[0] # 显式工作根。
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("config/pipeline.json"))) # 捕获约定。
	var host: Node = load(folder.path_join("runtime/scene_host.gd")).new() # 共享宿主，无生产依赖。
	root.add_child(host)
	host.configure(folder)
	for directory in ["renders","frames/day","frames/night","frames/crop_day","frames/crop_night"]:
		DirAccess.make_dir_recursive_absolute(folder.path_join(directory))
		if directory.begins_with("frames/"):
			for filename: String in DirAccess.get_files_at(folder.path_join(directory)):
				if filename.begins_with("frame_") and filename.ends_with(".png"):
					assert(DirAccess.remove_absolute(folder.path_join(directory).path_join(filename)) == OK) # 只移除本工具拥有的旧导出帧。
	var time_positions := {} # 读取相同时间配置，不另写常量。
	for keyframe: Dictionary in host.profile.keyframes:
		time_positions[keyframe.id] = float(keyframe.position)
	var count := roundi(float(host.motion.loop_seconds) * float(config.capture.fps)) if config.capture.animate else 0 # 周期配置唯一决定导出帧数。
	var crop_values: Array = config.preview.crop # 港口裁切坐标。
	var crop := Rect2i(crop_values[0],crop_values[1],crop_values[2]-crop_values[0],crop_values[3]-crop_values[1]) # 原像素裁切范围。
	for state: String in config.capture.states:
		host.set_time(time_positions[state])
		host.set_motion_enabled(false)
		save(await read_frame(host.output_view),folder.path_join("renders/"+state+"_disabled.png"))
		host.set_motion_enabled(true)
		for phase: float in config.capture.static_phases:
			host.set_phase(phase)
			var image := await read_frame(host.output_view) # 单一素材在指定相位的实际输出。
			save(image,folder.path_join("renders/%s_phase_%02d.png"%[state,roundi(phase*100)]))
			save(image.get_region(crop),folder.path_join("renders/%s_crop_%02d.png"%[state,roundi(phase*100)]))
		host.set_phase(1.0)
		save(await read_frame(host.output_view),folder.path_join("renders/"+state+"_loop_end.png"))
		if config.capture.include_ui:
			host.ui_layer.show()
			host.set_phase(0.25)
			save(await read_frame(host.output_view),folder.path_join("renders/"+state+"_ui.png"))
			host.ui_layer.hide()
		for index in range(count):
			var seconds := float(index)/float(count)*float(host.motion.loop_seconds) # 按完整周期均匀取样，不重复首帧。
			host.set_elapsed(seconds)
			var image := await read_frame(host.output_view) # 每帧由 GPU 输出。
			save(image.get_region(crop),folder.path_join("frames/crop_%s/frame_%04d.png"%[state,index]))
			image.resize(config.capture.dimensions[0],config.capture.dimensions[1],Image.INTERPOLATE_LANCZOS)
			save(image,folder.path_join("frames/%s/frame_%04d.png"%[state,index]))
	# 中途时态变化也使用同一个宿主，船舱窗随船，不加载任何独立夜景船。
	host.set_time(float(time_positions["dusk"]))
	host.set_phase(0.25)
	save(await read_frame(host.output_view),folder.path_join("renders/dusk_phase_25.png"))
	var metadata := {"adapter":RenderingServer.get_video_adapter_name(),"engine":Engine.get_version_info(),"states":config.capture.states,"frames_per_state":count,"fps":config.capture.fps,"source":"same live relit viewport sampled by bounded harbor material","loop_seconds":host.motion.loop_seconds,"clock_connected":false,"game_loaded":false,"image_generation_used":false} # 真实渲染记录。
	var output := FileAccess.open(folder.path_join("reports/render.json"),FileAccess.WRITE)
	output.store_string(JSON.stringify(metadata,"  "))
	output.close()
	print(JSON.stringify(metadata))
	print("ARTCONTROL_JOB_OK")
	quit(0)
