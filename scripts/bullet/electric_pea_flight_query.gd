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
## 战场节点独占的原始候选缓存；仅复用同一检测器、同一物理帧的重叠身份。
const RAW_TARGET_CACHE_META: StringName = &"_electric_pea_raw_target_cache"
## 粗筛包围盒的世界像素余量；接触边缘仍交给原精确碰撞决定。
const CONTACT_BOUNDS_EPSILON: float = 0.001
## 连续电球回调共用的查询数据，随战场释放。
const COHORT_META: StringName = &"_electric_pea_flight_cohort"
## 未知同步回调进行时暂停跨弹体共享；深度按战场独立恢复。
const HIT_DEPTH_META: StringName = &"_electric_pea_hit_depth"
## 不能安全粗筛的标记；有效包围盒由形状变换产生，宽度不会为负。
const UNKNOWN_BOUNDS := Rect2(0.0, 0.0, -1.0, -1.0)
## 空间粗筛的桶宽，单位为世界像素。
const BUCKET_SIZE: float = 80.0
## 超大形状、长扫掠及非常规坐标直接走顺序粗筛，避免创建大量格桶。
const BUCKET_SPAN_LIMIT: int = 8
## 紧凑世界范围最多开这些复用桶，防止稀疏战场按空白区域分配内存。
const DENSE_BUCKET_LIMIT: int = 256
## 单枚电球独占的原版方形碰撞框。
var _probe := RectangleShape2D.new()
## 当前扫掠的候选下标，结算前同步消费，下次粗筛时复用。
var _nearby: Array[int] = []
## 是否已为某段轨迹计算纯数值扫掠包围盒；首次查询必须建立缓存。
var _has_sweep: bool = false
## 已缓存轨迹的精确世界起点，不使用近似比较合并相邻物理段。
var _sweep_start: Vector2 = Vector2.ZERO
## 已缓存轨迹的精确世界终点，反向、竖向及坡面分段分别失效。
var _sweep_finish: Vector2 = Vector2.ZERO
## 建立包围盒时的实际探针尺寸，尺寸变化后立即重新计算。
var _sweep_size: Vector2 = Vector2.ZERO
## 同一轨迹查询所有目标时只读复用的世界扫掠包围盒，不缓存任何目标几何。
var _sweep_bounds := Rect2()
## 当前缓存是否为有限包围盒；非有限轨迹仍走原精确查询路径。
var _sweep_bounded: bool = false
## 固定姿态的探针起点，在同段的精确查询间复用。
var _sweep_origin := Transform2D.IDENTITY
## 探针的完整世界位移，二分查询只缩放这段位移。
var _sweep_motion := Vector2.ZERO


