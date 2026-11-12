extends RefCounted
## 可选建筑视觉层：配置与遮罩独立于输入，不复制风/船运动公式。
## 唯一高亮材质。
var material: ShaderMaterial
## 可编辑表现参数。
var style: Dictionary
## 入口对应的已加载可见蒙版。
var masks: Dictionary = {}
## 当前作用入口与目标强度。
var active_id := ""
var desired := 0.0
## 当前平滑强度。
var amount := 0.0

## [param host] 提供原生纹理/视口工厂；返回原受光之后的新视口，缺配置则直接透传。
func configure(host: Node, folder: String, source: SubViewport) -> SubViewport:
	if not FileAccess.file_exists(folder.path_join("config/entries.json")):
		return source
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("config/entries.json"))) # 权威入口表现。
	style = data.style
	for entry: Dictionary in data.entries:
		masks[entry.id] = host.texture_file(folder.path_join("entry_assets/"+entry.id+".png"))
	var view: SubViewport = host.make_view(source.size) # 不含任何UI。
	var display: TextureRect = host.artwork(view,source.get_texture()) # 既有像素，关闭时完全透传。
	var shader := Shader.new() # 沿动态链传递高亮颜色。
	shader.code = load("res://shaders/ui/main_menu/entry_highlight.gdshader").code
	material = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("entry_mask",masks[data.entries[0].id])
	material.set_shader_parameter("fill_gain",float(style.fill_gain))
	material.set_shader_parameter("inner_edge_gain",float(style.inner_edge_gain))
	display.material = material
	return view

## [param id] 为空表示离开；[param mode] 区分可进入/不可进入，[param pressed] 为按下反馈。
func set_target(id: String, mode: String, pressed: bool=false) -> void:
	if material == null:
		return
	if id.is_empty() or not masks.has(id):
		desired = 0.0
		return
	if active_id != id:
		active_id = id
		amount = 0.0
		material.set_shader_parameter("strength",amount) # 切换蒙版与强度同帧提交，防止上一入口的亮度闪到新目标。
		material.set_shader_parameter("entry_mask",masks[id])
	var rgb: Array = style.available_color if mode == "available" else style.locked_color # 锁定/未开放反馈克制。
	material.set_shader_parameter("accent",Vector3(rgb[0],rgb[1],rgb[2]))
	desired = (1.0 if mode == "available" else float(style.locked_strength)) * (float(style.pressed_multiplier) if pressed else 1.0)

## [param delta] 为显式推进秒数；正常运行用delta，录像用固定帧时长。
func advance(delta: float) -> void:
	if material == null:
		return
	var duration: float = style.fade_in_seconds if desired>amount else style.fade_out_seconds # 同一实例可中断过渡。
	amount = move_toward(amount,desired,delta/maxf(duration,.001))
	material.set_shader_parameter("strength",amount)
