## 动能弹沿真实路径加速，绘制过去的弹体位置形成幻影；沿用原受击、护甲与地形碰撞。
extends BulletLinear000Base

## 从原速到最高速的时长，单位为游戏秒。
const RAMP_SECONDS: float = 1.5
## 最高为出膛速度两倍，伤害从100%随速度线性增加到200%。
const TOP_MULTIPLIER: float = 2.0
## 支路斜向入行的水平跨度，单位为世界像素。斜段也按真实距离积分。
const ENTRY_WIDTH: float = 88.0
## 常规帧由现有 Area2D 碰撞处理；长步才启用扫掠，防倍速和大时间步穿过薄受击框。
const SWEEP_STEP: float = 12.0
## 画面重放的最新有效年龄；1.75秒后所有幻影也已进入等速直线。
const FINAL_VISUAL_AGE: float = 1.75
## 五个窄面片共用网格和材质，每颗弹只上传一组飞行参数。
const GHOST_SHADER = preload("res://shaders/adventure/three_pea_kinetic_ghost.gdshader")

## 首枚动能弹出现时共享的绘制资源。
static var _mesh: ArrayMesh
static var _ghost_material: ShaderMaterial

## 发射时的冻结战场地形，传给长步扫掠。
var terrain: MainGameSlope
## 出膛速度，物理更新只写当前速度。
var _launch_speed: float = 300.0
## 已完成的游戏飞行秒。
var _age: float = 0.0
## 邻行入口的实际路径和长度；本行从一开始便按水平线飞行。
var _entry := Vector2.ZERO
var _entry_length: float = 0.0
## 仅在原物理步长不够安全时构造几何辅助，平常不重复宽相查询。
var _sweep: BloomerangFlightQuery

## 保留原生碰撞和命中配置，弹体和幻影由同一画布节点绘制。
func _ready() -> void:
	super()
	_launch_speed = speed
	bullet_shadow.hide()
	if _mesh == null:
		_mesh = _create_mesh()
		_ghost_material = ShaderMaterial.new()
		_ghost_material.shader = GHOST_SHADER
	material = _ghost_material
	if finisher_highlight:
		set_instance_shader_parameter(&"final_round", true)
	_publish_visual()

## 接收发射器指定的 [param target_y]，以实际行距替代固定格高。
func change_y(target_y: float):
	_entry = Vector2(signf(direction.x) * ENTRY_WIDTH, target_y - global_position.y)
	_entry_length = _entry.length()
	_publish_visual()

## 返回当前0至1的加速进度，1.5游戏秒恰好达到1。
func kinetic_progress() -> float:
	return clampf((speed / _launch_speed - 1.0) / (TOP_MULTIPLIER - 1.0), 0.0, 1.0)

## 单调的原伤害乘数。[param enemy] 仅由原生命中流程提供，不改变速度公式。
func _modify_impact_damage(damage: int, _enemy: Character000Base) -> int:
	return roundi(damage * (1.0 + kinetic_progress()))

## 按已走过的真实距离计算 [param at] 秒的位置；入行时也遵守同一速度曲线。
func _offset_at(at: float) -> Vector2:
	var traveled: float = _distance_at(at) # 斜段和横段共享同一个时间积分。
	var straight := Vector2(signf(direction.x) * maxf(0.0, traveled - _entry_length), 0.0) # 到达本路后的距离。
	return straight if _entry_length == 0.0 else straight + _entry * minf(1.0, traveled / _entry_length)

## 对速度积分求 [param at] 秒的位置；精确处理刚好跨过1.5秒的物理步。
func _distance_at(at: float) -> float:
	var ramp: float = clampf(at, 0.0, RAMP_SECONDS) # 在上限前为匀加速运动。
	return _launch_speed * (ramp + (TOP_MULTIPLIER - 1.0) * ramp * ramp / (2.0 * RAMP_SECONDS) \
		+ TOP_MULTIPLIER * maxf(0.0, at - RAMP_SECONDS))

