## 电球专用连续碰撞与范围查询；原版三十像素碰撞框不会被电光贴图放大。
extends RefCounted
class_name ElectricPeaFlightQuery

## 原版 ElectricPeaDefault.CollisionRect 的半宽，单位为世界像素。
const HALF_SIZE: float = 15.0
## 固定次数二分求首次碰撞，防止高速电球跨过较窄目标。
const CONTACT_STEPS: int = 16
## 原版 ground_zombies 与 off_ground_zombies 对应正常、跳跃及空中状态。
const TARGET_STATES: int = Zombie000Base.E_BeAttackStatusZombie.IsNorm \
	| Zombie000Base.E_BeAttackStatusZombie.IsJump | Zombie000Base.E_BeAttackStatusZombie.IsSky
## 单枚电球独占的原版方形碰撞框。
var _probe := RectangleShape2D.new()


## [param size_multiplier] 缩放独立碰撞框；小电球沿用同一真实扫掠。
func _init(size_multiplier: float = 1.0) -> void:
	_probe.size = Vector2.ONE * HALF_SIZE * 2.0 * size_multiplier


## 从 [param game] 的原始全局重叠区域取敌人，避开全局检测器默认不含跳跃状态的预筛选。
## 返回当前仍有效的去重角色；本物种状态资格统一由 [method can_hit] 决定。
static func all_targets(game: MainGameManager) -> Array[Character000Base]:
	var result: Array[Character000Base] = [] # 当前查询独占候选列表。
	var seen: Dictionary[int, bool] = {} # 同一僵王或角色的多个区域只登记一次。
	if not is_instance_valid(game) or not is_instance_valid(game.detect_component_global):
		return result
	for ray: Area2D in game.detect_component_global.all_ray_area: # 使用全局原始阵营层，不改共享状态掩码。
		for area: Area2D in ray.get_overlapping_areas(): # 全局区域已经覆盖当前战场。
			if not is_instance_valid(area) or not is_instance_valid(area.owner):
				continue
			var target: Character000Base = area.owner as Character000Base # 梯子等非角色对象不进入电击候选。
			if not can_hit(target) or seen.has(target.get_instance_id()):
				continue
			seen[target.get_instance_id()] = true
			result.append(target)
	return result


## 返回 [param target] 是否仍为原版电球可攻击的敌方目标，排除水下、地下和魅惑对象。
static func can_hit(target: Character000Base) -> bool:
	if not is_instance_valid(target) or target.is_death or target.is_hypno \
			or target.is_queued_for_deletion() or not target.is_inside_tree() \
			or not is_instance_valid(target.hurt_box_component) or not target.hurt_box_component.is_enabling:
		return false
	if target is Zombie000Base:
		return (target.curr_be_attack_status & TARGET_STATES) != 0
	return (target is ZB000Base or target is EnemyStructureBase) \
		and target.character_init_type == Character000Base.E_CharacterInitType.IsNorm


## 返回 [param target] 的真实受击中心，兼容根节点远离机甲的僵王。
static func target_position(target: Character000Base) -> Vector2:
	var area: Area2D = target.hurt_box_component.hurt_box_real # 电弧落点使用真实受击层。
	var shape: Node2D = area.get_node_or_null(^"CollisionShape2D") as Node2D # 常规角色都有具名形状。
	return shape.global_position if shape != null else area.global_position


## 返回 [param slope] 在 [param world_x] 的屋顶高度，平地或已移除坡面为零。
static func height_at(slope: MainGameSlope, world_x: float) -> float:
	return slope.get_all_slope_y(world_x) if is_instance_valid(slope) else 0.0


## 返回 [param board] 中距离 [param point] 地面投影最近的真实攻击行。
## [param slope] 统一剔除屋顶高差；无有效地块时沿用 [param fallback]，不制造边界外的攻击行。
static func nearest_lane(board: BoardRuntime, point: Vector2, slope: MainGameSlope, fallback: int) -> int:
	var flat_point := Vector2(point.x, point.y - height_at(slope, point.x)) # 弹体当前地面投影的展开坐标。
	var closest: float = INF # 同一展开平面内的最小距离平方。
	var lane: int = fallback # 空板或正在清理时保留最后一个有效行号。
	for cell: PlantCell in board.cells(): # 每次查询使用平台移动后的真实地块位置。
		if not is_instance_valid(cell) or cell.is_queued_for_deletion() or not cell.is_visible_in_tree():
			continue
		var center: Vector2 = cell.get_global_rect().get_center() # 屋顶高度在地块自身横坐标处剔除。
		center.y -= height_at(slope, center.x)
		var distance: float = flat_point.distance_squared_to(center) # 枪口离地偏移已由调用者抵消。
		if distance < closest:
			closest = distance
			lane = cell.row_col.x
	return lane


