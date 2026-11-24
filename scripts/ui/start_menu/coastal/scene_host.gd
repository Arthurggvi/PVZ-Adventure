extends Node
## 单一场景宿主：先实时受光，再由港口层采样；UI 与场景材质独立。
## 船体和船旗在制作母图坐标中的绘制范围。四周留出配置允许的最大位移和采样边缘。
const BOAT_DRAW_RECT := Rect2(1416.0, 150.0, 256.0, 315.0)
## 固定前景在制作母图中的绘制范围，覆盖码头贴图 alpha 包络及线性采样边缘。
const DOCK_DRAW_RECT := Rect2(1408.0, 350.0, 210.0, 130.0)

## 原始受光视口，所有时段只在此计算一次。
var lit_view: SubViewport
## 最终合成视口。
var output_view: SubViewport
## 既有统一光照材质。
var light_material: ShaderMaterial
## 港口底层材质，负责海面补图、动态水纹和接触亮边。
var harbor_material: ShaderMaterial
## 船体及旗帜材质，与海面共用船体相位。
var _boat_material: ShaderMaterial
## 固定前景材质，绘制顺序在船体之后。
var _dock_material: ShaderMaterial
## 海面动效关闭时一起隐藏的两张局部四边形。
var _harbor_overlays: Array[TextureRect] = []
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
## hover/光行为/水面效果的统一可调用门面；没有反向持有宿主。
var effects := preload("res://scripts/ui/start_menu/coastal/effect_controls.gd").new()
## 可显式重载的效果配置地址，制作目录未提供时使用中性默认。
var effect_profile_path := ""
## 缓存真实光照uniform声明；日周期不能写入由效果控制器拥有的倍率。
var _light_uniform_types: Dictionary={}
## 单实例纹理存储，避免同一母图重复占用显存。
var assets := preload("res://scripts/ui/start_menu/coastal/asset_store.gd").new()

## [param path] 是本工作目录图片；不触发生产游戏资源导入。
func texture_file(path: String) -> Texture2D:
	return assets.texture(path)

## [param path] 为小端 RGBA32F 文件，[param size] 为画布尺寸。
func float_texture(path: String, size: Vector2i) -> Texture2D:
	return assets.floating(path,size)

## [param size] 指定真实绘制尺寸；返回本宿主拥有的视口。
func make_view(size: Vector2i) -> SubViewport:
	var view := SubViewport.new() # 由宿主统一释放。
	view.size = size
	view.disable_3d = true
	view.use_hdr_2d = false
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	return view

## 将 [param texture] 绘制到 [param view] 的 [param bounds]。空范围使用整个画布。
func artwork(view: SubViewport, texture: Texture2D, bounds := Rect2()) -> TextureRect:
	var rect := TextureRect.new() # 只承载画面，不参与交互。
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.position = bounds.position
	rect.size = bounds.size if bounds.has_area() else Vector2(view.size)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	view.add_child(rect)
	return rect

## [param folder] 是资产工作目录；不读取存档或生产单例。
func configure(folder: String, include_preview_ui: bool=true) -> void:
	assets.configure(folder)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("config/pipeline.json"))) # 场景约定。
	var size := Vector2i(manifest.canvas[0],manifest.canvas[1]) # 母图真实尺寸。
	profile = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("config/time_profile.json")))
	motion = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("config/motion.json")))
	sampler = preload("res://scripts/ui/start_menu/coastal/time_profile.gd").new()
	lit_view = make_view(size)
	var base := artwork(lit_view,texture_file(folder.path_join("master_original.png"))) # 原图永不替换为夜景贴图。
	base.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var light_shader := Shader.new() # 沿用已批准受光算法。
	light_shader.code = load("res://shaders/ui/main_menu/relight.gdshader").code
	light_material = ShaderMaterial.new()
	light_material.shader = light_shader
	for declaration: Dictionary in light_shader.get_shader_uniform_list(): # 仅构建时枚举一次。
		_light_uniform_types[str(declaration.name)]=int(declaration.type)
	var inputs := {"base_working":"working_base.png","ground_finished":"ground_finished.png","normal_data":"maps/normal.png","control_data":"maps/controls.png","environment_data":"maps/environment.png","local_emission_data":"finish_maps/local_emission.png","source_halo_data":"finish_maps/source_halo.png"} # 共用受光输入。
	for key: String in inputs:
		light_material.set_shader_parameter(key,texture_file(folder.path_join(inputs[key])))
	light_material.set_shader_parameter("local_receiver_data",float_texture(folder.path_join("attenuation_maps/receivers.rgba32f"),size))
	for key: String in profile.reference:
		var value: Array = profile.reference[key] # 固定校准参数。
		light_material.set_shader_parameter(key,Vector3(value[0],value[1],value[2]))
	base.material = light_material
	entry_highlight = preload("res://scripts/ui/start_menu/coastal/entry_highlight.gd").new()
	var entry_source: SubViewport = entry_highlight.configure(self,folder,lit_view) # 共用原动态变换，无额外近似运动。
	wind_controller = preload("res://scripts/ui/start_menu/coastal/wind_layer.gd").new()
	var wind_view: SubViewport = wind_controller.configure(self,folder,entry_source) # 树/棚在船体变换之前处理。
	output_view = make_view(size)
	_configure_harbor(folder, wind_view.get_texture())
	ui_layer = Node2D.new()
	output_view.add_child(ui_layer)
	if include_preview_ui:
		for filename in ["layer_profile_proposed.png","layer_console_proposed.png","layer_toolbar_expanded.png"]:
			var rect := TextureRect.new() # 不使用场景材质的界面占位。
			rect.texture = texture_file(folder.path_join("ui/"+filename))
			rect.size = Vector2(size)
			ui_layer.add_child(rect)
	ui_layer.hide()
	apply_motion()
	effects.configure(entry_highlight,light_material,harbor_material,motion)
	effect_profile_path=folder.path_join("config/effect_profile.json")
	if FileAccess.file_exists(effect_profile_path):
		var result: Dictionary=effects.reload_file(effect_profile_path) # 错误配置不提交半个场景。
		assert(result.ok,str(result.get("error","Invalid effect profile")))
	set_time(0.0)