## [param delta] 为可暂停的游戏时间。速度与伤害在同一时间点取样。
func _physics_process(delta: float) -> void:
	if not is_attack_active() or is_queued_for_deletion():
		queue_free()
		return
	var previous: float = _age # 两时刻差量同时驱动实弹和历史位置的幻影。
	_age += delta
	speed = _launch_speed * lerpf(1.0, TOP_MULTIPLIER, clampf(_age / RAMP_SECONDS, 0.0, 1.0))
	var start: Vector2 = global_position # 可能已经随甲板发生合法平移。
	var motion: Vector2 = _offset_at(_age) - _offset_at(previous) # 游戏帧内实际走过的世界轨迹。
	if motion.length_squared() > SWEEP_STEP * SWEEP_STEP and _test_long_step(start, start + motion, previous):
		return
	global_position = start + motion
	if global_position.distance_squared_to(start_world_position) > max_distance * max_distance:
		queue_free()
	elif previous < FINAL_VISUAL_AGE:
		_publish_visual()

## 只在超长物理步中补测 [param start] 至 [param finish]；较近目标比墙后目标先结算。
## [param previous] 是该步起始时刻。返回是否已命中真实目标或地形。
func _test_long_step(start: Vector2, finish: Vector2, previous: float) -> bool:
	var stop: Vector2 = terrain.first_projectile_contact(start, finish, lane) if is_instance_valid(terrain) else finish # 地形挡住以后不查墙后。
	if _sweep == null:
		_sweep = BloomerangFlightQuery.new()
	for entry: Dictionary in _sweep.contacts(self, start, stop, 512): # 使用同一原生敌方真实受击层。
		var area: Area2D = entry["area"] # 已按真实首次接触距离排序。
		if not is_instance_valid(area) or not area.monitorable:
			continue
		var enemy := area.owner as Character000Base # 原生命中资格保留阵营、状态和分行。
		if not _can_attack_character(enemy) or enemy.is_hypno:
			continue
		var fraction: float = float(entry["fraction"]) # 本步首次命中点内插对应弹速。
		var stop_ratio: float = start.distance_to(stop) / start.distance_to(finish) # 地形先缩短扫掠再得到原步比例。
		_age = lerpf(previous, _age, fraction * stop_ratio)
		speed = _launch_speed * lerpf(1.0, TOP_MULTIPLIER, clampf(_age / RAMP_SECONDS, 0.0, 1.0))
		global_position = start.lerp(stop, fraction)
		attack_once(enemy)
		return true
	if not stop.is_equal_approx(finish):
		global_position = stop
		queue_free()
		return true
	return false

## 上传本帧的飞行信息，不重新提交网格、图像或碰撞。
func _publish_visual() -> void:
	set_instance_shader_parameter(&"flight", Vector4(minf(_age, FINAL_VISUAL_AGE), _entry.x, _entry.y,
		signf(direction.x) * _launch_speed))

## 每发在一次绘制内给相同网格；位置与辉光由该发的独立参数驱动。
func _draw() -> void:
	if _mesh != null:
		draw_mesh(_mesh, null)

## 只创建一次的五枚窄四边形。UV 的整数纵坐标标记第几层幻影。
static func _create_mesh() -> ArrayMesh:
	var vertices := PackedVector2Array() # 面片先定义局部形状，位移在顶点着色器内完成。
	var uvs := PackedVector2Array() # 各自使用相同的软光轮廓。
	var indices := PackedInt32Array() # 每层刚好两个三角形，远处先画。
	for stamp: int in range(4, -1, -1): # 弹头覆盖较远的拖影。
		var base: int = vertices.size() # 此层索引从本面片第一点开始。
		vertices.append_array(PackedVector2Array([Vector2(-14.0, -11.0), Vector2(14.0, -11.0),
			Vector2(14.0, 11.0), Vector2(-14.0, 11.0)]))
		uvs.append_array(PackedVector2Array([Vector2(0.0, stamp + 0.1), Vector2(1.0, stamp + 0.1),
			Vector2(1.0, stamp + 0.9), Vector2(0.0, stamp + 0.9)]))
		indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	var arrays: Array = [] # ArrayMesh 的二维顶点数据槽。
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new() # 每种转职弹型只持有这一份网格。
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.custom_aabb = AABB(Vector3(-140.0, -140.0, -1.0), Vector3(280.0, 280.0, 2.0)) # 包括顶点动画移动的拖影。
	return mesh
