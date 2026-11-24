## 图形回归。直接读取独立小视口验证 GPU 射线几何和逐灯通道，使用 GL Compatibility 运行。
extends SceneTree

## 投影实例表与细分网格。
const Ground = preload("res://scripts/battle/environment/battle_shadow_ground.gd")
## CPU 选择主灯使用的源数据。
const Light = preload("res://scripts/battle/environment/battle_light_source.gd")
## 与板面标定一致的地面横轴。
const AXIS := Vector2(1.0, 0.22)
## 测试的原始裁切范围。
const POSE := Rect2(-18, -80, 36, 80)
## 使上部与躯干拥有可分辨的延伸量。
const BODY := 60.0
## 虚拟灯高。
const HEIGHT := 100.0
## 每格的名义世界可见半径。
const REACH := 150.0

## 等主视口初始化后再创建图形测试用例。
func _initialize() -> void:
	call_deferred("_run")

## 所有断言成功后输出并退出。
func _run() -> void:
	if not await _check_geometry() or not await _check_channels():
		quit(1)
		return
	print("PASS test_church_shadow_geometry")
	quit()

## 创建 [param size] 的独立透明视口与一个材质为 [param shader] 的批次。
func _batch(size: Vector2i, shader: Shader) -> MultiMeshInstance2D:
	var viewport := SubViewport.new() # 测试专用纹理，避免读取游戏窗口。
	viewport.size = size
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var batch := MultiMeshInstance2D.new() # 共用一个真实 CanvasItem 批次。
	batch.multimesh = MultiMesh.new()
	batch.multimesh.use_custom_data = true
	var material := ShaderMaterial.new() # 不修改生产资源。
	material.shader = shader
	batch.material = material
	viewport.add_child(batch)
	return batch

## 用实测的头部标记与解析射线交点对照，过零时长影的面积必须消失。
func _check_geometry() -> bool:
	var shader := Shader.new() # 与生产着色器共用顶点函数，保留可测的颜色标记。
	shader.code = """
shader_type canvas_item;
render_mode unshaded;
#include "res://shaders/environment/battle_shadow_ground.gdshaderinc"
varying vec2 source_uv;
void vertex() {
	GroundVertex projected = project_ground_vertex(INSTANCE_ID, UV);
	VERTEX = projected.position;
	source_uv = projected.pose_uv;
}
void fragment() {
	vec2 marker = (source_uv - vec2(0.5, 0.24)) / vec2(0.21, 0.09);
	COLOR = vec4(vec3(1.0), 1.0 - smoothstep(0.35, 1.0, length(marker)));
}
"""
	var batch: MultiMeshInstance2D = _batch(Ground.LIGHT_GRID * Ground.LIGHT_TILE, shader) # 实际纹理参数实例表。
	var projector := Ground.new() # 直接使用生产的上传通道。
	var feet: Array[Vector2] = [Vector2(60, 0), Vector2.ZERO, Vector2(-60, 0), Vector2(34, -49)] # 左右、过零与错纵深。
	projector.configure(batch, feet.size(), AXIS)
	for index: int in range(feet.size()): # 一个灯格一个角色，能检查实例地址。
		var light := Light.new() # 测试灯共用虚拟高度，地面垂足为原点。
		light.height = HEIGHT
		light.reach = REACH
		light.shadow_slot = index
		projector.submit(feet[index], POSE, Vector2i.ZERO, POSE.size.y, BODY, light, 1.0, 500.0)
	projector.flush()
	await RenderingServer.frame_post_draw
	var frame: Image = batch.get_viewport().get_texture().get_image() # 只在验收脚本中读取 GPU。
	for index: int in range(feet.size()): # 对比每个灯格的实测位置。
		var start := Vector2i(index * Ground.LIGHT_TILE, 0) # 灯格左上角。
		var centroid := Vector2.ZERO # 红色标记的可见像素积分位置。
		var count := 0 # 用于检验灯脚重合时的退化面积。
		for y: int in range(Ground.LIGHT_TILE): # 读取单个局部灯格。
			for x: int in range(Ground.LIGHT_TILE): # 解析像素中心。
				var pixel: Vector2i = start + Vector2i(x, y) # 实测纹理像素。
				if frame.get_pixelv(pixel).a > 0.46:
					centroid += Vector2(pixel) + Vector2(0.5, 0.5)
					count += 1
		var h: float = BODY * (1.0 - 0.24) # 头部标记的实际虚拟高度。
		var expected: Vector2 = Vector2(start) + Vector2.ONE * (Ground.LIGHT_TILE * 0.5) \
			+ feet[index] * (1.0 + h / (HEIGHT - h)) * (Ground.LIGHT_INNER / (2.0 * REACH)) # 中线解析值。
		if (index == 1 and count > 1) or (index != 1 and (count == 0 or (centroid / maxi(count, 1)).distance_to(expected) > 1.8)):
			push_error("GPU shadow geometry failed for " + str(feet[index]))
			return false
	batch.get_viewport().queue_free()
	return true