## 只在同优先级的原生相邻电球之间共享几何；每次外部结算及树序修改立即清空。
class FlightCohort:
	## 关联的弹体容器实例，用于拒绝容器被重建的情况。
	var container_id: int
	## 最近一次调用所属的物理步。
	var frame: int = -1
	## 最近一枚球的处理优先级。
	var priority: int
	## 当前已经登记过查询的电球ID；供同一回调共享地块世界几何。
	var source_id: int
	## 几何失效的次数，同一批次内用于派生缓存核对采样时点。
	var geometry_generation: int = 0
	## 查询时的下一位直接兄弟实例，要求当前回调仍属于它。
	var next_id: int
	## 下一位直接兄弟当时的下标。
	var next_index: int
	## 候选身份的有序数组，共享原检测器的物理帧快照。
	var targets: Array[Character000Base] = []
	## 是否已对当前候选读取世界包围盒。
	var sampled: bool = false
	## 同一批次有第二次局部扫掠才构建桶，避免只用一次就被伤害回调使其失效。
	var _queried_locally: bool = false
	## 当前包围盒是否已登记到粗筛桶。
	var _indexed: bool = false
	## 按原检测顺序存放世界受击包围盒。
	var _bounds: Array[Rect2] = []
	## 是否能用一个有限范围排除整批候选；未知形状始终禁用此排除。
	var _bounded: bool = false
	## 所有可界定候选的最小世界端点；分别保存两端，避免重构矩形时舍入收窄。
	var _minimum := Vector2.ZERO
	## 所有可界定候选的最大世界端点，包含贴边接触。
	var _maximum := Vector2.ZERO
	## 有限单形状候选对应的真实形状；其他候选留给原遍历。
	var _shapes: Array[Shape2D] = []
	## 与受击边界同时采样的世界形状姿态。
	var _poses: Array[Transform2D] = []
	## 真实形状拥有者的编号，精确碰撞前仍读取当前禁用状态。
	var _owner_ids := PackedInt32Array()
	## 稀疏世界范围的空间桶；跨桶目标可重复登记。
	var _buckets: Dictionary[Vector2i, Array] = {}
	## 紧凑世界桶范围，空矩形表示使用稀疏桶。
	var _dense_cells := Rect2i()
	## 以相对桶坐标索引的目标列表，跨几何采样复用列表容器。
	var _dense_buckets: Array[Array] = []
	## 非有限、大型或多形状角色的下标，用于保持保守性。
	var _overflow: Array[int] = []

	## 结算或树序改变后，旧几何数据在下一查询前必须刷新。
	func invalidate() -> void:
		geometry_generation += 1
		sampled = false

	## 对 [param bounds] 求包含其两端的世界桶范围；过长或异常的范围返回空矩形。
	static func bucket_range(bounds: Rect2) -> Rect2i:
		if bounds.size.x < 0.0 or not bounds.end.is_finite():
			return Rect2i()
		var minimum: Vector2 = (bounds.position / BUCKET_SIZE).floor() # 左上角桶坐标。
		var maximum: Vector2 = (bounds.end / BUCKET_SIZE).floor() # 包含接触边界的右下角桶坐标。
		var extent: Vector2 = maximum - minimum + Vector2.ONE # 每轴实际遍历的桶数。
		if maxf(absf(minimum.x), absf(minimum.y)) > 1000000000.0 \
				or extent.x > BUCKET_SPAN_LIMIT or extent.y > BUCKET_SPAN_LIMIT:
			return Rect2i()
		return Rect2i(Vector2i(minimum), Vector2i(extent))

	## 仅在发射批次首次需要几何时同步读取全部目标，不冻结当前命中资格。
	func _sample() -> void:
		var count: int = targets.size() # 同一编号关联身份、范围和精确碰撞数据。
		_bounds.resize(count)
		_shapes.resize(count)
		_poses.resize(count)
		_owner_ids.resize(count)
		_queried_locally = false
		_indexed = false
		_bounded = count > 0
		_minimum = Vector2(INF, INF)
		_maximum = Vector2(-INF, -INF)
		for index: int in range(count): # 目标顺序与原检测器完全一致。
			var world: Rect2 = _sample_target(index) # 用同一真实形状建立单目标与整批范围。
			_bounds[index] = world
			if _bounded:
				var end: Vector2 = world.end # 与精确边界测试共用目标的最大端点。
				if world.size.x < 0.0 or not end.is_finite():
					_bounded = false
				else:
					_minimum = _minimum.min(world.position)
					_maximum = _maximum.max(end)
		sampled = true

	## 记录 [param index] 的单一真实形状；未知边界返回未知标记并保留原遍历路径。
	func _sample_target(index: int) -> Rect2:
		_shapes[index] = null
		var reference: Variant = targets[index] # 已被早先命中移除的节点不可解引用。
		if not is_instance_valid(reference) or not is_instance_valid(reference.hurt_box_component):
			return UNKNOWN_BOUNDS
		var area: Area2D = reference.hurt_box_component.hurt_box_real # 以原受击区域为准。
		if not is_instance_valid(area):
			return UNKNOWN_BOUNDS
		var owners: PackedInt32Array = area.get_shape_owners() # 每次采样重查动态拥有者。
		if owners.size() != 1 or area.shape_owner_get_shape_count(owners[0]) != 1:
			return UNKNOWN_BOUNDS
		var owner_id: int = owners[0] # 已确认只有一个拥有者与一个真实形状。
		var shape: Shape2D = area.shape_owner_get_shape(owner_id, 0) # 同一资源用于包围盒和精确扫掠。
		if shape == null or shape is WorldBoundaryShape2D:
			return UNKNOWN_BOUNDS
		var pose: Transform2D = area.global_transform * area.shape_owner_get_transform(owner_id) # 包含父级、翻转与受击偏移。
		var world: Rect2 = pose * shape.get_rect() # 刷新形状参数和姿态后取得世界范围。
		if not world.position.is_finite() or not world.size.is_finite():
			return UNKNOWN_BOUNDS
		_shapes[index] = shape
		_poses[index] = pose
		_owner_ids[index] = owner_id
		return world

	## 对有后续查询的同一批次构建空间桶，保留无法登记的特殊几何。
	func _index_bounds() -> void:
		_buckets.clear()
		_overflow.clear()
		_reset_dense_buckets()
		var stride: int = _dense_cells.size.x # 零表示当前范围走稀疏桶。
		var base: Vector2i = _dense_cells.position # 紧凑表的左上桶坐标。
		for index: int in range(_bounds.size()): # 直接使用本批次的最新世界范围。
			var world: Rect2 = _bounds[index] # 有限单形状按实际覆盖的桶登记。
			var cells: Rect2i = bucket_range(world) # 有限单形状按实际覆盖的桶登记。
			if not cells.has_area():
				_overflow.append(index)
				continue
			for y: int in range(cells.position.y, cells.end.y): # 逐行登记世界受击范围。
				var row: int = (y - base.y) * stride - base.x # 紧凑表上该行的横坐标偏移。
				for x: int in range(cells.position.x, cells.end.x): # 横跨多个桶的目标都会被找到。
					if stride > 0:
						_dense_buckets[row + x].append(index)
					else:
						var key := Vector2i(x, y) # 稀疏桶按实际出现的世界坐标登记。
						var bucket: Variant = _buckets.get(key) # 已登记的列表直接复用。
						if bucket == null:
							bucket = []
							_buckets[key] = bucket
						bucket.append(index)
		_indexed = true

	## 为紧凑的当前候选范围清空将使用的桶；稀疏或未知范围沿用字典和溢出列表。
	func _reset_dense_buckets() -> void:
		_dense_cells = Rect2i()
		if not _bounded:
			return
		var first: Vector2 = (_minimum / BUCKET_SIZE).floor() # 与单目标桶范围保持相同取整。
		var last: Vector2 = (_maximum / BUCKET_SIZE).floor() # 包含所有有限目标的最后一个桶。
		var extent: Vector2 = last - first + Vector2.ONE # 转换为整数桶之前先限制范围。
		if maxf(absf(first.x), absf(first.y)) > 1000000000.0 \
				or maxf(absf(last.x), absf(last.y)) > 1000000000.0 \
				or extent.x * extent.y > DENSE_BUCKET_LIMIT:
			return
		_dense_cells = Rect2i(Vector2i(first), Vector2i(extent))
		var count: int = _dense_cells.size.x * _dense_cells.size.y # 仅清空此次将访问的列表。
		var previous: int = _dense_buckets.size() # 保留旧容量供范围轻微变动时复用。
		if count > previous:
			_dense_buckets.resize(count)
			for slot: int in range(previous, count): # 每个新桶分配独立的列表。
				_dense_buckets[slot] = []
		for slot: int in range(mini(previous, count)): # 不读取未使用的槽位或此前的索引。
			_dense_buckets[slot].clear()

	## 将可能接触 [param bounds] 的有序角色下标写入 [param nearby]；未知几何始终保留。
	func collect_overlaps(bounds: Rect2, nearby: Array[int]) -> void:
		if not sampled:
			_sample()
		if _bounds.is_empty():
			return
		if _bounded:
			var end: Vector2 = bounds.end # 严格分离才排除，贴着范围边界仍继续检查。
			if end.x < _minimum.x or end.y < _minimum.y or bounds.position.x > _maximum.x or bounds.position.y > _maximum.y:
				return
		var cells: Rect2i = bucket_range(bounds) # 矩形较大时顺序访问现有几何。
		if not cells.has_area() or not _queried_locally:
			_queried_locally = _queried_locally or cells.has_area()
			for index: int in range(_bounds.size()): # 不因大扫掠漏掉任何已登记目标。
				var world: Rect2 = _bounds[index] # 只用同步读取的边界，未知形状照常保留。
				if world.size.x < 0.0 or bounds.intersects(world, true):
					nearby.append(index)
			return
		if not _indexed:
			_index_bounds()
		var stride: int = _dense_cells.size.x # 零表示当前范围走稀疏桶。
		var base: Vector2i = _dense_cells.position # 紧凑表的左上桶坐标。
		if stride > 0:
			cells = cells.intersection(_dense_cells)
		if cells.size == Vector2i.ONE and _overflow.is_empty():
			var offset: Vector2i = cells.position - base # 紧凑表内相对位置。
			var bucket: Variant = _dense_buckets[offset.y * stride + offset.x] if stride > 0 else _buckets.get(cells.position) # 单桶已按原序登记。
			if bucket != null:
				for index: int in bucket: # 单个桶内的角色各出现一次。
					if bounds.intersects(_bounds[index], true):
						nearby.append(index)
			return
		nearby.append_array(_overflow)
		for y: int in range(cells.position.y, cells.end.y): # 只访问扫掠跨过的桶。
			var row: int = (y - base.y) * stride - base.x # 紧凑表上该行的横坐标偏移。
			for x: int in range(cells.position.x, cells.end.x): # 合并各相邻桶的角色下标。
				var bucket: Variant = _dense_buckets[row + x] if stride > 0 else _buckets.get(Vector2i(x, y)) # 合并同一世界坐标的列表。
				if bucket != null:
					nearby.append_array(bucket)
		nearby.sort()
		var previous: int = -1 # 相邻重复仅由同一目标跨多个桶引起。
		var count: int = 0 # 原地压缩有效候选，写入位置不会超过正在读取的位置。
		for slot: int in range(nearby.size()): # 恢复原扫描顺序，供精确接触排序使用。
			var index: int = nearby[slot] # 当前合并后的候选角色下标。
			if index != previous and ElectricPeaFlightQuery.bounds_may_intersect(_bounds[index], bounds):
				nearby[count] = index
				count += 1
			previous = index
		nearby.resize(count)