## 将 [param start] 到 [param finish] 按 [param slope] 折点拆段，[param start_y] 到 [param finish_y] 为这一段的坡面相对高度。
static func path_points(start: Vector2, finish: Vector2, slope: MainGameSlope,
		start_y: float, finish_y: float) -> Array[Vector2]:
	var breaks: Array[float] = [] # 只处理本帧经过的有限屋顶折点。
	var left: float = minf(start.x, finish.x) # 正反向共用的经过区间左端点。
	var right: float = maxf(start.x, finish.x) # 竖直飞行时区间为空，不执行横向插值。
	if is_instance_valid(slope):
		for part: Slope in slope.all_slopes: # 低帧率跨坡时仍沿坡面飞行。
			if not is_instance_valid(part):
				continue
			for boundary: float in [part.slope_global_pos_x_range.x, part.slope_global_pos_x_range.y]: # 坡段两端。
				if boundary > left and boundary < right and not breaks.has(boundary):
					breaks.append(boundary)
	breaks.sort()
	if finish.x < start.x:
		breaks.reverse()
	var points: Array[Vector2] = [start] # 顺序始终沿实际速度方向，包括向左飞行的分裂后代。
	for boundary: float in breaks: # 每个折点高度来自同一坡面接口。
		var fraction: float = inverse_lerp(start.x, finish.x, boundary) # 同步插值斜向弹道的离地高度。
		points.append(Vector2(boundary, lerpf(start_y, finish_y, fraction) + height_at(slope, boundary)))
	points.append(finish)
	return points


## 求 [param area] 在 [param start] 到 [param finish] 上首次接触比例；无接触返回 INF。
func contact_fraction(area: Area2D, start: Vector2, finish: Vector2) -> float:
	if not is_instance_valid(area) or area.is_queued_for_deletion():
		return INF
	var first: float = INF # 同一目标多个受击形状只取最早的真实接触。
	for owner_id: int in area.get_shape_owners(): # 禁用形状不能触发伤害。
		if area.is_shape_owner_disabled(owner_id):
			continue
		var transform: Transform2D = area.global_transform * area.shape_owner_get_transform(owner_id) # 形状世界坐标。
		for index: int in range(area.shape_owner_get_shape_count(owner_id)): # 支持多形状僵王。
			var shape: Shape2D = area.shape_owner_get_shape(owner_id, index) # 当前实体形状。
			first = minf(first, _shape_fraction(shape, transform, start, finish))
	return first


## 对 [param shape] 的 [param transform] 求 [param start] 至 [param finish] 的固定上界接触二分。
func _shape_fraction(shape: Shape2D, transform: Transform2D, start: Vector2, finish: Vector2) -> float:
	var origin := Transform2D(0.0, start) # 碰撞方形不随美术旋转。
	var motion: Vector2 = finish - start # 只查询本物理段的真实位移。
	if shape == null:
		return INF
	if _probe.collide(origin, shape, transform):
		return 0.0
	if not _probe.collide_with_motion(origin, motion, shape, transform, Vector2.ZERO):
		return INF
	var lower: float = 0.0 # 尚未接触的已知前缀。
	var upper: float = 1.0 # 已经接触的已知前缀。
	for _step: int in range(CONTACT_STEPS): # 查询次数固定，不进行逐像素扫描。
		var middle: float = (lower + upper) * 0.5 # 本次前缀长度比例。
		if _probe.collide_with_motion(origin, motion * middle, shape, transform, Vector2.ZERO):
			upper = middle
		else:
			lower = middle
	return upper


## [param plant] 使用 [param detect] 查询同行前方可见敌人；僵王由真实重叠定位。
static func has_forward_target(plant: Plant000Base, detect: DetectComponent) -> bool:
	var screen: Rect2 = plant.get_canvas_transform().affine_inverse() * plant.get_viewport_rect() # 镜头移动时仍按实际可见战场索敌。
	for target: Character000Base in detect.get_all_enemy_can_be_attacked(): # 组件已完成同行与状态筛选。
		if not ElectricPeaFlightQuery.can_hit(target):
			continue
		var target_x: float = target.hurt_box_component.global_position.x # 机甲根节点不代表可命中位置。
		if target_x >= plant.global_position.x and target_x <= screen.end.x:
			return true
	return false
