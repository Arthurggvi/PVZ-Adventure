## 验证实际裂隙网格的六束连续采样、冷却回收和容量边界。
extends SceneTree

## 位于虚拟地板内、能容纳六束的固定测试区域。
const FLOOR := Rect2(0.0, 0.0, 680.0, 560.0)
## 八十世界像素宽的规则格距。
const CELL_SPAN := 80.0
## 生产采样器从真实资源加载，用同一入口判断未实现的情况。
const GEOMETRY_PATH := "res://scripts/fx/savior_fissure_geometry.gd"

## 等待测试引擎完成初始化再提交网格资源。
func _initialize() -> void:
	_run.call_deferred()

## 执行三个独立的运行契约，失败时以非零状态结束。
func _run() -> void:
	var source: Script = load(GEOMETRY_PATH) # 生产几何脚本。
	if source == null:
		_fail("找不到可运行的裂隙几何实现")
		return
	if not _check_sampling(source) or not _check_cooling(source) \
			or not _check_exterior_retention(source) or not _check_capacity(source):
		return
	print("PASS test_savior_fissure_geometry")
	quit()

## [param source] 创建两个真实采样器。相同轨迹的不同帧分割应共享连贯的网格和出生时间。
func _check_sampling(source: Script) -> bool:
	var mesh_a := ArrayMesh.new() # 单帧跨过整段路径的实际网格。
	var mesh_b := ArrayMesh.new() # 小步推进完全相同路径的实际网格。
	var single: RefCounted = source.new() # 一次推进能够跨越多个格子。
	var divided: RefCounted = source.new() # 多次小步累积同样的弧长。
	var positions: PackedVector2Array = _points(Vector2(72.0, 52.0)) # 六束世界起点。
	for sampler: RefCounted in [single, divided]: # 共享相同开始帧与事先确定的棋盘几何。
		sampler.configure(CELL_SPAN, FLOOR)
		sampler.begin(positions, 0.0)
		sampler.sample(positions, 0.0)
	single.sample(_points(Vector2(232.0, 52.0)), 0.8)
	for step: int in range(1, 17): # 每五十毫秒以相同速度推进十个世界像素。
		divided.sample(_points(Vector2(72.0 + step * 10.0, 52.0)), step * 0.05)
	single.flush(mesh_a)
	divided.flush(mesh_b)
	var stats: Dictionary = single.profile_snapshot() # 生产统计应对应实际连片和分叉。
	if stats.strokes != 6 or stats.triangles < 180 or stats.active_branches < 1:
		return _fail("六束必须生成连续主纹和少量分叉")
	if mesh_a.get_surface_count() != 1 or mesh_b.get_surface_count() != 1:
		return _fail("六道网格应共享一个图元表面")
	var a: Array = mesh_a.surface_get_arrays(0) # 查询提交给渲染服务器的真实数组。
	var b: Array = mesh_b.surface_get_arrays(0) # 与细分输入的网格结果比较。
	var vertices_a: PackedVector2Array = a[Mesh.ARRAY_VERTEX] # 世界空间镶边顶点。
	var vertices_b: PackedVector2Array = b[Mesh.ARRAY_VERTEX] # 同一组弧长节点的镶边。
	var heat_a: PackedFloat32Array = a[Mesh.ARRAY_CUSTOM0] # 首通道为插值后的战斗出生时间。
	var heat_b: PackedFloat32Array = b[Mesh.ARRAY_CUSTOM0] # 同样的时序应与帧划分无关。
	if vertices_a.size() != vertices_b.size() or heat_a.size() != vertices_a.size() * 4 \
			or a[Mesh.ARRAY_INDEX] != b[Mesh.ARRAY_INDEX]:
		return _fail("同一条轨迹的网格拓扑随帧率变化")
	for index: int in range(vertices_a.size()): # 每个顶点包含稳定的横向位置及热量参数。
		if vertices_a[index].distance_to(vertices_b[index]) > 0.01 \
				or not is_equal_approx(heat_a[index * 4], heat_b[index * 4]):
			return _fail("同速轨迹的位置、分叉或出生时间随帧率变化")
	return true

