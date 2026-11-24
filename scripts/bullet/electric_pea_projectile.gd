## 电球沿真实世界轨迹穿透，独立按半秒节奏向附近敌人放电。
extends Node2D
class_name ElectricPeaProjectile

## 从共享图集播放球面与方向电光的飞行表现。
const ProjectileVisual = preload("res://scripts/fx/electric_pea_flight_sprite.gd")
## 原版电球在坡面坐标内的飞行速率，单位为世界像素每秒。
const SPEED: float = 180.0
## 每次邻近放电之间的游戏秒数。
const BOLT_INTERVAL: float = 0.5
## 三种普通球的循环片段。
const PROJECTILE_CLIPS: Array[StringName] = [&"projectile", &"projectile2", &"projectile3"]

## 相邻电球同一几何批次内的棋盘中心；完成一次同步受击结算后重新读取。
const LANE_GEOMETRY_META: StringName = &"_electric_pea_lane_centers"

## 冻结战局、伤害与来源；须在入树前配置。
var shot: ElectricPeaShotContext
## 离手前设置的坡面相对方向；入树后固定，不吸附邻行或追随母株。
var flight_direction: Vector2 = Vector2.RIGHT
## 入树时冻结的坡面相对速度，单位为世界像素每秒；所有方向保持相同速率。
var velocity: Vector2 = Vector2.ZERO
## 最近物理帧的世界速度，包含屋顶高度变化，供弹体表现对齐真实运动。
var frame_velocity: Vector2 = Vector2.ZERO
## 仅离手时读取的原始地块，用于冻结枪口到地面中心的高度差。
var launch_origin: PlantCell
## 是否为分裂后代，决定尺寸、伤害及是否仍可分裂。
var is_child_ball: bool = false
## 放电的当前攻击行，随斜向飞行更新。
var _lane: int = -1
## 原始飞行坡面，母株移除不改变已经离手的轨迹。
var _slope: MainGameSlope
## 当前坡面相对高度，按固定二维速度推进，单位为世界像素。
var _level_y: float = 0.0
## 枪口到地格中心的固定高度差；后代继承，避免跨行定位受弹体离地高度影响。
var _lane_height_offset: float = 0.0
## 距下次放电的游戏秒数；首轮采用原版随机相位。
var _bolt_remaining: float = 0.0
## 每枚球的直击记录，独立于每轮放电目标。
var _contact_ids: Dictionary[int, bool] = {}
## 本颗球的实际承伤去重；多枚弹体各自允许独立伤害，保护者代伤同弹只结算一次。
var _hit_scope: CombatHitScope = CombatHitScope.new()
## 每枚球独立碰撞大小和连续碰撞查询器。
var _query: ElectricPeaFlightQuery
## 生存秒数限制永久追随弹体的镜头造成的泄漏。
var _elapsed: float = 0.0
## 跟随速度调整的寿命上界。
var _lifetime: float = 0.0
## 折算转职后的坡面相对飞行速率，单位为世界像素每秒。
var _speed: float = SPEED
## 小球仅乘一次比例，普通球保持离手伤害。
var _damage_multiplier: float = 1.0
## 跟随逻辑物理帧更新的方向性电球表现，暂停时保持静止。
var _flight_visual: ProjectileVisual


## 入树后建立独立表现和放电计时；无有效战局时直接释放。
func _ready() -> void:
	if shot == null or not shot.is_active():
		queue_free()
		return
	# 暂停时仍核对战场身份，换场立即清掉旧弹。
	process_mode = Node.PROCESS_MODE_ALWAYS
	_lane = shot.lane if _lane < 0 else _lane
	z_index = _lane * 50 + 45
	_slope = shot.game.main_game_slope
	_level_y = _height_above_slope(global_position)
	if is_instance_valid(launch_origin):
		var ground: Vector2 = launch_origin.get_global_rect().get_center() # 普通棋盘用格心校准。
		if shot.board.definition != null and shot.board.definition.project_surface_combat_lanes:
			ground = launch_origin.get_spawn_global_position()
		_lane_height_offset = _height_above_slope(ground) - _level_y
	launch_origin = null
	_speed = SPEED * shot.promotions.speed_multiplier
	velocity = flight_direction.normalized() * _speed
	frame_velocity = velocity
	_bolt_remaining = BOLT_INTERVAL if is_child_ball else randf_range(0.0, BOLT_INTERVAL)
	_lifetime = maxf(8.0 * SPEED, _screen_rect().size.x * 2.0) / _speed
	var size_multiplier: float = shot.promotions.split_size if is_child_ball else 1.0 # 小球缩小碰撞与美术。
	_damage_multiplier = shot.promotions.split_damage if is_child_ball else 1.0
	_query = ElectricPeaFlightQuery.new(size_multiplier)
	var clip: StringName = PROJECTILE_CLIPS.pick_random() # 保留三种球面循环与原有战斗随机数顺序。
	_flight_visual = ProjectileVisual.new()
	_flight_visual.configure(shot.appearance_rank, is_child_ball, clip)
	_flight_visual.scale *= size_multiplier
	add_child(_flight_visual)
	_flight_visual.advance_visual(_elapsed, frame_velocity)
	if shot.matrix_damage > 0:
		ElectricPeaMatrix.register_ball(self)


