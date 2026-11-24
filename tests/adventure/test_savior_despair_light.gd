## 用 GL 光场验证局部红晕的边缘裁切和路灯花变体。
extends SceneTree

## 教堂已有的共享灯片材质。
const MASK_SHADER := "res://shaders/environment/battle_visibility_light.gdshader"
## 教堂真实登记与光场绘制。
const FIELD_SCRIPT := "res://scripts/battle/environment/battle_visibility_light_field.gd"

## Autoload 就绪后才构建光场。
func _initialize() -> void:
	_run.call_deferred()

## 提交有偏心的受击范围，在实际红光纹理上检查裁剪、吸收与外侧纯黑。
func _run() -> void:
	var field = load(FIELD_SCRIPT).new() # 真实四分之一分辨率光场，不需要独立测试着色器。
	var world := Node2D.new() # 模拟真实战场承载发光点。
	var anchor := Marker2D.new() # 投影垂足也是发光点。
	var red := SubViewport.new() # 与场景相同的红光子视口。
	var material := ShaderMaterial.new() # 两种灯批次共用一份材质。
	material.shader = load(MASK_SHADER)
	red.name = &"RedMask"
	red.transparent_bg = true
	red.disable_3d = true
	red.render_target_update_mode = SubViewport.UPDATE_DISABLED
	red.add_child(_make_batch(material, true))
	field.add_child(_make_batch(material, false))
	field.add_child(red)
	world.add_child(anchor)
	root.add_child(world)
	root.add_child(field)
	anchor.position = Vector2(148, 124)
	field.register_light(anchor, field.Tone.RED, 98.0, Vector2.ZERO, anchor, 54.0, 8.0, 1.0, false)
	var rect := Rect2(120, 80, 76, 104) # 右下边与左上边距灯心不同，测试真实裁剪坐标。
	var point_inside := Vector2i(42, 31) # 红光纹理的 42 列约对应世界 x=170。
	var point_outside := Vector2i(52, 31) # 刚超出裁剪区域且仍处于同一盏灯名义半径内。
	var view := Rect2(0, 0, 320, 240) # 光场会从实际视口比例推导纹理大小。
	var id: int = anchor.get_instance_id() # 此次施法复用同一个灯。
	field.set_red_light_shape(id, Vector2.ZERO, 98.0, 54.0, rect)
	field.render_lights(view, Transform2D.IDENTITY, 0.0)
	await process_frame
	RenderingServer.force_draw(false)
	var dry: Image = field.red_texture().get_image() # GPU 记录的实际局部散晕。
	if dry == null or dry.get_pixelv(point_inside).b < 0.44 or dry.get_pixelv(point_outside).b > 0.01:
		_fail("红色散晕必须照亮真实裁剪范围且在边缘外消失")
		return
	if dry.get_pixelv(point_inside).g > 0.01:
		_fail("普通散晕没有吸收强度")
		return
	field.set_red_light_shape(id, Vector2.ZERO, 98.0, 54.0, rect, 1.0)
	field.render_lights(view, Transform2D.IDENTITY, 0.08)
	await process_frame
	RenderingServer.force_draw(false)
	var spread: Image = field.red_texture().get_image() # 同样大小下检验亮度确实从中心让给外围。
	var center := Vector2i(37, 31) # 实际光罩中的格心。
	if spread.get_pixelv(center).b > dry.get_pixelv(center).b * 0.56 or spread.get_pixelv(point_outside).b > 0.01:
		_fail("扩散后的红晕中心应变弱且仍受同一范围裁剪")
		return
	field.set_red_light_shape(id, Vector2.ZERO, 98.0, 54.0, rect, 0.0, true)
	field.render_lights(view, Transform2D.IDENTITY, 0.1)
	await process_frame
	RenderingServer.force_draw(false)
	var caught: Image = field.red_texture().get_image() # 同一光晕被标记为灯罩吸收。
	if caught.get_pixelv(point_inside).g < 0.44 or caught.get_pixelv(point_outside).g > 0.01:
		_fail("吸收亮度要和真的红晕落在同一区域")
		return
	field.unregister_light(id)
	if field.render_lights(view, Transform2D.IDENTITY, 0.65):
		_fail("退场后的红晕仍在光场中")
		return
	world.queue_free()
	field.queue_free()
	await process_frame
	print("DESPAIR_LIGHT_OK")
	quit()

## 以 [param material] 构造实际灯片。[param red] 允许红光批次用颜色提交局部裁剪值。
func _make_batch(material: ShaderMaterial, red: bool) -> MultiMeshInstance2D:
	var quad := QuadMesh.new() # 与生产场景相同的标准四边形。
	quad.size = Vector2(2, 2)
	var mesh := MultiMesh.new() # 光场按可见光源分配实例。
	mesh.use_colors = red
	mesh.use_custom_data = true
	mesh.mesh = quad
	var batch := MultiMeshInstance2D.new() # 仅用来采样正式灯片。
	batch.name = &"LightBatch"
	batch.material = material
	batch.multimesh = mesh
	return batch

## [param reason] 给出失败的可见结果。
func _fail(reason: String) -> void:
	push_error("DESPAIR_LIGHT: " + reason)
	quit(1)
