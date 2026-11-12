extends SceneTree
## 隔离预览：沿正式方法替换三类效果，再恢复默认；不加载游戏autoload或玩家数据。
## 当前宿主、输出根与演示帧记录。
var host: Node
var folder := ""
var evidence: Dictionary={}

func _initialize() -> void:
	_run.call_deferred()

## [param name] 保存实际合成画面；[param small] 仅在视频帧写出前等比缩放。
func capture(name: String, small: bool=false) -> void:
	await process_frame
	for pass_index in range(4): # 主线程显式推进已有四层真实GPU合成，避免等候桌面自动交换缓冲。
		RenderingServer.force_draw(false,0.0)
	var image: Image=host.output_view.get_texture().get_image()
	if small:
		image.resize(1066,600,Image.INTERPOLATE_LANCZOS)
	assert(image.save_png(folder.path_join(name+".png"))==OK)
	if not small or name.ends_with("0012") or name.ends_with("0036"):
		print("CAPTURED ",name)

## [param result] 保存成功提交结果，失败立即停止当前演示。
func accepted(result: Dictionary) -> void:
	assert(result.ok,str(result.get("error","Effect rejected")))

func _run() -> void:
	folder=OS.get_cmdline_user_args()[0]
	for directory in ["examples","frames/hover","frames/lights","frames/water"]:
		DirAccess.make_dir_recursive_absolute(folder.path_join(directory))
	host=load("res://scripts/ui/start_menu/coastal/scene_host.gd").new()
	root.add_child(host)
	host.configure("res://assets/adventure/main_menu/coastal",false)
	var display := TextureRect.new() # 供离屏最终结果实际呈现，不含UI业务。
	display.texture=host.output_view.get_texture()
	display.size=Vector2(1066,600)
	root.add_child(display)
	RenderingServer.render_loop_enabled=false
	evidence.api=host.effects.describe()
	var neutral: Dictionary=host.effects.snapshot() # 官方默认，后续案例只改内存。
	# 1. 高亮切换不改变当前入口/锁定信息，hover控制器不复制业务。
	host.set_time(1.0);host.set_elapsed(1.5)
	host.set_entry_hover("research","available");host.advance_entry_hover(2.0)
	await capture("examples/hover_classic")
	accepted(host.effects.set_hover_effect({"shader":"res://shaders/ui/main_menu/entry_sweep.gdshader","parameters":{"fill_gain":.035,"sweep_gain":.28,"inner_edge_gain":.30,"period_seconds":2.0}}))
	assert(host.entry_highlight.active_id=="research")
	await capture("examples/hover_sweep")
	for index in range(48):
		host.set_elapsed(float(index)/24.0)
		await capture("frames/hover/frame_%04d"%index,true)
	# 错误字段/无效周期不能悄悄丢弃或半更新。
	var kept: Dictionary=host.effects.snapshot() # 原有效状态与材质应保留。
	var kept_material: ShaderMaterial=host.entry_highlight.material
	var failures: Array=[] # 记录原生返回的具体原因。
	for candidate: Dictionary in [{"hover":{"parameters":{"typo_gain":1.0}}},{"water":{"period_seconds":0.0}},{"lights":{"research":{"mode":"breathe","minimum":2.0,"maximum":1.0}}},{"water":{"pattern":"unregistered"}}]:
		var rejected: Dictionary=host.effects.apply_profile(candidate)
		assert(not rejected.ok and host.effects.snapshot()==kept and host.entry_highlight.material==kept_material)
		failures.append(rejected.error)
	evidence.rejected_without_partial_update=failures
	# 2. 呼吸的窗口、接收光、光晕共享倍率，日周期不得覆盖它。
	accepted(host.effects.apply_profile(neutral))
	host.set_entry_hover("","",false);host.advance_entry_hover(2.0)
	accepted(host.effects.set_light_behavior("research",{"mode":"breathe","minimum":.15,"maximum":1.45,"period_seconds":2.0}))
	var samples: Array=[] # 同一个动作时刻下的三层参数证据。
	for seconds: float in [0.0,.5,1.0,1.5,2.0]:
		host.set_elapsed(seconds);host.set_time(1.0) # 故意在时间调制后提交全景时段。
		var receiver: Vector4=host.light_material.get_shader_parameter("local_group_energy")
		assert(receiver==host.light_material.get_shader_parameter("emission_group_energy"))
		assert(receiver==host.light_material.get_shader_parameter("halo_group_energy"))
		samples.append({"second":seconds,"research":receiver.w,"other_groups":[receiver.x,receiver.y,receiver.z]})
		if seconds==0.0 or seconds==1.0:
			await capture("examples/breathe_"+("low" if seconds==0.0 else "high"))
	evidence.synchronized_light_samples=samples
	var daily: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/adventure/main_menu/coastal/config/daily_cycle.json")) # 正式全天数据也必须能提交。
	var cycle := preload("res://scripts/ui/start_menu/coastal/daily_cycle.gd").new()
	var before_daily: Vector4=host.light_material.get_shader_parameter("local_group_energy")
	for hour: float in [0.0,6.0,7.5,12.0,18.5,21.5,23.99]:
		var daily_values: Dictionary=cycle.sample(daily,hour)
		assert(host.apply_uniforms(daily_values,float(daily_values.get("water_time_gain",1.0))))
		assert(host.light_material.get_shader_parameter("local_group_energy")==before_daily)
	evidence.full_daily_cycle_preserves_modulation=true
	host.set_time(1.0)
	for index in range(48):
		host.set_elapsed(float(index)/24.0)
		await capture("frames/lights/frame_%04d"%index,true)
	accepted(host.effects.set_light_behavior("research",{"mode":"flicker","minimum":.55,"maximum":1.2,"period_seconds":2.0}))
	host.set_elapsed(.375);await capture("examples/flicker")
	evidence.flicker_multiplier=host.light_material.get_shader_parameter("local_group_energy").w
	# 3. 水面换算法/周期不修改船相位或重新加载部件。
	accepted(host.effects.apply_profile(neutral))
	host.set_time(0.0);host.set_elapsed(1.5)
	var boat_phase: float=host.harbor_material.get_shader_parameter("phase")
	await capture("examples/water_drift")
	accepted(host.effects.set_water_effect({"pattern":"ripples","period_seconds":2.0,"ripple_spacing":21.0,"ripple_center":[1480.0,340.0]}))
	host.set_elapsed(1.5)
	assert(host.harbor_material.get_shader_parameter("phase")==boat_phase)
	evidence.water_independent_from_boat={"boat_phase":boat_phase,"water_angle":host.harbor_material.get_shader_parameter("water_angle")}
	await capture("examples/water_ripples")
	for index in range(48):
		host.set_elapsed(float(index)/24.0)
		await capture("frames/water/frame_%04d"%index,true)
	# 真正文件重载：恢复正式中性配置，确认不是仅能修改示例字典。
	accepted(host.reload_effects())
	assert(host.effects.snapshot()==neutral)
	for state: Array in [["day",0.0],["night",1.0]]:
		host.set_time(state[1]);host.set_elapsed(1.5)
		host.set_entry_hover("","",false);host.advance_entry_hover(2.0)
		await capture("examples/restored_"+state[0])
	evidence.restored_profile=host.effects.snapshot()
	evidence.adapter=RenderingServer.get_video_adapter_name()
	evidence.no_player_services=true
	var report := FileAccess.open(folder.path_join("reports/effect_reachability.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify(evidence,"  "));report.close()
	display.queue_free();host.queue_free()
	for frame in range(4):
		await process_frame
	print("EFFECT_REVIEW_COMPLETE")
	quit(0)
