extends Node
## 单一场景宿主：先实时受光，再由港口层采样；UI 与场景材质独立。
## 原始受光视口，所有时段只在此计算一次。
var lit_view: SubViewport
## 最终合成视口。
var output_view: SubViewport
## 既有统一光照材质。
var light_material: ShaderMaterial
## 有界港口动态材质。
var harbor_material: ShaderMaterial
## 独立界面节点。
var ui_layer: Node2D
## 时段配置和共用采样器。
var profile: Dictionary
var sampler: RefCounted
## 动态配置，内部只保存本实例状态。
var motion: Dictionary
## 当前时段进度。
var time_progress := 0.0
## 可选统一风场，只持有本宿主实例。
var wind_controller: RefCounted
## 可选入口视觉；没有入口配置时不增加视口。
var entry_highlight: RefCounted

## [param path] 是本工作目录图片；不触发生产游戏资源导入。
func texture_file(path: String) -> ImageTexture:
	var image := Image.load_from_file(path) # 已有图像。
	assert(image != null and not image.is_empty(), path)
	return ImageTexture.create_from_image(image)

## [param path] 为小端 RGBA32F 文件，[param size] 为画布尺寸。
func float_texture(path: String, size: Vector2i) -> ImageTexture:
	var bytes := FileAccess.get_file_as_bytes(path) # 不经过色彩变换的数值。
	assert(bytes.size() == size.x * size.y * 16, path)
	return ImageTexture.create_from_image(Image.create_from_data(size.x,size.y,false,Image.FORMAT_RGBAF,bytes))

## [param size] 指定真实绘制尺寸；返回本宿主拥有的视口。
func make_view(size: Vector2i) -> SubViewport:
	var view := SubViewport.new() # 由宿主统一释放。
	view.size = size
	view.disable_3d = true
	view.use_hdr_2d = false
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	return view

## [param view] 接受 [param texture]；返回全画布图像节点。
func artwork(view: SubViewport, texture: Texture2D) -> TextureRect:
	var rect := TextureRect.new() # 只承载画面，不参与交互。
	rect.texture = texture
	rect.size = Vector2(view.size)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	view.add_child(rect)
	return rect

## [param folder] 是资产工作目录；不读取存档或生产单例。
func configure(folder: String) -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("config/pipeline.json"))) # 场景约定。
	var size := Vector2i(manifest.canvas[0],manifest.canvas[1]) # 母图真实尺寸。
	profile = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("config/time_profile.json")))
	motion = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("config/motion.json")))
	sampler = load(folder.path_join("runtime/time_profile.gd")).new()
	lit_view = make_view(size)
	var base := artwork(lit_view,texture_file(folder.path_join("master_original.png"))) # 原图永不替换为夜景贴图。
	base.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var light_shader := Shader.new() # 沿用已批准受光算法。
	light_shader.code = FileAccess.get_file_as_string(folder.path_join("runtime/relight.gdshader"))
	light_material = ShaderMaterial.new()
	light_material.shader = light_shader
	var inputs := {"base_working":"working_base.png","ground_finished":"ground_finished.png","normal_data":"maps/normal.png","control_data":"maps/controls.png","environment_data":"maps/environment.png","spill_data":"maps/spill.png","local_emission_data":"finish_maps/local_emission.png","source_halo_data":"finish_maps/source_halo.png","old_group_emission_data":"finish_maps/base_group_emission.png"} # 共用受光输入。
	for key: String in inputs:
		light_material.set_shader_parameter(key,texture_file(folder.path_join(inputs[key])))
	light_material.set_shader_parameter("local_receiver_data",float_texture(folder.path_join("attenuation_maps/receivers.rgba32f"),size))
	for key: String in profile.reference:
		var value: Array = profile.reference[key] # 固定校准参数。
		light_material.set_shader_parameter(key,Vector3(value[0],value[1],value[2]))
	base.material = light_material
	entry_highlight = load(folder.path_join("runtime/entry_highlight.gd")).new()
	var entry_source: SubViewport = entry_highlight.configure(self,folder,lit_view) # 共用原动态变换，无额外近似运动。
	wind_controller = load(folder.path_join("runtime/wind_layer.gd")).new()
	var wind_view: SubViewport = wind_controller.configure(self,folder,entry_source) # 树/棚在船体变换之前处理。
	output_view = make_view(size)
	var composite := artwork(output_view,wind_view.get_texture()) # 读取真实实时受光结果。
	var harbor_shader := Shader.new() # 只负责有界动态，不重复计算灯光。
	harbor_shader.code = wind_controller.shader_source(folder,"harbor.gdshader")
	harbor_material = ShaderMaterial.new()
	harbor_material.shader = harbor_shader
	harbor_material.set_shader_parameter("canvas_pixels",Vector2(size))
	harbor_material.set_shader_parameter("masks",texture_file(folder.path_join("assets/harbor_masks.png")))
	harbor_material.set_shader_parameter("master_color",texture_file(folder.path_join("master_original.png")))
	harbor_material.set_shader_parameter("clean_color",texture_file(folder.path_join("assets/clean_plate.png")))
	for uniform: String in ["clean_light_uv","boat_premult","boat_light_uv","fixed_premult","fixed_light_uv"]: # 预乘颜色与低频受光参考分别绑定。
		harbor_material.set_shader_parameter(uniform,float_texture(folder.path_join("assets/"+uniform+".rgba32f"),size))
	composite.material = harbor_material
	wind_controller.bind_flag(self,folder,harbor_material)
	ui_layer = Node2D.new()
	output_view.add_child(ui_layer)
	for filename in ["layer_profile_proposed.png","layer_console_proposed.png","layer_toolbar_expanded.png"]:
		var rect := TextureRect.new() # 不使用场景材质的界面占位。
		rect.texture = texture_file(folder.path_join("ui/"+filename))
		rect.size = Vector2(size)
		ui_layer.add_child(rect)
	ui_layer.hide()
	apply_motion()
	set_time(0.0)

