## 杨桃瞄准的局部目标索引。同一物理步共享一次位置采样，单发只探查必要的空间格。
extends RefCounted

## 地面目标分桶宽度，单位世界像素，与普通格宽接近。
const BUCKET_SIZE: float = 96.0
## 稀疏超大地图直接遍历已占用的桶，不跨空白层逐级扩展。
const MAX_SHELL: int = 28
## 同一物理步重用的各真实受击节点。
var _points: Array[Node2D] = []
## 和受击节点同序的当前世界坐标快照。
var _positions := PackedVector2Array()
## 和受击点同序的候选角色。
var _targets: Array[Character000Base] = []
## 桶的容器在相邻物理步之间复用。
var _buckets: Dictionary[Vector2i, Array] = {}
## 本步真正存在目标的桶索引。
var _occupied: Array[Vector2i] = []
## 当前有效桶的左上与右下，不包含历史空桶。
var _first := Vector2i.ZERO
## 当前有效桶的右下坐标，含此边界。
var _last := Vector2i.ZERO
## 已采样的物理帧，同帧所有星弹共用。
var _frame: int = -1
## 构建次数供压力测试核对跨弹共享。
var builds: int = 0

## [param game] 当前物理时间第一次发生锁定才采样，其他弹体不查询角色树。
func refresh(game: MainGameManager) -> void:
	var frame: int = Engine.get_physics_frames() # 官方场景物理步号。
	if _frame == frame:
		return
	_frame = frame
	builds += 1
	for key: Vector2i in _occupied: # 活跃桶复用容器，空桶不重新扫描。
		_buckets[key].clear()
	_occupied.clear()
	_points.clear()
	_positions.clear()
	_targets.clear()
	for target: Zombie000Base in game.zombie_manager.all_zombies_1d: # 真实敌对注册表，没有图鉴实例。
		if ground_target(target):
			_add(target)
	for boss: ZB000Base in game.zombie_manager.get_living_bosses(): # 有正式接地行的僵王，也接受其有效受击点。
		if ground_target(boss):
			_add(boss)
	if _buckets.size() > maxi(128, _occupied.size() * 4):
		var live: Dictionary[Vector2i, Array] = {} # 释放远处移动地形留下的历史桶。
		for key: Vector2i in _occupied: # 每项直接转移已获容器。
			live[key] = _buckets[key]
		_buckets = live

## 将有正式受击点的 [param target] 加入当前只读位置快照。
func _add(target: Character000Base) -> void:
	var point: Node2D = aim_point(target) # 比实体脚点更贴合真实碰撞。
	if point == null or not point.global_position.is_finite():
		return
	var position: Vector2 = point.global_position # 同一物理步内固定的几何索引。
	var key: Vector2i = _bucket(position) # 世界坐标允许负值。
	if not _buckets.has(key):
		_buckets[key] = []
	var entries: Array = _buckets[key] # 只复用空间存储，角色引用来自当前战斗。
	if entries.is_empty():
		if _occupied.is_empty():
			_first = key
			_last = key
		else:
			_first = _first.min(key)
			_last = _last.max(key)
		_occupied.append(key)
	entries.append(_targets.size())
	_targets.append(target)
	_points.append(point)
	_positions.append(position)

## [param origin] 是星弹当前位置，[param excluded] 为该弹已经命中的敌人。
## 返回实际最近的目标下标。边界下界只剪去不可能获胜的空间桶，允许回头和跨行。
func nearest(origin: Vector2, excluded: Dictionary[int, bool]) -> int:
	if _occupied.is_empty() or not origin.is_finite():
		return -1
	var center: Vector2i = _bucket(origin).clamp(_first, _last) # 盘外查询从最近的索引边开始。
	var extent: Vector2i = (center - _first).max(_last - center) # 覆盖所有有效桶所需壳层。
	var limit: int = maxi(extent.x, extent.y) # 极端稀疏范围走占用列表。
	var best: int = -1 # 对应当前最近目标的下标。
	if limit > MAX_SHELL:
		for key: Vector2i in _occupied: # 跳过超大地图的空白空间。
			best = _scan(key, origin, excluded, best)
		return best
	for layer: int in range(limit + 1): # 从近到远访问每个空间桶一次。
		var raw_min: Vector2i = center - Vector2i(layer, layer) # 当前壳层左上角。
		var raw_max: Vector2i = center + Vector2i(layer, layer) # 当前壳层右下角。
		var low: Vector2i = raw_min.max(_first) # 有效区域内的左上角。
		var high: Vector2i = raw_max.min(_last) # 有效区域内的右下角。
		for y: int in range(low.y, high.y + 1): # 上下边横扫，中间只查左右边。
			if y == raw_min.y or y == raw_max.y:
				for x: int in range(low.x, high.x + 1): # 本壳唯一的整行。
					best = _scan(Vector2i(x, y), origin, excluded, best)
			else:
				if raw_min.x >= _first.x:
					best = _scan(Vector2i(raw_min.x, y), origin, excluded, best)
				if raw_max.x <= _last.x and raw_max.x != raw_min.x:
					best = _scan(Vector2i(raw_max.x, y), origin, excluded, best)
		if best >= 0:
			var outside: float = _outer_gap(origin, low, high) # 未查询区的最小可能距离。
			if origin.distance_squared_to(_positions[best]) < outside * outside:
				return best
	return best