## [param source] 的旧轨迹可与新施法共存，暂停没有几何上传，全部冷却后释放网格表面。
func _check_cooling(source: Script) -> bool:
	var sampler: RefCounted = source.new() # 使用同一缓存连续施法。
	var mesh := ArrayMesh.new() # 多轮轨迹复用同一资源。
	sampler.configure(CELL_SPAN, FLOOR)
	sampler.begin(_points(Vector2(72.0, 40.0)), 0.0)
	sampler.sample(_points(Vector2(72.0, 40.0)), 0.0)
	sampler.sample(_points(Vector2(192.0, 40.0)), 0.2)
	sampler.end()
	sampler.flush(mesh)
	var first: Dictionary = sampler.profile_snapshot() # 暂停前主纹和分叉的实际上传量。
	sampler.expire(0.2)
	sampler.flush(mesh)
	if sampler.profile_snapshot().uploads != first.uploads or first.triangles == 0:
		return _fail("冻结战斗时间或光柱退场时重绘或清空了余痕")
	sampler.begin(_points(Vector2(400.0, 40.0)), 1.5)
	sampler.sample(_points(Vector2(400.0, 40.0)), 1.5)
	sampler.sample(_points(Vector2(520.0, 40.0)), 1.6)
	sampler.end()
	sampler.flush(mesh)
	if sampler.profile_snapshot().strokes != 12:
		return _fail("重复施法吞掉了未熄灭的旧轨迹")
	sampler.expire(2.05)
	sampler.flush(mesh)
	if sampler.profile_snapshot().strokes != 6 or sampler.profile_snapshot().triangles == 0:
		return _fail("逐条按出生时间回收时误伤了新轨迹")
	sampler.expire(3.5)
	sampler.flush(mesh)
	if mesh.get_surface_count() != 0 or sampler.profile_snapshot().triangles != 0:
		return _fail("所有裂缝熄灭后仍提交三角形")
	return true

