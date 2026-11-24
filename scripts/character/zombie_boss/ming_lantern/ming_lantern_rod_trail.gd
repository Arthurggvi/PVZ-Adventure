## 灯条在水中留下的发光尾迹。灯管尾端牵引近处流束，远处随水流卷曲、上浮并扩散。
extends Node2D
class_name MingLanternRodTrail

## 光芯、雾边和旋流在一张连续的带状网格内混合。
const WATER_TRAIL: Shader = preload("res://shaders/adventure/wonderland/ming_lantern_rod_trail.gdshader")
## 每段水光的寿命，单位为战斗秒。
const PERSISTENCE := 1.42
## 沿路径的横截面数。近端不依赖帧历史，低帧率下也能与灯身接合。
const SECTIONS := 48

## 尾迹的光源。灯条提前移除时在最后一次接点处继续消散。
var rod: MingLanternRod
## 从灯条生成起经过的战斗秒，暂停时与实体一起停止。
var _age := 0.0
## 最后一段水光写入的时刻，坠落结束后保持不变。
var _latest := 0.0
## 初始灯管轴线，光源释放后仍供历史轨迹使用。
var _flight_axis := Vector2.UP
## 属于这根灯条的水流相位，避免相邻拖尾同相形变。
var _phase := 0.0
## 灯管尾端在本节点内的姿态。原点随实体更新，X 轴沿尾迹的出射方向。
var _attachment := Transform2D.IDENTITY
## 轨迹至少有两段有效截面时才绘制和投光。
var _visible_trail := false
## 控制当前尾迹内部的流纹、亮芯衰减与水雾。
var _shader_material: ShaderMaterial
## 横截面中心，与场景照明共用。
var _centers := PackedVector2Array()
## 每个横截面的左右边缘，按从旧到新的顺序排列。
var _vertices := PackedVector2Array()
## 每个顶点的透明度承载该段光强。RGB 保持白色，供材质着色。
var _colors := PackedColorArray()
## 横轴为该段水光的年龄占比，纵轴从流束的一侧过渡到另一侧。
var _uvs := PackedVector2Array()
## 相邻横截面之间的两片三角形，整段寿命内共用拓扑。
var _indices := PackedInt32Array()

## 初始化带状网格与本实例的水流材质。
func _ready() -> void:
	_flight_axis = rod.flight_axis
	_phase = _flight_axis.x * 9.9
	_shader_material = ShaderMaterial.new()
	_shader_material.shader = WATER_TRAIL
	_shader_material.set_shader_parameter(&"phase", _phase)
	_shader_material.set_shader_parameter(&"lifetime", PERSISTENCE)
	material = _shader_material
	_centers.resize(SECTIONS)
	_vertices.resize(SECTIONS * 2)
	_colors.resize(SECTIONS * 2)
	_uvs.resize(SECTIONS * 2)
	for section: int in range(SECTIONS - 1): # 每一段连接前、后两个横截面。
		var vertex: int = section * 2 # 前截面左边缘的索引。
		_indices.append_array(PackedInt32Array([vertex, vertex + 1, vertex + 2, vertex + 1, vertex + 3, vertex + 2]))

## 实时下坠倍率与灯条一致，使历史轨迹接在真实灯尾。散开后恢复战斗秒。
var fall_rate: Callable

## 用 [param delta] 推进扩散，在灯条更新后读取真实尾端位置和方向。
func _process(delta: float) -> void:
	_age += delta * float(fall_rate.call()) if _age < MingLanternRod.FALL_TIME and fall_rate.is_valid() else delta
	if is_instance_valid(rod) and rod.is_inside_tree() and not rod.is_queued_for_deletion():
		_latest = minf(_age, MingLanternRod.FALL_TIME)
		_attachment = global_transform.affine_inverse() * rod.global_transform * rod.trail_attachment()
	if _age >= _latest + PERSISTENCE:
		queue_free()
		return
	var oldest: float = maxf(0.0, _age - PERSISTENCE) # 按段移除已经散光的最老部分。
	_visible_trail = _latest - oldest > 0.004
	if _visible_trail:
		_build_ribbon(oldest)
		_shader_material.set_shader_parameter(&"clock_seconds", _age)
	queue_redraw()

