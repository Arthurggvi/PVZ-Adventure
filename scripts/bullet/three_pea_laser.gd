## 高能光束从真实动画炮口入行。冻结后的同一条路径用于墙面裁切、贯穿判定和绘制。
extends Bullet000NormBase

## 与普通豌豆相同的敌人真实受击层。
const TARGET_MASK: int = 512
## 受击带的半高，单位为世界像素。
const HALF_WIDTH: float = 7.0
## 出射到邻行的最短水平过渡，单位为世界像素。
const MIN_ENTRY: float = 54.0
## 出射曲线按固定八段采样，绘制与物理使用同一折线。
const ENTRY_STEPS: int = 8
## 炮口移动只带动画面前段，固定入行后的光束和墙面交点。
const MUZZLE_FOLLOW_DISTANCE: float = 66.0
## 单个脉冲的显示寿命，单位为游戏秒。
const LIFETIME: float = 0.19
## 每路火花数只限制表现，伤害依然覆盖整条路线。
const VISIBLE_CONTACTS: int = 6

## 从实际炮口到有效终点的冻结局部折线；首点为零。
var _path := PackedVector2Array()
## 仍存活时让显示的开头跟随口型动作。
var _muzzle: Marker2D
## 停在墙面时才画地形火花。
var _blocked: bool = false
## 当前线路颜色。
var _tint := Color(0.30, 1.0, 0.63)
## 火花位置位于实际命中路径，无额外碰撞或特效实体。
var _contacts := PackedVector2Array()
## 已播放的游戏秒数。
var _life: float = 0.0
## 跟随本轮射速缩短的表现寿命，单位为游戏秒。
var _pulse_lifetime: float = LIFETIME
## 只有首次命中影响催折时才定位路线上的第一个受击目标。
var _front_first: bool = false

## 从 [param muzzle] 向 [param rail_end] 发出贯穿脉冲。
## [param terrain] 裁切真实路径；[param source_lane] 与 [param lane_shift] 用于弯道的地面投影。
## [param tint] 只区分画面；[param interval] 缩短攻速较高时的辉光，[param order_first] 启用首中次序。
## 伤害仍在点火时结算一次。
func fire(muzzle: Marker2D, rail_end: Vector2, terrain: MainGameSlope,
		source_lane: int, lane_shift: float, tint: Color, interval: float, order_first: bool) -> void:
	_muzzle = muzzle
	_tint = tint
	_pulse_lifetime = minf(LIFETIME, maxf(1.0 / 60.0, interval - 0.006))
	_front_first = order_first
	_trace(rail_end, terrain, source_lane, lane_shift)
	if _path.size() >= 2:
		_hit_targets()
	queue_redraw()

## 向 [param rail_end] 建立单调向前的折线；入行前后使用对应的真实地形。
## [param terrain] 为空时只受战斗右界限制；[param source_lane] 和 [param lane_shift] 给出实际行差。
func _trace(rail_end: Vector2, terrain: MainGameSlope, source_lane: int, lane_shift: float) -> void:
	_path.append(Vector2.ZERO)
	var start: Vector2 = global_position # 真实炮口世界坐标。
	var facing: float = -1.0 if direction.x < 0.0 else 1.0 # 翻面时仍只沿出射方向前进。
	var distance: float = (rail_end.x - start.x) * facing # 剩余场地的可用横向距离。
	if distance <= 0.01:
		return
	var previous: Vector2 = start # 上一个尚未穿过地形的世界点。
	if lane != source_lane:
		var rise: float = rail_end.y - start.y # 当前炮口到邻行轨道的实际像素高差。
		var width: float = maxf(MIN_ENTRY, absf(rise) * 1.24) # 高差较大时拉长过渡，避免突然竖向折线。
		var portion: float = minf(1.0, distance / width) # 出界前还未入行时保留部分弯道。
		var previous_shift: float = 0.0 # 上一采样点从原行平移到的位置。
		for index: int in range(1, ENTRY_STEPS + 1): # 双端水平切线，出光和入行处都无横线接头。
			var t: float = portion * index / ENTRY_STEPS # 当前单调的水平进度。
			var blend: float = t * t * (3.0 - 2.0 * t) # 三次平滑入行。
			var point := start + Vector2(facing * width * t, rise * blend) # 同一路径的当前世界点。
			var shift: float = lane_shift * blend # 地面在两个攻击行之间连续取样。
			var clipped: Vector2 = _clip_entry(terrain, source_lane, previous, point, previous_shift, shift) # 精确到地面相交处。
			if _append_endpoint(previous, point, clipped):
				return
			previous = point
			previous_shift = shift
		if portion < 1.0:
			return
	var end: Vector2 = terrain.first_projectile_contact(previous, rail_end, lane, true) \
		if is_instance_valid(terrain) else rail_end # 入行以后直接查询目标行的原生碰撞线。
	_append_endpoint(previous, rail_end, end)