## 将 [param source] 的受光结果画入海面、活动船、固定码头三个有序绘制项。
## [param folder] 提供母图和技术贴图，各材质只绑定实际消费的输入。
func _configure_harbor(folder: String, source: Texture2D) -> void:
	var base := artwork(output_view, source) # 先重建静态底色并绘制海面。
	harbor_material = _harbor_pass(folder, "harbor", ["clean_light_uv", "boat_premult"])
	harbor_material.set_shader_parameter("clean_color", texture_file(folder.path_join("assets/clean_plate.png")))
	harbor_material.set_shader_parameter("masks", texture_file(folder.path_join("assets/harbor_masks.png")))
	base.material = harbor_material

	var boat := artwork(output_view, source, BOAT_DRAW_RECT) # 活动船在海面之后。
	_boat_material = _harbor_pass(folder, "harbor_boat", ["boat_premult", "boat_light_uv"], BOAT_DRAW_RECT)
	boat.material = _boat_material
	wind_controller.bind_flag(self, folder, _boat_material)

	var dock := artwork(output_view, source, DOCK_DRAW_RECT) # 固定码头仍在活动船之前景。
	_dock_material = _harbor_pass(folder, "harbor_dock", ["fixed_premult", "fixed_light_uv"], DOCK_DRAW_RECT)
	dock.material = _dock_material
	_harbor_overlays = [boat, dock]

## 从 [param folder] 绑定一份港口材质。 [param shader_name] 为仓内材质名。
## [param fields] 指定本层消费的浮点贴图名；[param bounds] 将局部矩形映射回全景 UV。
func _harbor_pass(folder: String, shader_name: String, fields: Array[String], bounds := Rect2()) -> ShaderMaterial:
	var size := output_view.size # 取光和入口描边用同一分辨率。
	var material := ShaderMaterial.new() # 每个场景有自己的相位与引导状态。
	material.shader = load("res://shaders/ui/main_menu/" + shader_name + ".gdshader")
	material.set_shader_parameter("canvas_pixels", Vector2(size))
	material.set_shader_parameter("master_color", texture_file(folder.path_join("master_original.png")))
	if entry_highlight.masks.has("harbor"):
		material.set_shader_parameter("entry_guide_mask", entry_highlight.masks["harbor"])
	for field: String in fields: # 参数名与技术场名称一致。
		material.set_shader_parameter(field, float_texture(folder.path_join("assets/" + field + ".rgba32f"), size))
	if bounds.has_area():
		var origin_uv := bounds.position / Vector2(size) # 局部四边形左上角在全景中的位置。
		var size_uv := bounds.size / Vector2(size) # 局部四边形在全景中的采样跨度。
		material.set_shader_parameter("region_uv", Vector4(origin_uv.x, origin_uv.y, size_uv.x, size_uv.y))
	return material