## [param size_multiplier] 缩放独立碰撞框；小电球沿用同一真实扫掠。
func _init(size_multiplier: float = 1.0) -> void:
	_probe.size = Vector2.ONE * HALF_SIZE * 2.0 * size_multiplier


## 从 [param game] 的原始全局重叠区域取敌人，避开全局检测器默认不含跳跃状态的预筛选。
## 同物理帧只缓存原始身份；每次调用仍由 [method can_hit] 生成独立资格快照，命中回调不会扩充本轮候选。
static func all_targets(game: MainGameManager) -> Array[Character000Base]:
	var result: Array[Character000Base] = [] # 当前查询独占候选列表。
	for reference: Variant in raw_targets(game): # 同帧前一枚电球的回调可能已经释放原始候选。
		if is_instance_valid(reference) and can_hit(reference):
			result.append(reference)
	return result


## 返回 [param game] 本物理步只读共享的原始身份。资格与几何由使用者即时核对。
static func raw_targets(game: MainGameManager) -> Array[Character000Base]:
	if not is_instance_valid(game) or not is_instance_valid(game.detect_component_global):
		return []
	var detect: DetectComponent = game.detect_component_global # 缓存按当前检测器身份隔离，替换后立即重建。
	if Engine.is_in_physics_frame():
		var frame: int = Engine.get_physics_frames() # 重叠列表随物理步刷新，不跨物理帧复用。
		var detector_id: int = detect.get_instance_id() # 同场景内替换检测器时使旧缓存失效。
		var cache: Dictionary = game.get_meta(RAW_TARGET_CACHE_META, {}) # 缓存随原战场节点一起释放。
		if int(cache.get("frame", -1)) == frame and int(cache.get("detector_id", 0)) == detector_id:
			return cache["targets"]
		var candidates: Array[Character000Base] = _raw_targets(detect) # 刷新当前检测器的原始身份。
		game.set_meta(RAW_TARGET_CACHE_META, {"frame": frame, "detector_id": detector_id, "targets": candidates})
		return candidates
	# 非物理调用不假定重叠刷新阶段，直接读取当前列表。
	return _raw_targets(detect)