## 将从 [param start] 到 [param finish] 的入行段投影回 [param source_lane] 的地面。
## [param from_shift] 和 [param to_shift] 是两端跨行位移；同一比例还原 [param terrain] 的世界交点。
func _clip_entry(terrain: MainGameSlope, source_lane: int, start: Vector2, finish: Vector2,
		from_shift: float, to_shift: float) -> Vector2:
	if not is_instance_valid(terrain):
		return finish
	var flat_start := start - Vector2(0.0, from_shift) # 保留相对坡面的离地高度。
	var flat_end := finish - Vector2(0.0, to_shift) # 对应当前行间进度的同一地表。
	var contact: Vector2 = terrain.first_projectile_contact(flat_start, flat_end, source_lane, true) # 原生地形求交。
	return finish if contact.is_equal_approx(flat_end) else start.lerp(finish,
		(contact.x - flat_start.x) / (flat_end.x - flat_start.x))

## 保存 [param actual]；它比 [param planned] 早到时返回 true。和 [param previous] 重合时不写零长段。
func _append_endpoint(previous: Vector2, planned: Vector2, actual: Vector2) -> bool:
	if not previous.is_equal_approx(actual):
		_path.append(to_local(actual))
	_blocked = not planned.is_equal_approx(actual)
	return _blocked

## 一个宽相查询取出整束候选，只有带弯道的路线才逐段复核窄相。
func _hit_targets() -> void:
	var hull := ConvexPolygonShape2D.new() # 覆盖路径带的安全宽相，窄相会去掉凸包的空白角。
	var cloud := PackedVector2Array() # 每个采样点的受击带上下沿。
	var pad := Vector2(0.0, HALF_WIDTH) # 厚度按纵向扩展，端点不横向超出碰撞墙。
	for point: Vector2 in _path: # 使用同一条已裁切路线。
		cloud.append(point - pad)
		cloud.append(point + pad)
	hull.set_point_cloud(cloud)
	var areas: Array[Area2D] = CombatExplosion.query_shape(get_world_2d().direct_space_state,
		hull, global_transform, TARGET_MASK, true) # 每束只做一次物理空间宽相。
	if areas.is_empty():
		return
	var strips: Array[ConvexPolygonShape2D] = [] # 只在有候选时构造窄相段。
	if _path.size() > 2 or _front_first:
		for index: int in range(1, _path.size()): # 窄相严格沿绘制的连续路径。
			var a: Vector2 = _path[index - 1] # 当前段前端。
			var b: Vector2 = _path[index] # 当前段后端及真实裁切位置。
			var band := ConvexPolygonShape2D.new() # 单段闭合受击带。
			band.set_point_cloud(PackedVector2Array([a - pad, b - pad, b + pad, a + pad]))
			strips.append(band)
	var hit: Dictionary[int, bool] = {} # 同一脉冲每个敌人只结算一次。
	var pending: Dictionary[Character000Base, Vector2] = {} # 只有催折脉冲先冻结候选几何。
	var front: Character000Base # 当前光束最先接触的敌人。
	var first_x: float = INF # 沿出光方向计的最小接触距离。
	var facing: float = signf(_path[-1].x) # 镜像也沿实际飞行顺序定位。
	for area: Area2D in areas: # 实际生命与行资格仍由原生弹体处理。
		if not is_attack_active():
			break
		if not is_instance_valid(area):
			continue
		var enemy := area.owner as Character000Base # 普通僵尸、僵王与敌方设施共用原伤害。
		if not _can_attack_character(enemy) or enemy.is_hypno or hit.has(enemy.get_instance_id()):
			continue
		var spot: Vector2 = _contact_point(area, strips) # 凸包内但光束外的目标返回无效坐标。
		if not spot.is_finite():
			continue
		hit[enemy.get_instance_id()] = true
		if not _front_first:
			_resolve_contact(enemy, spot)
			continue
		pending[enemy] = spot
		if spot.x * facing < first_x:
			first_x = spot.x * facing
			front = enemy
	if front != null:
		_resolve_contact(front, pending[front])
		for enemy: Character000Base in pending: # 后排贯穿仍生效，只有首中判断需要前排优先。
			if is_instance_valid(enemy) and enemy != front and is_attack_active() and _can_attack_character(enemy):
				_resolve_contact(enemy, pending[enemy])