## 将本实例的配置施加到共享 shader；越过已核对包络即拒绝。
func apply_motion() -> void:
	assert(is_finite(float(motion.loop_seconds)) and float(motion.loop_seconds)>0.0)
	effects.water.default_period=float(motion.loop_seconds) # 未单独配置水周期时，热调motion后仍正确继承。
	effects.water.default_phase=float(motion.boat.phase_offset)
	assert(absf(motion.boat.heave_px) <= motion.limits.max_heave_px)
	assert(absf(motion.boat.roll_degrees) <= motion.limits.max_roll_degrees)
	assert(absf(motion.boat.sway_px) <= motion.limits.max_sway_px)
	assert(motion.water.displacement_px <= motion.limits.max_water_displacement_px)
	var boat_values := { # 水面接触亮边与船体必须使用同一组变换参数。
		"boat_enabled": motion.boat.enabled,
		"pivot": Vector2(motion.boat.pivot[0], motion.boat.pivot[1]),
		"heave_px": motion.boat.heave_px,
		"sway_px": motion.boat.sway_px,
		"roll_radians": deg_to_rad(motion.boat.roll_degrees),
		"phase_offset": motion.boat.phase_offset,
	}
	for key: String in boat_values: # 两个绘制项共享同一船位置。
		harbor_material.set_shader_parameter(key, boat_values[key])
		_boat_material.set_shader_parameter(key, boat_values[key])

	var water_values := { # 海面专有参数只提交给底层。
		"water_enabled": motion.water.enabled,
		"contact_enabled": motion.contact.enabled,
		"water_displacement_px": motion.water.displacement_px,
		"water_glint": motion.water.glint_strength,
		"wave_lengths": Vector2(motion.water.wave_lengths[0], motion.water.wave_lengths[1]),
		"contact_width": motion.contact.width_px,
		"contact_strength": motion.contact.strength,
	}
	for key: String in water_values: # 更新水面与接触亮边参数。
		harbor_material.set_shader_parameter(key, water_values[key])
	set_motion_enabled(motion.enabled)

## [param progress] 为统一时态0～1；与动态相位独立。
func set_time(progress: float) -> void:
	time_progress = clampf(progress,0.0,1.0)
	var values: Dictionary = sampler.sample(profile,time_progress) # 全景同一时段。
	apply_uniforms(values,lerpf(1.0,float(motion.water.night_gain),time_progress))

## [param values] 为统一场景参数；[param water_gain] 为水面夜间权重；完整验证成功返回true，失败不提交，不改变动作时间。
func apply_uniforms(values: Dictionary, water_gain: float) -> bool:
	var converted: Dictionary=preload("res://scripts/ui/start_menu/coastal/effect_uniforms.gd").scene_values(values,_light_uniform_types) # 先验证整个提交。
	if not converted.ok or not is_finite(water_gain):
		push_error(str(converted.get("error","Invalid water gain")))
		return false
	light_material.set_shader_parameter("enabled",true)
	for key: String in converted["values"]: # 只更新日周期拥有的参数。
		light_material.set_shader_parameter(key,converted["values"][key])
	harbor_material.set_shader_parameter("water_time_gain",water_gain)
	return true

## [param phase] 为可重复的周期进度；不读取系统时钟。
func set_phase(phase: float) -> void:
	harbor_material.set_shader_parameter("phase",phase)
	_boat_material.set_shader_parameter("phase",phase)
	effects.set_elapsed(phase*float(motion.loop_seconds))
	if wind_controller != null:
		wind_controller.set_elapsed(phase*float(motion.loop_seconds))

## [param enabled] 控制全部港口动态；关闭直接返回静态受光源。
func set_motion_enabled(enabled: bool) -> void:
	harbor_material.set_shader_parameter("motion_enabled",enabled)
	for overlay: TextureRect in _harbor_overlays: # 停用补底时由原画显示静止船和码头。
		overlay.visible = enabled

## [param seconds] 为调用者提供的连续运行秒数；周期统一来自 motion.json。
func set_elapsed(seconds: float) -> void:
	assert(float(motion.loop_seconds) > 0.0)
	var phase := fposmod(seconds / float(motion.loop_seconds), 1.0) # 船及其接触亮边共用相位。
	harbor_material.set_shader_parameter("phase", phase)
	_boat_material.set_shader_parameter("phase", phase)
	effects.set_elapsed(seconds)
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

## [param id] 为主入口；[param strength] 为与牌匾同步的内缘混色权重，范围为 0 至 1。
func set_entry_guide(id: String, strength: float) -> void:
	if id == "harbor":
		harbor_material.set_shader_parameter("entry_guide_strength",strength)
		_boat_material.set_shader_parameter("entry_guide_strength",strength)
		_dock_material.set_shader_parameter("entry_guide_strength",strength)

## [param delta] 独立推进交互过渡，不重置船或风的计时。
func advance_entry_hover(delta: float) -> void:
	if entry_highlight != null:
		entry_highlight.advance(delta)

## 从当前数据根重载效果配置；失败保留原状态并返回error，不修改文件。
func reload_effects() -> Dictionary:
	return effects.reload_file(effect_profile_path)