## 单盏灯的局部遮挡不得改变另一盏灯和鼠标光。遮挡只在地面上半区生效。
func _check_channels() -> bool:
	var batch: MultiMeshInstance2D = _batch(Vector2i(64, 64), preload("res://shaders/environment/battle_visibility_light.gdshader")) # 生产灯片。
	var material := batch.material as ShaderMaterial # 固定半格遮挡用来检查阴影纵轴。
	var mask := Image.create_empty(384, 384, false, Image.FORMAT_RGBA8) # 仅第一盏暖灯的上半格遮挡。
	mask.fill_rect(Rect2i(1, 1, 94, 45), Color.WHITE)
	material.set_shader_parameter(&"shadow_mask", ImageTexture.create_from_image(mask))
	batch.multimesh.mesh = QuadMesh.new()
	batch.multimesh.mesh.size = Vector2(2.0, 2.0)
	batch.multimesh.instance_count = 3
	for index: int in range(3): # 三个灯片位置相同，因此可解析 Alpha 合成。
		batch.multimesh.set_instance_transform_2d(index, Transform2D(0.0, Vector2.ONE * 25.0, 0.0, Vector2(32.0, 32.0)))
		batch.multimesh.set_instance_custom_data(index, Color(float(index > 0), 0.0, 0.0, [0.30, 0.60, 0.40][index]))
	await RenderingServer.frame_post_draw
	var original: Image = batch.get_viewport().get_texture().get_image() # 无遮挡基准光场。
	batch.multimesh.set_instance_custom_data(1, Color(1.0, 0.0, 1.0 / 255.0, 0.60))
	await RenderingServer.frame_post_draw
	var masked: Image = batch.get_viewport().get_texture().get_image() # 同一个暖光位置的局部遮挡。
	var top := Vector2i(31, 28) # 第一盏灯应该扣光的位置。
	var bottom := Vector2i(31, 35) # 垂直镜像误差会错误扣掉这里。
	var before: Color = original.get_pixelv(top) # R 与 G 是原始暖光及微光。
	var after: Color = masked.get_pixelv(top) # B 只剩第二盏灯。
	var stable := Light.new() # 用 CPU 覆盖函数验证保留下来的那一盏。
	stable.tone = 1
	stable.center = Vector2(32.0, 32.0)
	stable.radius = 25.0 / Light.EDGE_MARGIN
	stable.intensity = 0.40
	var expected_fill: float = stable.coverage_at(Vector2(top) + Vector2(0.5, 0.5)) # 未被第一盏灯遮掉的补光。
	if absf(before.r - after.r) > 0.005 or absf(before.g - after.g) > 0.005 \
			or absf(after.b - expected_fill) > 0.015 or after.b > before.b - 0.15 \
			or not original.get_pixelv(bottom).is_equal_approx(masked.get_pixelv(bottom)):
		push_error("Lamp isolation or receiver alignment failed: " + str([before, after, expected_fill]))
		return false
	return true