## 对 [param key] 内的目标比较与 [param origin] 的精确距离，[param excluded] 与 [param best] 延续之前结果。
func _scan(key: Vector2i, origin: Vector2, excluded: Dictionary[int, bool], best: int) -> int:
	var entries: Variant = _buckets.get(key) # 多数查询只会碰到很少的已占用桶。
	if entries == null or entries.is_empty():
		return best
	var chosen: int = best # 当前赢家。
	var distance: float = INF if best < 0 else origin.distance_squared_to(_positions[best]) # 当前最短距离平方。
	var identity: int = 0 if best < 0 else _targets[best].get_instance_id() # 同距离按稳定身份。
	for index: int in entries: # 优先比较快照数字，再访问真实实体。
		var squared: float = origin.distance_squared_to(_positions[index]) # 不计算平方根。
		if squared > distance:
			continue
		var candidate: Variant = _targets[index] # 同帧其他命中可能已将它移除。
		if not is_instance_valid(candidate) or not ground_target(candidate):
			continue
		var id: int = candidate.get_instance_id() # 被本发击中的角色不能重新锁定。
		if not excluded.has(id) and (squared < distance or id < identity):
			chosen = index
			distance = squared
			identity = id
	return chosen

## 从 [param origin] 到 [param low]、[param high] 已查区域外最近有效桶的欧氏距离下界。
func _outer_gap(origin: Vector2, low: Vector2i, high: Vector2i) -> float:
	var boundary: float = INF # 没有未查区域时可以直接选定。
	if low.x > _first.x:
		boundary = minf(boundary, maxf(0.0, origin.x - low.x * BUCKET_SIZE))
	if high.x < _last.x:
		boundary = minf(boundary, maxf(0.0, (high.x + 1) * BUCKET_SIZE - origin.x))
	if low.y > _first.y:
		boundary = minf(boundary, maxf(0.0, origin.y - low.y * BUCKET_SIZE))
	if high.y < _last.y:
		boundary = minf(boundary, maxf(0.0, (high.y + 1) * BUCKET_SIZE - origin.y))
	return boundary

## [param point] 所在的世界桶。
static func _bucket(point: Vector2) -> Vector2i:
	return Vector2i((point / BUCKET_SIZE).floor())

## 返回快照 [param index] 的地面角色。
func target_at(index: int) -> Character000Base:
	return _targets[index]

## 返回快照 [param index] 对应的真实受击点节点，用于锁定后跟踪。
func point_at(index: int) -> Node2D:
	return _points[index]

## [param target] 仍是可锁定的活跃地面敌方角色。
static func ground_target(target: Character000Base) -> bool:
	if not is_instance_valid(target) or target.is_death or target.is_hypno or target.is_queued_for_deletion() \
			or not target.is_inside_tree() or not is_instance_valid(target.hurt_box_component) or not target.hurt_box_component.is_enabling:
		return false
	if target is Zombie000Base:
		return not target.retiring_from_battle and target.curr_be_attack_status == Zombie000Base.E_BeAttackStatusZombie.IsNorm
	return target is ZB000Base and target.lane >= 0 \
		and target.character_init_type == Character000Base.E_CharacterInitType.IsNorm

## 取得 [param target] 的真实受击形状中心，而非装饰精灵或影子的中心。
static func aim_point(target: Character000Base) -> Node2D:
	var area: Area2D = target.hurt_box_component.hurt_box_real # 原生区域。
	if not is_instance_valid(area):
		return null
	var center := area.get_node_or_null(^"CollisionShape2D") as Node2D # 多形状僵王回退到原区域中心。
	return center if center != null else area