## 从 [param detect] 读取去重的原始角色身份，不冻结存活、魅惑或受击状态；返回数组仅供内部只读共享。
static func _raw_targets(detect: DetectComponent) -> Array[Character000Base]:
	var result: Array[Character000Base] = [] # 当前物理步检测器提供的原始角色集合。
	var seen: Dictionary[int, bool] = {} # 同一僵王或角色的多个区域只登记一次。
	for ray: Area2D in detect.all_ray_area: # 使用全局原始阵营层，不改共享状态掩码。
		if not is_instance_valid(ray):
			continue
		for area: Area2D in ray.get_overlapping_areas(): # 全局区域已经覆盖当前战场。
			if not is_instance_valid(area) or not is_instance_valid(area.owner):
				continue
			var target: Character000Base = area.owner as Character000Base # 梯子等非角色对象不进入电击候选。
			if not is_instance_valid(target) or seen.has(target.get_instance_id()):
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


## 为 [param game] 中的单段电球 [param source] 登记 [param candidates] 的粗筛作用域，无法共享时返回空。
## Godot 同组同优先级的物理回调按树序执行；仅直接相邻的已确认电球可以跨回调重用几何。
func begin_projectile_candidates(game: MainGameManager, source: Node2D,
		candidates: Array[Character000Base]) -> FlightCohort:
	if not Engine.is_in_physics_frame() or not is_instance_valid(game) or game.has_meta(HIT_DEPTH_META):
		return null
	var container: Node = source.get_parent() # 根必须在同一个正式战场的弹体容器中。
	if not is_instance_valid(container) or container != game.bullets \
			or source.process_thread_group != Node.PROCESS_THREAD_GROUP_INHERIT:
		return null
	var cohort: FlightCohort # 本战场最近一次电球回调记录。
	if game.has_meta(COHORT_META):
		cohort = game.get_meta(COHORT_META)
	if cohort == null or cohort.container_id != container.get_instance_id():
		cohort = FlightCohort.new()
		cohort.container_id = container.get_instance_id()
		container.child_order_changed.connect(cohort.invalidate)
		game.set_meta(COHORT_META, cohort)
	var frame: int = Engine.get_physics_frames() # 新物理步允许敌人及棋盘完成新位移。
	var source_index: int = source.get_index() # 当前直接兄弟下标，容器变化后必须重新采样。
	if cohort.frame != frame or cohort.priority != source.process_physics_priority \
			or cohort.next_id != source.get_instance_id() or cohort.next_index != source_index \
			or not is_same(cohort.targets, candidates):
		cohort.invalidate()
		cohort.targets = candidates
	cohort.frame = frame
	cohort.priority = source.process_physics_priority
	cohort.next_index = source_index + 1
	cohort.next_id = 0
	cohort.source_id = source.get_instance_id()
	if cohort.next_index < container.get_child_count():
		cohort.next_id = container.get_child(cohort.next_index).get_instance_id()
	return cohort


