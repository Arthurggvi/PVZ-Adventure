## 给共享细分网格提交逐实例地面射线投影参数，所有灯共用一张局部遮挡图集。
extends RefCounted

## 光源位置、半径与遮挡槽位。
const LightSource = preload("res://scripts/battle/environment/battle_light_source.gd")
## 光源遮挡格的像素宽高，含四周各一像素隔离区。
const LIGHT_TILE := 96
## 每盏灯使用的实际绘制宽度。
const LIGHT_INNER := LIGHT_TILE - 2
## 支持 16 盏同时投影的暖灯，其余光源仍提供补光。
const LIGHT_GRID := Vector2i(4, 4)
## 共享竖向细分数。最后一条按实例对齐零高度脚线。
const HEIGHT_SEGMENTS := 10
## 横向细分数。减少同一条高度带在近侧与远侧的采样误差。
const WIDTH_SEGMENTS := 2
## 每个实例使用四个 RGBAF 参数像素，实例编号为行号。
const PARAM_TEXELS := 4

## 投影图集中的 MultiMesh 节点。
var _batch: MultiMeshInstance2D
## 当前帧的连续参数表，整批上传。
var _records := PackedFloat32Array()
## 顶点着色器读取的参数纹理。
var _table: ImageTexture
## 参数表最大行数。
var _capacity: int
## 当前有效投影实例数。
var count: int

## 初始化 [param batch] 并预分配 [param capacity] 个投影。
## [param horizontal_axis] 把原画横向长度映射到略倾斜的固定地面横轴。
func configure(batch: MultiMeshInstance2D, capacity: int, horizontal_axis: Vector2) -> void:
	_batch = batch
	_capacity = capacity
	_records.resize(PARAM_TEXELS * 4 * capacity)
	_table = ImageTexture.create_from_image(_parameter_image())
	var material := batch.material as ShaderMaterial # 参数表和网格均属于当前战场。
	material.set_shader_parameter(&"projector_instances", _table)
	material.set_shader_parameter(&"horizontal_ground_axis", horizontal_axis)
	var mesh: MultiMesh = batch.multimesh # 每个角色使用一份细分网格实例。
	mesh.mesh = make_mesh()
	mesh.instance_count = capacity
	mesh.visible_instance_count = 0
	mesh.custom_aabb = AABB(Vector3(0.0, 0.0, -1.0), Vector3(LIGHT_TILE * LIGHT_GRID.x, LIGHT_TILE * LIGHT_GRID.y, 2.0))

## 清空本帧投影计数，继续重用已分配的网格和参数表。
func begin() -> void:
	count = 0

## 提交脚点 [param foot]、图集相对矩形 [param pose] 和剪影格 [param tile]。
## [param reference_height] 是固定原画高度，[param body_height] 是对应虚拟高度。
## [param light] 提供地面垂足和局部遮挡格，[param opacity] 为遮挡率。
## [param extent] 限制灯高可使用的安全高度比例，避免远端无穷伸展。
func submit(foot: Vector2, pose: Rect2, tile: Vector2i, reference_height: float, body_height: float,
		light: LightSource, opacity: float, extent: float) -> void:
	var from_light: Vector2 = foot - light.ground # 射线使用地面垂足。
	var from_center: Vector2 = foot - light.center # 遮挡格以灯罩光圈圆心采样。
	var height_limit: float = minf(body_height, light.height * minf(0.82, extent / (extent + light.reach))) # 安全上界与姿势和脚点距离无关。
	_write(0, Vector4(pose.position.x, pose.position.y, pose.size.x, pose.size.y))
	_write(1, Vector4(from_light.x, from_light.y, body_height / reference_height, height_limit))
	_write(2, Vector4(from_center.x, from_center.y, light.height, light.reach))
	_write(3, Vector4(light.source_radius, 0.0, 0.0, 0.0))
	var slot := Vector2i(light.shadow_slot % LIGHT_GRID.x, light.shadow_slot / LIGHT_GRID.x) # 对应灯片在遮挡图集中的格。
	var scale_to_mask: float = LIGHT_INNER / (2.0 * light.reach) # 等比从世界单位换算到局部遮挡格像素。
	var center: Vector2 = Vector2(slot * LIGHT_TILE) + Vector2.ONE * (LIGHT_TILE * 0.5) # 遮挡格中心。
	var transform := Transform2D(0.0, Vector2.ONE * scale_to_mask, 0.0, center + from_center * scale_to_mask) # 顶点着色后只应用一次。
	_batch.multimesh.set_instance_transform_2d(count, transform)
	_batch.multimesh.set_instance_custom_data(count, Color(tile.x / 255.0, tile.y / 255.0, opacity, 1.0))
	count += 1

## 更新实例可见数及参数表，空批次无需上传。
func flush() -> void:
	_batch.multimesh.visible_instance_count = count
	if count > 0:
		_table.update(_parameter_image())

## 将 [param value] 写入当前实例的第 [param column] 个参数像素。
func _write(column: int, value: Vector4) -> void:
	var start: int = (count * PARAM_TEXELS + column) * 4 # RGBAF 像素的首通道。
	_records[start] = value.x
	_records[start + 1] = value.y
	_records[start + 2] = value.z
	_records[start + 3] = value.w

## 构造同一规格的参数纹理数据。
func _parameter_image() -> Image:
	return Image.create_from_data(PARAM_TEXELS, _capacity, false, Image.FORMAT_RGBAF, _records.to_byte_array())

## 构建 UV 自顶向下的共享细分网格，CanvasItem 顶点着色器按实例变形。
static func make_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array() # 局部平面，位置将在 GPU 上改写。
	var uvs := PackedVector2Array() # 每条高度带使用同一张剪影的 UV。
	var indices := PackedInt32Array() # 相邻格共用顶点。
	for row: int in range(HEIGHT_SEGMENTS + 1): # 从剪影顶部到脚线下缘。
		for column: int in range(WIDTH_SEGMENTS + 1): # 左缘、中线与右缘。
			var uv := Vector2(float(column) / WIDTH_SEGMENTS, float(row) / HEIGHT_SEGMENTS) # 整张剪影的高度参数。
			vertices.append(Vector3(uv.x * 2.0 - 1.0, uv.y * 2.0 - 1.0, 0.0))
			uvs.append(uv)
	for row: int in range(HEIGHT_SEGMENTS): # 垂直带。
		for column: int in range(WIDTH_SEGMENTS): # 带内左右各一格。
			var start: int = row * (WIDTH_SEGMENTS + 1) + column # 当前格左上顶点。
			var below: int = start + WIDTH_SEGMENTS + 1 # 当前格左下顶点。
			indices.append_array(PackedInt32Array([start, start + 1, below, start + 1, below + 1, below]))
	var arrays: Array = [] # Godot 的 ArrayMesh 顶点属性。
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new() # 场景内所有投影实例共用。
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