## [param source] 走完一段地表后在外侧长距离飞行，回到棋盘时保留旧余热且不横跨两段接线。
func _check_exterior_retention(source: Script) -> bool:
	var sampler: RefCounted = source.new() # 一条真实弧长输入已足以复现离场挤占。
	var mesh := ArrayMesh.new() # 检查重入后的实际顶点和拓扑。
	var origin := PackedVector2Array([Vector2(120.0, 132.0)]) # 上方石砖上开始出手。
	sampler.configure(CELL_SPAN, FLOOR)
	sampler.begin(origin, 0.0)
	sampler.sample(origin, 0.0)
	sampler.sample(PackedVector2Array([Vector2(420.0, 132.0)]), 0.30)
	sampler.sample(PackedVector2Array([Vector2(850.0, 132.0)]), 0.55)
	sampler.sample(PackedVector2Array([Vector2(2400.0, 132.0)]), 0.94)
	sampler.expire(0.94)
	sampler.flush(mesh)
	if mesh.get_surface_count() != 1:
		return _fail("尚未冷却的棋盘内裂隙被离场采样清空")
	var initial: Array = mesh.surface_get_arrays(0) # 把主纹与分叉按实际顶点属性分开检查。
	var vertices: PackedVector2Array = initial[Mesh.ARRAY_VERTEX] # 离场后的剩余可提交网格顶点。
	var heat: PackedFloat32Array = initial[Mesh.ARRAY_CUSTOM0] # 第三分量的大值代表主纹热源。
	var has_origin := false # 首段余热应当保持直到战斗时间到期。
	for index: int in range(vertices.size()): # 单条仍活跃主纹应继续到达出手处。
		has_origin = has_origin or (vertices[index].x < 130.0 and heat[index * 4 + 2] >= 0.69)
	if not has_origin:
		return _fail("尚未冷却的棋盘内裂隙被离场样点挤出容量")
	sampler.sample(PackedVector2Array([Vector2(2400.0, -200.0)]), 1.02)
	sampler.sample(PackedVector2Array([Vector2(-200.0, -200.0)]), 1.09)
	sampler.sample(PackedVector2Array([Vector2(-200.0, 450.0)]), 1.16)
	sampler.sample(PackedVector2Array([Vector2(350.0, 450.0)]), 1.24)
	sampler.flush(mesh)
	var reentered: Array = mesh.surface_get_arrays(0) # 棋盘内应有上、下两道相互独立的裂隙。
	vertices = reentered[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = reentered[Mesh.ARRAY_INDEX] # 实际送往 GPU 的三角形索引。
	var has_reentry := false # 确认新折线确实进入下方的区域。
	for start: int in range(0, indices.size(), 3): # 横过外侧的假接线将产生垂直跨度异常的三角形。
		var a: float = vertices[indices[start]].y # 本三角形第一个顶点。
		var b: float = vertices[indices[start + 1]].y # 本三角形第二个顶点。
		var c: float = vertices[indices[start + 2]].y # 本三角形第三个顶点。
		if maxf(a, maxf(b, c)) - minf(a, minf(b, c)) > 160.0:
			return _fail("离场后的再次入场没有分开索引条带")
		has_reentry = has_reentry or a > 430.0
	return has_reentry or _fail("离场后没有在返回棋盘时恢复采样")

## [param source] 的容量独立于帧间位移和施法次数，完全离场的几何不提交。
func _check_capacity(source: Script) -> bool:
	var sampler: RefCounted = source.new() # 连续高倍速且无暂停回收的压力实例。
	var mesh := ArrayMesh.new() # 要向渲染器提交的共享图元。
	sampler.configure(CELL_SPAN, FLOOR)
	sampler.begin(_points(Vector2(-5000.0, 40.0)), 0.0)
	sampler.sample(_points(Vector2(-5000.0, 40.0)), 0.0)
	sampler.sample(_points(Vector2(5000.0, 40.0)), 0.01)
	sampler.flush(mesh)
	if sampler.profile_snapshot().triangles <= 0:
		return _fail("两端离场的高速穿越漏掉了场内几何")
	for cast_index: int in range(12): # 最旧轨迹超限时先回收，活动内存有明确边界。
		var now: float = 0.1 + cast_index * 0.04 # 所有模拟施法的活动余热都重合。
		sampler.begin(_points(Vector2(52.0, 52.0)), now)
		sampler.sample(_points(Vector2(52.0, 52.0)), now)
		sampler.sample(_points(Vector2(980.0, 52.0)), now + 0.02)
	sampler.flush(mesh)
	var stats: Dictionary = sampler.profile_snapshot() # 实测活动样点和便于性能报告的预算上限。
	if stats.active_samples > stats.sample_limit or stats.active_branches > stats.branch_limit \
			or stats.triangles > stats.triangle_limit or stats.strokes > 18:
		return _fail("高速和连续施法突破了几何容量")
	sampler.clear()
	sampler.begin(_points(Vector2(52.0, -500.0)), 0.0)
	sampler.sample(_points(Vector2(52.0, -500.0)), 0.0)
	sampler.sample(_points(Vector2(352.0, -500.0)), 0.3)
	sampler.flush(mesh)
	if sampler.profile_snapshot().triangles != 0:
		return _fail("完全离开棋盘边界的路径仍然提交图元")
	return true

## [param origin] 为第一束的位置，其余束在垂直方向平移到独立的行。
func _points(origin: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array() # 复用技能的六束接触点数据格式。
	for index: int in range(6): # 分隔足够远以便区分支裂纹与另一道主纹。
		points.append(origin + Vector2(0.0, 82.0 * index))
	return points

## 将 [param reason] 写入错误日志并以失败状态退出。
func _fail(reason: String) -> bool:
	printerr("FAIL test_savior_fissure_geometry: " + reason)
	quit(1)
	return false