## 返回 [param source] 在 [param game] 当前相邻电球批次；其他调用路径返回空。
static func current_projectile_cohort(game: MainGameManager, source: Node2D) -> FlightCohort:
	if not Engine.is_in_physics_frame() or not is_instance_valid(game) \
			or game.has_meta(HIT_DEPTH_META) or not game.has_meta(COHORT_META):
		return null
	var cohort: FlightCohort = game.get_meta(COHORT_META) # 只有同一回调已经登记时才能共用时点。
	if cohort.frame != Engine.get_physics_frames() or cohort.source_id != source.get_instance_id():
		return null
	return cohort


## 在 [param game] 进入未知同步回调前失效旧几何；期间所有重入查询都即时读取。
static func begin_sync_hit(game: MainGameManager) -> void:
	var depth: int = game.get_meta(HIT_DEPTH_META, 0) # 外层已经失效旧几何，嵌套只记录深度。
	game.set_meta(HIT_DEPTH_META, depth + 1)
	if depth == 0 and game.has_meta(COHORT_META):
		var cohort: FlightCohort = game.get_meta(COHORT_META) # 战场本地缓存由已有弹体查询建立。
		cohort.invalidate()


## 结束 [param game] 的同步回调；最外层返回后才允许下一批弹体采样共享几何。
static func end_sync_hit(game: MainGameManager) -> void:
	if not is_instance_valid(game):
		return
	var depth: int = game.get_meta(HIT_DEPTH_META, 0) # 对应同一入栈时点的战场，兼容伤害结束整个关卡。
	if depth > 1:
		game.set_meta(HIT_DEPTH_META, depth - 1)
	else:
		game.remove_meta(HIT_DEPTH_META)


## 收集 [param start] 至 [param finish] 的扫掠候选在 [param candidates] 中的原始下标。
## [param cohort] 为本段已确认的共享范围，其他路径由精确查询即时逐形状粗筛。
## 返回值在下次粗筛时复用，调用方必须在同步结算前完成遍历。
func overlapping_target_indices(candidates: Array[Character000Base], start: Vector2,
		finish: Vector2, cohort: FlightCohort) -> Array[int]:
	_prepare_sweep(start, finish)
	_nearby.clear()
	if cohort != null and _sweep_bounded:
		cohort.collect_overlaps(_sweep_bounds, _nearby)
	else:
		_nearby.resize(candidates.size())
		for index: int in range(candidates.size()): # 非有限扫掠或独立坡段按原顺序检查当前形状。
			_nearby[index] = index
	return _nearby