## 为确认命中的 [param enemy] 结算伤害及 [param spot] 处的火花。
func _resolve_contact(enemy: Character000Base, spot: Vector2) -> void:
	if _contacts.size() < VISIBLE_CONTACTS:
		_contacts.append(spot)
	attack_once(enemy)

## 返回 [param area] 和 [param strips] 的第一个交接段上的演出坐标，无接触时返回无穷。
## 无窄相段代表直线；这时宽相形状已经吻合受击带。
func _contact_point(area: Area2D, strips: Array[ConvexPolygonShape2D]) -> Vector2:
	var center: Vector2 = to_local(area.global_position) # 仅用于把火花贴回已确认命中的光束。
	if strips.is_empty():
		return Geometry2D.get_closest_point_to_segment(center, _path[0], _path[1])
	var facing: float = signf(_path[-1].x) # 投影到正向后，第一个交接段最先结算。
	var closest: Vector2 = Vector2.INF # 多个真实受击形状取最靠前的交点。
	var best: float = INF # 起始无任何交点。
	for owner_id: int in area.get_shape_owners(): # 实际真实受击区可拆成几个形状。
		if area.is_shape_owner_disabled(owner_id):
			continue
		var at: Transform2D = area.global_transform * area.shape_owner_get_transform(owner_id) # 不猜目标宽高。
		for shape_index: int in range(area.shape_owner_get_shape_count(owner_id)): # 每个有效受击形状。
			var shape: Shape2D = area.shape_owner_get_shape(owner_id, shape_index) # 空形状不能产生命中。
			if shape == null:
				continue
			for index: int in strips.size(): # 单段无需再查询世界碰撞层。
				if not strips[index].collide(global_transform, shape, at):
					continue
				var a: Vector2 = _path[index] # 已确认碰撞的路径段起点。
				var b: Vector2 = _path[index + 1] # 已确认碰撞的路径段终点。
				if not _front_first:
					return Geometry2D.get_closest_point_to_segment(center, a, b)
				var bounds: Rect2 = (global_transform.affine_inverse() * at) * shape.get_rect() # 取命中形状自身的前缘。
				var edge: float = bounds.position.x if facing > 0.0 else bounds.end.x # 沿光束前进方向的入射侧。
				var entry: float = clampf((edge - a.x) / (b.x - a.x), 0.0, 1.0) # 至少已经抵达当前碰撞段。
				var contact: Vector2 = a.lerp(b, entry) # 同一路由上的首中排序位置。
				if contact.x * facing < best:
					best = contact.x * facing
					closest = contact
				break # 该受击形状之后的路径只会更远。
	return closest

## [param delta] 为游戏秒；暂停及阶段切换沿用弹体原生门禁。
func _process(delta: float) -> void:
	_life += delta
	if _life >= _pulse_lifetime or not is_attack_active():
		queue_free()
	else:
		queue_redraw()