## [param delta] 为游戏物理秒数，屋顶折线与斜向位移都纳入连续扫掠。
func _physics_process(delta: float) -> void:
	if shot == null or not shot.is_active():
		queue_free()
		return
	if get_tree().paused:
		return
	_elapsed += delta
	if _elapsed >= _lifetime:
		queue_free()
		return
	var start: Vector2 = global_position # 本帧真实起点，用于恢复世界速度。
	var start_y: float = _level_y # 保存上一帧的坡面相对高度，不累积屋顶投影误差。
	var advance: Vector2 = velocity * delta # 正向、反向及竖向使用同一速率，不靠tan放大斜向速度。
	_level_y += advance.y
	var finish_x: float = start.x + advance.x # 不继承母株或移动平台的横向位移。
	var finish_y: float = _level_y # 坡面相对高度持续线性变化，经过邻行也不拐平。
	var finish := Vector2(finish_x, finish_y + ElectricPeaFlightQuery.height_at(_slope, finish_x)) # 世界终点。
	frame_velocity = (finish - start) / delta if delta > 0.0 else velocity
	var points: Array[Vector2] # 正反向跨过坡面折点时逐段扫掠，平地只有当前步起止点。
	if is_instance_valid(_slope):
		points = ElectricPeaFlightQuery.path_points(start, finish, _slope, start_y, finish_y)
	else:
		points = [start, finish]
	var candidates: Array[Character000Base] # 跨折点保留本步起始资格，单段可在几何粗筛后检查资格。
	var cohort: ElectricPeaFlightQuery.FlightCohort # 只在确认单段与相邻弹体连续执行时复用世界几何。
	if points.size() > 2:
		candidates = ElectricPeaFlightQuery.all_targets(shot.game)
	else:
		candidates = ElectricPeaFlightQuery.raw_targets(shot.game)
		cohort = _query.begin_projectile_candidates(shot.game, self, candidates)
	for index: int in range(1, points.size()): # 命中回调结束战局或分裂时立即停止旧球。
		_move_segment(points[index], candidates, cohort)
		if is_queued_for_deletion() or not shot.is_active():
			queue_free()
			return
		if get_tree().paused:
			_level_y = _height_above_slope(global_position)
			return
	_flight_visual.advance_visual(_elapsed, frame_velocity)
	_bolt_remaining -= delta
	if _bolt_remaining <= 0.0:
		_bolt_remaining = BOLT_INTERVAL
		ElectricPeaBolt.discharge(shot, global_position, _lane, roundi(shot.bolt_damage * _damage_multiplier))
	var screen: Rect2 = _screen_rect().grow(ElectricPeaFlightQuery.HALF_SIZE) # 给球体边缘留下可见空间。
	if not screen.has_point(global_position):
		queue_free()


## 按弹体的真实地面投影更新攻击行；离板侧弹只选实际存在的最近行，不改变飞行方向。
func _refresh_lane() -> void:
	if not is_child_ball and is_zero_approx(velocity.y):
		return
	var ground: Vector2 = global_position + Vector2(0.0, _lane_height_offset) # 抵消枪口离地高度后再定位。
	var lane: int # 浮台棋盘只按弹体自己的脚点判断是否跨行。
	if shot.board.definition != null and shot.board.definition.project_surface_combat_lanes:
		lane = shot.board.lane_at_foot_y(shot.game.to_local(ground).y)
	else:
		var cohort := ElectricPeaFlightQuery.current_projectile_cohort(shot.game, self) # 同批弹体可共享场地几何。
		lane = ElectricPeaFlightQuery.nearest_lane(shot.board, ground, _slope, _lane) \
			if cohort == null else _nearest_cached_lane(cohort, ground)
	if _lane != lane:
		_lane = lane
		z_index = _lane * 50 + 45