## 确认 [param hurt] 描述的受击范围能否碰到 [param bounds]，未知受击范围始终保留。
static func bounds_may_intersect(hurt: Rect2, bounds: Rect2) -> bool:
	return hurt.size.x < 0.0 or bounds.intersects(hurt, true)


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


## 在 [param start] 至 [param finish] 上精确查询 [param index] 对应的 [param area]，无接触返回 INF。
## 同步粗筛后可读 [param cohort] 的形状和姿态；未知、多形状及非有限扫掠沿用原查询。
func candidate_contact_fraction(index: int, area: Area2D, start: Vector2, finish: Vector2,
		cohort: FlightCohort) -> float:
	if cohort != null and cohort.sampled and _sweep_bounded:
		var shape: Shape2D = cohort._shapes[index] # 已由同一段粗筛确认的单个真实形状。
		if shape != null:
			if not is_instance_valid(area) or area.is_queued_for_deletion() \
					or area.is_shape_owner_disabled(cohort._owner_ids[index]):
				return INF
			return _shape_fraction(shape, cohort._poses[index])
	return contact_fraction(area, start, finish)


## 求 [param area] 在 [param start] 到 [param finish] 上首次接触比例；无接触返回 INF。
func contact_fraction(area: Area2D, start: Vector2, finish: Vector2) -> float:
	if not is_instance_valid(area) or area.is_queued_for_deletion():
		return INF
	var first: float = INF # 同一目标多个受击形状只取最早的真实接触。
	_prepare_sweep(start, finish)
	for owner_id: int in area.get_shape_owners(): # 禁用形状不能触发伤害。
		if area.is_shape_owner_disabled(owner_id):
			continue
		var transform: Transform2D = area.global_transform * area.shape_owner_get_transform(owner_id) # 形状世界坐标。
		for index: int in range(area.shape_owner_get_shape_count(owner_id)): # 支持多形状僵王。
			var shape: Shape2D = area.shape_owner_get_shape(owner_id, index) # 当前实体形状。
			if shape == null:
				continue
			if _sweep_bounded and not shape is WorldBoundaryShape2D:
				var shape_bounds: Rect2 = transform * shape.get_rect() # 即时世界包围盒覆盖旋转、缩放及身体位移。
				if shape_bounds.position.is_finite() and shape_bounds.size.is_finite() \
						and not _sweep_bounds.intersects(shape_bounds, true):
					continue
			first = minf(first, _shape_fraction(shape, transform))
	return first


## 核对 [param start] 与 [param finish] 的扫掠范围，与精确查询共用同一探针尺寸。
func _prepare_sweep(start: Vector2, finish: Vector2) -> void:
	var probe_size: Vector2 = _probe.size # 外部调整探针尺寸时使缓存立即失效。
	if _has_sweep and start == _sweep_start and finish == _sweep_finish and probe_size == _sweep_size:
		return
	_sweep_start = start
	_sweep_finish = finish
	_sweep_size = probe_size
	_sweep_origin = Transform2D(0.0, start)
	_sweep_motion = finish - start
	var half_size: Vector2 = probe_size * 0.5 # 分裂小球使用自身真实尺寸。
	_sweep_bounds = Rect2(start.min(finish) - half_size, _sweep_motion.abs() + probe_size).grow(CONTACT_BOUNDS_EPSILON)
	_sweep_bounded = _sweep_bounds.position.is_finite() and _sweep_bounds.size.is_finite()
	_has_sweep = true


## 对 [param shape] 的 [param transform] 在已准备的物理段内求固定上界接触二分。
func _shape_fraction(shape: Shape2D, transform: Transform2D) -> float:
	if _probe.collide(_sweep_origin, shape, transform):
		return 0.0
	if not _probe.collide_with_motion(_sweep_origin, _sweep_motion, shape, transform, Vector2.ZERO):
		return INF
	var lower: float = 0.0 # 尚未接触的已知前缀。
	var upper: float = 1.0 # 已经接触的已知前缀。
	for _step: int in range(CONTACT_STEPS): # 查询次数固定，不进行逐像素扫描。
		var middle: float = (lower + upper) * 0.5 # 本次前缀长度比例。
		if _probe.collide_with_motion(_sweep_origin, _sweep_motion * middle, shape, transform, Vector2.ZERO):
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