## 返回仍贴在活动口型上的显示路径；命中结果和墙面终点保持在点火时的位置。
func _visual_path() -> PackedVector2Array:
	if _path.size() < 2 or not is_instance_valid(_muzzle) or not _muzzle.is_inside_tree():
		return _path
	var lip: Vector2 = to_local(_muzzle.global_position) # 当前动画帧的炮口。
	var facing: float = signf(_path[-1].x) # 横向归一后始终正向。
	var extent: float = _path[-1].x * facing # 不以口型位移延长已裁切的路径。
	if lip.is_zero_approx():
		return _path
	if lip.x * facing >= extent:
		return PackedVector2Array() # 炮口已经到了终点之后时结束显示。
	var reach: float = minf(extent, maxf(MUZZLE_FOLLOW_DISTANCE, lip.x * facing * 2.0)) # 混合范围内横坐标保持单调。
	var points := PackedVector2Array([lip]) # 第一笔正好从当前炮口发出。
	for index: int in range(1, _path.size()): # 只有近炮口的几个采样点发生变形。
		var point: Vector2 = _path[index] # 已结算的真实折线顶点。
		var x: float = point.x * facing # 从点火点沿光束的水平距离。
		var before: float = _path[index - 1].x * facing # 上一个真实顶点的水平距离。
		if before < reach and x > reach:
			points.append(_path[index - 1].lerp(point, (reach - before) / (x - before)))
		var u: float = clampf(x / reach, 0.0, 1.0) # x 线性回归保证不会反折，y 平滑收回。
		points.append(point + Vector2(lip.x * (1.0 - u), lip.y * (1.0 - smoothstep(0.0, 1.0, u))))
	return points

## 从炮口到截断点只绘制一条连续路径，三层亮度共享相同的中心线。
func _draw() -> void:
	var points: PackedVector2Array = _visual_path() # 当前口型与冻结轨迹的连续结果。
	if points.size() < 2:
		return
	var u: float = clampf(_life / _pulse_lifetime, 0.0, 1.0) # 归一化脉冲时间。
	var brightness: float = pow(1.0 - u, 0.82) # 先给出清晰亮芯，再收去辉光。
	draw_polyline(points, Color(_tint, 0.18 * brightness), 15.0 * brightness + 3.0, true)
	draw_polyline(points, Color(_tint, 0.7 * brightness), 6.4 * brightness + 1.4, true)
	draw_polyline(points, Color(0.92, 1.0, 0.97, brightness), 2.6 * brightness + 0.6, true)
	draw_circle(points[0], 2.8 * brightness + 0.5, Color(0.84, 1.0, 0.91, minf(1.0, 1.25 * brightness)), true, -1.0, true)
	_draw_glint(points, u, brightness)
	if u < 0.7:
		for point: Vector2 in _contacts: # 火花只附着于已命中的轨迹段。
			_scatter(point, 0.62, brightness, u)
	if _blocked:
		_scatter(points[-1], 1.30, brightness, u)

## 让高光沿 [param points] 推进；[param age] 与 [param brightness] 共用该脉冲的时间。
func _draw_glint(points: PackedVector2Array, age: float, brightness: float) -> void:
	var facing: float = signf(points[-1].x - points[0].x) # 镜像仍沿轨迹前进。
	var nose: float = lerpf(points[0].x, points[-1].x, smoothstep(0.0, 0.81, age)) * facing # 当前高光前端。
	for index: int in range(1, points.size()): # 高光经过拐弯时分段贴合，不走弦外。
		var a: Vector2 = points[index - 1] # 当前段的局部起点。
		var b: Vector2 = points[index] # 当前段的局部终点。
		var left: float = a.x * facing # 该段起始横距。
		var right: float = b.x * facing # 该段结束横距。
		var from: float = maxf(left, nose - 37.0) # 高光尾部裁在段内。
		var to: float = minf(right, nose) # 不越过墙或路径末端。
		if to > from:
			draw_line(a.lerp(b, (from - left) / (right - left)),
				a.lerp(b, (to - left) / (right - left)), Color(1.0, 1.0, 0.94, 0.84 * brightness), 3.6, true)

## 从 [param origin] 向来向散出碎光；[param size_factor] 区分普通命中与墙面。
## [param brightness] 与 [param age] 驱动有限粒子形状的衰减。
func _scatter(origin: Vector2, size_factor: float, brightness: float, age: float) -> void:
	var travel: float = signf(_path[-1].x) # 碎光始终落在来光方向一侧。
	for index: int in range(4): # 固定几条碎光，无独立节点。
		var spread: float = (index - 1.5) * (4.0 + age * 6.0) * size_factor # 侧向散开。
		var reach: float = (4.0 + index * 1.7 + age * 14.0) * size_factor # 回弹距离。
		draw_line(origin + Vector2(-travel * (1.0 + age * 2.0), spread * 0.36),
			origin + Vector2(-travel * reach, spread),
			Color(1.0, 0.88, 0.52, brightness * 0.78), 1.25 * size_factor, true)