## 从 [param cohort] 的活动几何中读取 [param ground] 对应的攻击行，保持原注册顺序与等距离口径。
func _nearest_cached_lane(cohort: ElectricPeaFlightQuery.FlightCohort, ground: Vector2) -> int:
	var geometry: Dictionary = cohort.get_meta(LANE_GEOMETRY_META, {}) # 批次独占，失效后可读取新平台位置。
	if geometry.get("generation", -1) != cohort.geometry_generation or geometry.get("board") != shot.board \
			or geometry.get("slope") != _slope:
		var flat: bool = not is_instance_valid(_slope) # 平地格心和飞行点共用世界坐标。
		var centers := PackedVector2Array() # 保留地块入场顺序，同距时选早登记的格子。
		var rows := PackedInt32Array() # 每个中心的实际攻击行，兼容空洞及不规则地块。
		for cell: PlantCell in shot.board.cells(): # 折线和平台当前位姿均参与投影。
			if not is_instance_valid(cell) or cell.is_queued_for_deletion() or not cell.is_visible_in_tree():
				continue
			var center: Vector2 = cell.get_global_rect().get_center() # 舞台当前位姿下的格心。
			if not flat:
				center.y -= ElectricPeaFlightQuery.height_at(_slope, center.x)
			centers.append(center)
			rows.append(cell.row_col.x)
		var columns: int = _shared_lane_columns(centers, rows) if flat else 0 # 只对当下确实对齐的平地图形按行缩减候选。
		geometry = {"generation": cohort.geometry_generation, "board": shot.board, "slope": _slope,
			"centers": centers, "rows": rows, "columns": columns}
		cohort.set_meta(LANE_GEOMETRY_META, geometry)
	var centers: PackedVector2Array = geometry.centers # 只读访问批次内的格心。
	var rows: PackedInt32Array = geometry.rows # 原地格登记顺序的攻击行。
	var columns: int = geometry.columns # 零表示按旧规则逐格扫描。
	var point: Vector2 = ground # 平地坐标直接使用；坡面展开后再进行平面距离比较。
	var first: int = 0 # 普通查询从首个格心开始，对齐棋盘从最接近的列开始。
	var step: int = 1 # 普通查询逐格，对齐棋盘每行只读一个格心。
	if columns > 0:
		var horizontal_gap: float = INF # 到所有行共用的最近列的横向距离。
		for column: int in range(columns): # 从第一行的列坐标找出所有行共用的最近列。
			var gap: float = absf(point.x - centers[column].x) # 行内等高，横向距离最小的格心也有最小总距离。
			if gap < horizontal_gap:
				horizontal_gap = gap
				first = column
		step = columns
	else:
		point.y -= ElectricPeaFlightQuery.height_at(_slope, ground.x)
	var closest: float = INF # 平面最短平方距离。
	var lane: int = _lane # 如果当前没有可见格则沿用已知行。
	for index: int in range(first, centers.size(), step): # 用原距离函数和严格小于比较，保留跨行同距顺序。
		var distance: float = point.distance_squared_to(centers[index]) # 本弹到当前格心的平方距离。
		if distance < closest:
			closest = distance
			lane = rows[index]
	return lane


## 核对 [param centers]、[param rows] 能否按原顺序分成等高且共享横向格心的若干行。
## 返回共用列数；错位、破坏对齐的缺格、非有限坐标或单行单列时返回零。
static func _shared_lane_columns(centers: PackedVector2Array, rows: PackedInt32Array) -> int:
	if centers.is_empty():
		return 0
	var columns: int = 1 # 第一段连续攻击行决定各行都必须满足的列数。
	while columns < rows.size() and rows[columns] == rows[0]:
		columns += 1
	if columns < 2 or columns == centers.size() or centers.size() % columns != 0:
		return 0
	for index: int in range(centers.size()): # 用实时格心验证分离条件，平台错位后不沿用旧布局。
		var column: int = index % columns # 在第一行内同序的列。
		var row_start: int = index - column # 本行最早登记的格心及其实际攻击行。
		var center: Vector2 = centers[index] # 当前参与距离计算的真实格心。
		if not center.is_finite() or rows[index] != rows[row_start] \
				or center.x != centers[column].x or center.y != centers[row_start].y:
			return 0
	return columns