## 返回 [param birth] 写入的横截面中心。[param flight_end] 是理论轨迹的最新点。
## 近端沿真实灯尾的轴线接入，中段平滑过渡到自由卷曲的残迹。
func _center_at(birth: float, flight_end: Vector2) -> Vector2:
	var point: Vector2 = MingLanternRod.flight_trail_attachment(birth, _flight_axis) # 该截面刚被灯管写入水中时的位置。
	var age_ratio: float = (_age - birth) / PERSISTENCE # 从新生的 0 过渡到消散的 1。
	var diffusion: float = smoothstep(0.04, 0.86, age_ratio) # 水流逐渐拉动已远离光源的部分。
	var eddy: float = birth * 23.0 + age_ratio * 4.2 + _phase # 卷流由原路径位置和水光年龄共同驱动。
	var flow := Vector2(39.0 * sin(eddy) + 11.0 * sin(eddy * 1.81 + 0.9) + _flight_axis.x * age_ratio * 29.0,
		13.0 * cos(eddy * 0.96 - 0.5) - age_ratio * 44.0) * diffusion # 横向卷曲叠加缓慢浮升。
	var join: float = 1.0 - smoothstep(0.0, 0.105, _latest - birth) # 从灯身朝外逐渐释放约一成秒的尾迹。
	var aligned: Vector2 = _attachment.origin + _attachment.x * point.distance_to(flight_end) # 最后几段从灯管轴线上伸出。
	return (point + flow).lerp(aligned, join)

## 从 [param oldest] 开始生成连续的横截面。中段扩散变宽，首尾在透明处收口。
func _build_ribbon(oldest: float) -> void:
	var flight_end: Vector2 = MingLanternRod.flight_trail_attachment(_latest, _flight_axis) # 用同一理论路径估算灯尾附近的沿程距离。
	for section: int in range(SECTIONS): # 先求中心，使相邻中心可以为截面提供法线。
		var fraction: float = float(section) / (SECTIONS - 1) # 从最远端向灯管推进。
		_centers[section] = _center_at(lerpf(oldest, _latest, fraction), flight_end)

	for section: int in range(SECTIONS): # 每个横截面只计算一次宽度、方向和衰减。
		var fraction: float = float(section) / (SECTIONS - 1) # 与中心采样的沿程参数一致。
		var birth: float = lerpf(oldest, _latest, fraction) # 此截面最初进入水中的时刻。
		var age_ratio: float = clampf((_age - birth) / PERSISTENCE, 0.0, 1.0) # 供材质切换亮芯和散开的水雾。
		var center: Vector2 = _centers[section] # 同时供场景光照使用。
		var normal: Vector2 = (_centers[mini(section + 1, SECTIONS - 1)] - _centers[maxi(section - 1, 0)]).normalized().orthogonal() # 截面垂直于水流，形变时保持圆润。
		var distance: float = center.distance_to(_attachment.origin) # 透明收口落在灯管原画内部。
		var spread: float = smoothstep(0.12, 0.91, age_ratio) # 水光变旧时逐渐扩散。
		var folds: float = 0.90 + 0.10 * sin(birth * 27.0 + age_ratio * 2.4 + _phase) # 卷流导致不均匀的横截面。
		var half_width: float = lerpf(29.0, 54.0, spread) * folds * lerpf(0.40, 1.0, smoothstep(0.0, 62.0, distance)) # 单侧宽度，单位为局部像素。
		var opacity: float = (1.0 - smoothstep(0.04, 1.0, age_ratio)) * smoothstep(0.0, 0.26, fraction) \
			* smoothstep(0.0, 9.0, distance) # 尾端、寿命尽头和灯身内的接点都平滑消光。
		var vertex: int = section * 2 # 同一横截面使用相同年龄和透明度。
		_vertices[vertex] = center - normal * half_width
		_vertices[vertex + 1] = center + normal * half_width
		_uvs[vertex] = Vector2(age_ratio, 0.0)
		_uvs[vertex + 1] = Vector2(age_ratio, 1.0)
		_colors[vertex] = Color(1.0, 1.0, 1.0, opacity)
		_colors[vertex + 1] = _colors[vertex]

## 相邻截面共享顶点，发光、细纹与雾边一次合成。
func _draw() -> void:
	if _visible_trail:
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _indices, _vertices, _colors, _uvs)

## 让 [param lighting] 从水光带的同一组截面读取光照，随卷曲和寿命一起退去。
func draw_scene_light(lighting: MingLanternLighting) -> void:
	if not _visible_trail:
		return
	for section: int in [11, 21, 31, 41]: # 均匀覆盖可见的部分，四个投光点共用既有照明通道。
		var width: float = _centers[section].distance_to(_vertices[section * 2]) # 扩散后周围收到的反照更宽更淡。
		var intensity: float = _colors[section * 2].a * lerpf(0.21, 0.13, _uvs[section * 2].x) # 按可见水光同步衰减。
		lighting.cast(self, _centers[section], Vector2(79.0 + width, 105.0 + width), Color("36c8ff"), intensity)
