extends RefCounted
## 9B全天/午夜与运行成本的实际输出记录，不修改真实系统时钟。

## [param scene] 为正式候选；[param io] 为隔离录制器。返回当前观测，不宣称全平台性能。
func capture(scene: Control, io: Node) -> Dictionary:
	var result := {} # 汇总同一进程的参数与实际帧。
	io.driver.move(scene.canvas.position+Vector2(850,700)*scene.canvas.scale) # 空地不高亮，便于同相位资源对照。
	scene.motion_paused=true
	scene.host.set_elapsed(1.5)
	io.overlay.hide()
	for item: Array in [["midnight",0.0],["dawn",6.0],["morning",7.5],["day",12.0],["dusk",18.5],["night",21.5],["before_midnight",23.99972222],["after_midnight",.00027778]]:
		scene.set_preview_hour(item[1])
		for frame in range(4): # 让受光/高亮/陆地/港口四级结果完成。
			await scene.get_tree().process_frame
		await RenderingServer.frame_post_draw
		var picture := scene.get_viewport().get_texture().get_image() # 实际完整菜单，非只贴背景。
		assert(picture.save_png(io.folder.path_join("renders/cycle_"+item[0]+".png"))==OK)
		var source: Image=scene.host.output_view.get_texture().get_image() # 原画尺寸便于静态基线比较。
		assert(source.save_png(io.folder.path_join("renders/scene_"+item[0]+".png"))==OK)
	var count := 240 # 十秒展示24小时，结束回到次日午夜。
	for index in range(count):
		scene.set_preview_hour(24.0*index/float(count-1))
		scene.host.set_elapsed(float(index)/24.0)
		for frame in range(2):
			await scene.get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image := scene.get_viewport().get_texture().get_image()
		assert(image.save_png(io.folder.path_join("frames/day_cycle/frame_%04d.png"%index))==OK)
	result["cycle_frames"]=count
	result["cycle_fps"]=24
	result["static_phase_seconds"]=1.5
	# 系统时间变化只替换参数输入；动作秒数在这期间不应被改写。
	var before: float=scene.elapsed # 原动作计时，不用绝对日期驱动。
	var supplied := {"hour":23.999} # 本录制注入的时钟，并不写系统设置。
	scene.clock.source=func():return supplied.hour
	scene.clock.use_local()
	scene.clock.resync(true)
	supplied.hour=6.0
	scene.clock.resync(false)
	var changed_start: Dictionary=scene.clock.values.duplicate()
	scene.clock.advance(float(scene.clock.config.resync_seconds)*.5)
	var changed_mid: Dictionary=scene.clock.values.duplicate()
	scene.clock.advance(float(scene.clock.config.resync_seconds))
	result["injected_clock_resync"]={"start":changed_start.ambient_rgb,"mid":changed_mid.ambient_rgb,"end":scene.clock.values.ambient_rgb,"animation_seconds_unchanged":is_equal_approx(scene.elapsed,before)}
	assert(result.injected_clock_resync.animation_seconds_unchanged)
	scene.clock.source=Callable()
	scene.clock.resync(true)
	scene.motion_paused=false
	# 无截图/读回时采样实际帧间隔，避免把PNG写盘耗时称作渲染性能。
	io.overlay.hide()
	Engine.max_fps=0
	var timings: Array[float]=[] # 实机帧间隔，不是纯GPU耗时。
	for frame in range(150):
		var tick := Time.get_ticks_usec()
		await scene.get_tree().process_frame
		if frame>=30:
			timings.append(float(Time.get_ticks_usec()-tick)/1000.0)
	timings.sort()
	var total := 0.0
	for timing: float in timings:
		total+=timing
	result["performance"]={"samples":timings.size(),"mean_frame_ms":total/timings.size(),"p95_frame_ms":timings[floori(timings.size()*.95)],"static_memory_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),"texture_memory_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),"video_memory_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),"renderer":RenderingServer.get_video_adapter_name(),"size":scene.get_viewport_rect().size,"capture_active":false}
	Engine.max_fps=24
	io.overlay.show()
	return result