## 沿当前位置至 [param finish] 搜索 [param candidates]，先结算最近的真实接触。
## [param cohort] 为当前单段可共享的查询范围，多段飞行各段实时读取目标。
func _move_segment(finish: Vector2, candidates: Array[Character000Base],
		cohort: ElectricPeaFlightQuery.FlightCohort) -> void:
	var start: Vector2 = global_position # 固定本段起点，按比例还原实际撞击位置。
	var contacts: Array[Dictionary] = [] # 先排序，碰撞顺序独立于场景树顺序。
	for index: int in _query.overlapping_target_indices(candidates, start, finish, cohort): # 结算前消费全部有序下标。
		var reference: Variant = candidates[index] # 前一坡段的伤害可能使原候选失效。
		if not is_instance_valid(reference) or not ElectricPeaFlightQuery.can_hit(reference):
			continue
		var target: Character000Base = reference # 已通过当前实例与攻击状态检查。
		if _contact_ids.has(target.get_instance_id()) or (target is EnemyStructureBase \
				and is_zero_approx(velocity.y) and not is_child_ball and target.lane != _lane):
			continue
		var area: Area2D = target.hurt_box_component.hurt_box_real # 真实区域仍需通过禁用和释放检查。
		var fraction: float = _query.candidate_contact_fraction(index, area, start, finish, cohort) # 连出生重叠一起检查。
		if is_finite(fraction):
			contacts.append({"target": target, "fraction": fraction})
	if contacts.size() > 1:
		contacts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.fraction) < float(b.fraction)) # a、b 为两次待结算接触。
	var splitting: bool = not is_child_ball and shot.promotions.split_count > 0 # 后代始终继续穿透。
	for contact: Dictionary in contacts: # 每次攻击后重查战局与下一个目标。
		if not shot.is_active() or get_tree().paused:
			return
		var target: Variant = contact.target # 弱引用经受击回调可能已经失效。
		if not is_instance_valid(target) or not ElectricPeaFlightQuery.can_hit(target):
			continue
		var target_id: int = target.get_instance_id() # 即使后续死亡仍能屏蔽子球出生碰撞。
		_contact_ids[target_id] = true
		global_position = start.lerp(finish, float(contact.fraction))
		_refresh_lane()
		var kind := ElectricPeaShotContext.HitKind.SPLIT if splitting else ElectricPeaShotContext.HitKind.CONTACT # 只有母球首次合法接触可触发分裂，后代不再递归。
		shot.hit(target, roundi(shot.contact_damage * _damage_multiplier), kind, _hit_scope)
		if splitting:
			if shot.is_active():
				# 接触与分裂作为同一事件完成；若受击回调暂停，后代留在命中点等待恢复。
				_split(target_id)
			queue_free()
			return
		if not shot.is_active() or get_tree().paused:
			return
	global_position = finish
	_refresh_lane()


## 在撞击点向整圈分层散射；[param parent_target_id] 标记小球出生时必须绕过的母命中目标。
func _split(parent_target_id: int) -> void:
	var count: int = shot.promotions.split_count # 各子球随机占据不同扇区，避免重合方向。
	var segment: float = TAU / count # 等分整圈；三颗子球的基准方向彼此相隔120度。
	var phase: float = randf_range(0.0, TAU) # 每次分裂整体旋转，避免固定向右的偏向。
	var jitter: float = minf(segment * 0.1, deg_to_rad(12.0)) # 有限抖动保证三颗不会全部挤入同一半圆。
	for index: int in range(count): # 各子球从同一个命中点离手并独立放电。
		var child: ElectricPeaProjectile = get_script().new() # 同一弹体实现，后代不再分裂。
		child.shot = shot
		child.is_child_ball = true
		child._lane = _lane
		child._lane_height_offset = _lane_height_offset
		child._contact_ids[parent_target_id] = true
		child.flight_direction = Vector2.from_angle(phase + float(index) * segment + randf_range(-jitter, jitter))
		child.position = get_parent().to_local(global_position)
		get_parent().add_child(child)


## 将 [param point] 换算为扣除当前坡面的世界高度。
func _height_above_slope(point: Vector2) -> float:
	return point.y - ElectricPeaFlightQuery.height_at(_slope, point.x)


## 返回当前镜头的世界可见矩形，兼容平移和缩放。
func _screen_rect() -> Rect2:
	return get_canvas_transform().affine_inverse() * get_viewport_rect()