## 将本实例的配置施加到共享 shader；越过已核对包络即拒绝。
func apply_motion() -> void:
	assert(absf(motion.boat.heave_px) <= motion.limits.max_heave_px)
	assert(absf(motion.boat.roll_degrees) <= motion.limits.max_roll_degrees)
	assert(absf(motion.boat.sway_px) <= motion.limits.max_sway_px)
	assert(motion.water.displacement_px <= motion.limits.max_water_displacement_px)
	var values := {"motion_enabled":motion.enabled,"boat_enabled":motion.boat.enabled,"water_enabled":motion.water.enabled,"contact_enabled":motion.contact.enabled,"pivot":Vector2(motion.boat.pivot[0],motion.boat.pivot[1]),"heave_px":motion.boat.heave_px,"sway_px":motion.boat.sway_px,"roll_radians":deg_to_rad(motion.boat.roll_degrees),"phase_offset":motion.boat.phase_offset,"water_displacement_px":motion.water.displacement_px,"water_glint":motion.water.glint_strength,"wave_lengths":Vector2(motion.water.wave_lengths[0],motion.water.wave_lengths[1]),"contact_width":motion.contact.width_px,"contact_strength":motion.contact.strength} # 全部运行调参入口。
	for key: String in values:
		harbor_material.set_shader_parameter(key,values[key])

## [param progress] 为统一时态0～1；与动态相位独立。
func set_time(progress: float) -> void:
	time_progress = clampf(progress,0.0,1.0)
	var values: Dictionary = sampler.sample(profile,time_progress) # 全景同一时段。
	light_material.set_shader_parameter("enabled",true)
	for key: String in values:
		light_material.set_shader_parameter(key,values[key])
	harbor_material.set_shader_parameter("water_time_gain",lerpf(1.0,float(motion.water.night_gain),time_progress))

## [param phase] 为可重复的周期进度；不读取系统时钟。
func set_phase(phase: float) -> void:
	harbor_material.set_shader_parameter("phase",phase)
	if wind_controller != null:
		wind_controller.set_elapsed(phase*float(motion.loop_seconds))

## [param enabled] 控制全部港口动态；关闭直接返回静态受光源。
func set_motion_enabled(enabled: bool) -> void:
	harbor_material.set_shader_parameter("motion_enabled",enabled)

## [param seconds] 为调用者提供的连续运行秒数；周期统一来自 motion.json。
func set_elapsed(seconds: float) -> void:
	assert(float(motion.loop_seconds) > 0.0)
	harbor_material.set_shader_parameter("phase",fposmod(seconds/float(motion.loop_seconds),1.0))
	if wind_controller != null:
		wind_controller.set_elapsed(seconds)

## [param enabled] 切换新增风动，不修改港口基线开关。
func set_wind_enabled(enabled: bool) -> void:
	if wind_controller != null:
		wind_controller.set_enabled(enabled)

## [param id] 指定入口；[param mode] 为可用状态；[param pressed] 只改变短按表现。
func set_entry_hover(id: String, mode: String, pressed: bool=false) -> void:
	if entry_highlight != null:
		entry_highlight.set_target(id,mode,pressed)

## [param delta] 独立推进交互过渡，不重置船或风的计时。
func advance_entry_hover(delta: float) -> void:
	if entry_highlight != null:
		entry_highlight.advance(delta)
