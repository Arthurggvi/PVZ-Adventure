extends RefCounted
## 风场适配器：一个配置和时钟，驱动陆地材质及船局部旗帜。
## 可选配置为空时完全保留旧管线。
var settings: Dictionary = {}
## 同一风场所控制的材质实例。
var materials: Array[ShaderMaterial] = []
## 当前启用状态，与港口运动开关独立。
var active := false

## [param folder] 定位执行副本；[param filename] 指定模板，注入唯一公共风场函数。
static func shader_source(_folder: String, filename: String) -> String:
	var shader: Shader = load("res://shaders/ui/main_menu/"+filename) # 唯一仓内材质，支持原生include与导出。
	return shader.code


## [param host] 提供纹理/视口工厂；返回陆地效果后的实时视口。
func configure(host: Node, folder: String, input: SubViewport) -> SubViewport:
	if not FileAccess.file_exists(folder.path_join("config/wind.json")):
		return input
	settings = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("config/wind.json")))
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("config/wind_layout.json"))) # 固定点与包络。
	assert(settings.canopy.left_amplitude_px <= settings.limits.canopy_max_px)
	assert(settings.canopy.rear_amplitude_px <= settings.limits.canopy_max_px)
	assert(settings.awning.amplitude_px <= settings.limits.awning_max_px)
	assert(settings.flag.amplitude_px <= settings.limits.flag_max_px)
	var view: SubViewport = host.make_view(input.size) # 风动只作用于受光场景，UI不进入。
	var rect: TextureRect = host.artwork(view,input.get_texture()) # 沿用受光源。
	var shader := Shader.new() # 共享场函数在这里展开，只有一份源代码。
	shader.code = shader_source(folder,"land_wind.gdshader")
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("scene_color", rect.texture)
	rect.material = material
	var png := {"canopy_weights":"canopy_weights", "awning_plate":"awning_plate", "awning_support":"awning_support"} # 原图坐标权重。
	for uniform: String in png:
		material.set_shader_parameter(uniform,host.texture_file(folder.path_join("wind_assets/"+png[uniform]+".png")))
	material.set_shader_parameter("master_color",host.texture_file(folder.path_join("master_original.png")))
	for uniform: String in ["awning_premult","awning_light_uv","awning_plate_uv"]:
		material.set_shader_parameter(uniform,host.float_texture(folder.path_join("wind_assets/"+uniform+".rgba32f"),input.size))
	var canopy: Dictionary = settings.canopy # 部件响应不改变公共节奏。
	var cloth: Dictionary = settings.awning
	var shape: Dictionary = layout.awning
	var values := {"canvas_pixels":Vector2(input.size),"canopy_enabled":canopy.enabled,"canopy_amplitude":Vector2(canopy.left_amplitude_px,canopy.rear_amplitude_px),"canopy_delay":Vector2(canopy.left_phase,canopy.rear_phase),"canopy_scale":canopy.spatial_scale_px,"canopy_cycles":canopy.cycles,"awning_enabled":cloth.enabled,"awning_amplitude":cloth.amplitude_px,"awning_delay":cloth.phase,"awning_cycles":cloth.cycles,"awning_travel":cloth.travel_radians,"awning_horizontal":cloth.horizontal_fraction,"anchor_start":Vector2(shape.anchor_start[0],shape.anchor_start[1]),"anchor_end":Vector2(shape.anchor_end[0],shape.anchor_end[1]),"cloth_depth":shape.cloth_depth_px,"pin_band":shape.pin_band_px,"cloth_outward":Vector2(shape.outward_vector[0],shape.outward_vector[1]),"side_anchor_uv":shape.side_anchor_uv} # 所有调整均取配置。
	for name: String in values:
		material.set_shader_parameter(name,values[name])
	register_material(material)
	return view

## [param host] 的船旗在既有船局部坐标处理；不重复父级位移。
func bind_flag(host: Node, folder: String, material: ShaderMaterial) -> void:
	if settings.is_empty():
		return
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("config/wind_layout.json"))) # 旗杆固定端。
	var flag: Dictionary = settings.flag # 仅布料响应。
	var size := Vector2i(layout.canvas[0],layout.canvas[1]) # 资产实际尺寸。
	material.set_shader_parameter("boat_without_flag",host.float_texture(folder.path_join("wind_assets/boat_without_flag.rgba32f"),size))
	material.set_shader_parameter("flag_premult",host.float_texture(folder.path_join("wind_assets/flag_premult.rgba32f"),size))
	var values := {"flag_enabled":flag.enabled,"flag_amplitude":flag.amplitude_px,"flag_delay":flag.phase,"flag_cycles":flag.cycles,"flag_travel":flag.travel_radians,"flag_root_x":float(layout.flag.root_x),"flag_tip_x":float(layout.flag.tip_x)} # 根部不动，自由端权重递增。
	for name: String in values:
		material.set_shader_parameter(name,values[name])
	register_material(material)

## [param material] 注册后共享风向、强度与阵风；不创建独立计时器。
func register_material(material: ShaderMaterial) -> void:
	materials.append(material)
	material.set_shader_parameter("wind_strength",settings.field.strength)
	material.set_shader_parameter("wind_direction",Vector2(settings.field.direction[0],settings.field.direction[1]))
	material.set_shader_parameter("gust_depth",settings.field.gust_depth)
	material.set_shader_parameter("gust_cycles",settings.field.gust_cycles)
	set_enabled(settings.enabled)

## [param enabled] 只关闭新增风动，保留已经通过的港口。
func set_enabled(enabled: bool) -> void:
	active = enabled and not settings.is_empty()
	for material: ShaderMaterial in materials:
		material.set_shader_parameter("wind_enabled",active)

## [param seconds] 为显式运行秒数；暂停/回放通过调用者控制。
func set_elapsed(seconds: float) -> void:
	if settings.is_empty():
		return
	assert(float(settings.loop_seconds)>0.0)
	var angle := fposmod(seconds/float(settings.loop_seconds),1.0)*TAU # 与港口时钟共享秒数，周期可不同。
	for material: ShaderMaterial in materials:
		material.set_shader_parameter("wind_angle",angle)
