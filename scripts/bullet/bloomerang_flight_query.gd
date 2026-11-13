## 回旋镖的连续几何查询；广查不漏密集受击框，窄查按首次真实接触排序。
extends RefCounted
class_name BloomerangFlightQuery

## 沿用弹体场景的十像素方形受击范围，不随美术旋转改变命中宽度。
const HALF_SIZE: float = 5.0
## 固定次数的接触比例二分，不使用可能无法结束的逼近循环。
const CONTACT_STEPS: int = 16

## 连续扫掠的原始方形，供形状间运动检测使用。
var _probe := RectangleShape2D.new()
## 线段两端方形的凸包，用于物理空间广查候选。
var _sweep := ConvexPolygonShape2D.new()
## 借用通用完整查询的几何配置，不触发爆炸伤害或表现。
var _profile := CombatExplosionProfile.new()
## 接镖枪口的半像素接触点，返回实际扫掠接触而不是仅比较横坐标。
var _catch_point := CircleShape2D.new()

## 初始化每枚弹独享的几何资源，避免并发查询互相修改共享形状。
func _init() -> void:
	_probe.size = Vector2.ONE * HALF_SIZE * 2.0
	_profile.shape = _sweep
	_catch_point.radius = 0.5

## 将 [param node] 当前视口经画布逆变换映射到世界边界，每帧读取以跟随镜头变化。
static func screen_rect(node: Node2D) -> Rect2:
	return node.get_canvas_transform().affine_inverse() * node.get_viewport_rect()

## 返回 [param slope] 在 [param world_x] 的公共高度；平地或已移除坡面返回零。
static func height_at(slope: MainGameSlope, world_x: float) -> float:
	return slope.get_all_slope_y(world_x) if is_instance_valid(slope) else 0.0

## 将 [param start] 至 [param finish] 按 [param slope] 折点拆成真实直线段。
## [param level_y] 是扣除坡面高度后的固定飞行高度。
static func path_points(start: Vector2, finish: Vector2,
		slope: MainGameSlope, level_y: float) -> Array[Vector2]:
	var breaks: Array[float] = [] # 只保存本次有限路径内部的斜面起止点。
	if is_instance_valid(slope):
		for part: Slope in slope.all_slopes: # 防止低帧率一步越过屋顶坡折时抄近路。
			if not is_instance_valid(part):
				continue
			for boundary: float in [part.slope_global_pos_x_range.x, part.slope_global_pos_x_range.y]: # 当前斜面的两个折点。
				if boundary > minf(start.x, finish.x) and boundary < maxf(start.x, finish.x) \
						and not breaks.has(boundary):
					breaks.append(boundary)
	breaks.sort()
	if finish.x < start.x:
		breaks.reverse()
	var points: Array[Vector2] = [start] # 顺序就是实际飞行顺序。
	for boundary: float in breaks: # 每个折点使用相同高度权威，避免扫描和显示的弹道分叉。
		points.append(Vector2(boundary, level_y + height_at(slope, boundary)))
	points.append(finish)
	return points

## 广查 [param node] 世界中的 [param start] 至 [param finish]，只取 [param mask] 指定受击层。
func areas(node: Node2D, start: Vector2, finish: Vector2, mask: int) -> Array[Area2D]:
	var motion: Vector2 = finish - start # 凸包以起点为局部原点，保留大世界坐标精度。
	var corners := PackedVector2Array() # 两端原始方形的八个顶点，生成精确的扫掠体积。
	for corner: Vector2 in [Vector2(-HALF_SIZE, -HALF_SIZE), Vector2(HALF_SIZE, -HALF_SIZE),
			Vector2(HALF_SIZE, HALF_SIZE), Vector2(-HALF_SIZE, HALF_SIZE)]:
		corners.append(corner)
		corners.append(corner + motion)
	_sweep.set_point_cloud(corners)
	_profile.collision_mask = mask
	return CombatExplosion.query_areas(node.get_world_2d().direct_space_state, _profile, start)

## 返回 [param node] 从 [param start] 至 [param finish] 在 [param mask] 中的有序接触。
## 每项含 area 与 fraction；使用形状边缘而非角色中心排序，僵王大受击框也遵守实际先后。
func contacts(node: Node2D, start: Vector2, finish: Vector2, mask: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = [] # 该线段的实际接触候选，伤害资格由弹体逐项复核。
	var seen: Dictionary[int, bool] = {} # 同一 Area 的多个形状只窄查一次。
	for area: Area2D in areas(node, start, finish, mask): # 广查只给候选，不提前消耗穿透次数。
		if not is_instance_valid(area) or area.is_queued_for_deletion() or seen.has(area.get_instance_id()):
			continue
		seen[area.get_instance_id()] = true
		var fraction: float = area_fraction(area, start, finish) # 首次进入真实形状的路径比例。
		if is_finite(fraction):
			result.append({"area": area, "fraction": fraction})
	# a、b 是两个已经窄查的接触；完全同时的形状以实例身份固定顺序。
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.area.get_instance_id() < b.area.get_instance_id() if a.fraction == b.fraction \
			else a.fraction < b.fraction)
	return result

## 返回 [param area] 在 [param start] 至 [param finish] 上的最早接触比例，无接触为 INF。
func area_fraction(area: Area2D, start: Vector2, finish: Vector2) -> float:
	if not is_instance_valid(area) or area.is_queued_for_deletion():
		return INF
	var first: float = INF # 多形状 Area 只取最早的真实接触。
	for owner_id: int in area.get_shape_owners(): # 读取当前形状变换，支持身体位移与镜像。
		if area.is_shape_owner_disabled(owner_id):
			continue
		var transform: Transform2D = area.global_transform * area.shape_owner_get_transform(owner_id) # 形状世界变换。
		for index: int in range(area.shape_owner_get_shape_count(owner_id)): # 同一区域可能有多个实体形状。
			first = minf(first, _shape_fraction(area.shape_owner_get_shape(owner_id, index),
				transform, start, finish))
	return first

## 用 [param point] 的当前世界坐标检查 [param start] 至 [param finish] 是否真实接触接镖点。
func marker_fraction(point: Vector2, start: Vector2, finish: Vector2) -> float:
	return _shape_fraction(_catch_point, Transform2D(0.0, point), start, finish)

## 求 [param shape] 在 [param transform] 处与 [param start] 至 [param finish] 的首次接触。
## 固定上界二分只查询前缀扫掠，先检测出生重叠，避免把宽僵王的中心当命中点。
func _shape_fraction(shape: Shape2D, transform: Transform2D, start: Vector2, finish: Vector2) -> float:
	if shape == null:
		return INF
	var origin := Transform2D(0.0, start) # 方形弹体不跟随美术旋转。
	var motion: Vector2 = finish - start # 当前真实直线路径，不使用母镖尚未走完的路径。
	if _probe.collide(origin, shape, transform):
		return 0.0
	if not _probe.collide_with_motion(origin, motion, shape, transform, Vector2.ZERO):
		return INF
	var lower: float = 0.0 # 已确认尚未接触的前缀。
	var upper: float = 1.0 # 已确认包含首次接触的前缀。
	for _step: int in range(CONTACT_STEPS): # 次数固定，最差大步长下也不会挂起物理帧。
		var middle: float = (lower + upper) * 0.5 # 当前二分前缀比例。
		if _probe.collide_with_motion(origin, motion * middle, shape, transform, Vector2.ZERO):
			upper = middle
		else:
			lower = middle
	return upper
