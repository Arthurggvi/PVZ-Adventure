## 战场唯一的超导电弧画布与固定帧结算器，按实际出手植株组织有界连线。
extends Node2D
class_name ElectricPeaMatrix

## 同一战场的子节点名；仅首枚选中矩阵的电球离手时建立。
const NODE_NAME: StringName = &"ElectricPeaMatrix"
## 每六十分之一游戏秒独立扣一次伤。
const STEP: float = 1.0 / 60.0
## 电弧的真实世界宽度与连续主线宽度共用同一参数，单位为像素。
const WIDTH: float = 2.0
## 最多为这些真实连线叠加流动碎电光，其余连线仍完整绘制真实主线。
const DECORATION_BUDGET: int = 96
## 矩阵沿用同一出手等阶的独立电能配色。
const PromotionArt = preload("res://scripts/adventure/plant_art/adventure_electric_peashooter_promotion_art.gd")
## 与短时放电共用稳定几何及细芯绘制，不共用伤害或生命周期。
const ArcVisual = preload("res://scripts/fx/electric_pea_arc_visual.gd")
## 流动电光共用一个有序的抗锯齿网格。
const StrokeBatch = preload("res://scripts/fx/electric_pea_stroke_batch.gd")
## 实例着色器在固定宽度的四边形内合成连续主线。
const MatrixBeams = preload("res://scripts/fx/electric_pea_matrix_beams.gd")
## 区分未接触、已接触且可续用几何，以及必须刷新几何的同步接触。
enum FieldContact { MISS, STABLE, REFRESH }

## 源植株实例 ID 到个体电球列表；换场或空组时回收。
var _groups: Dictionary[int, Array] = {}
## 当前展示帧的线段端点，每对端点为一条独立线。
var _lines := PackedVector2Array()
## 物理步已更新连线快照，等待画面更新统一提交。
var _redraw_pending: bool = false
## 每条线右端电球的实际出手配色，与本线真实伤害的出手快照一致。
var _line_ranks := PackedInt32Array()
## 由真实端点身份生成的稳定噪声种子，排序移动不会导致逐帧闪烁。
var _line_seeds := PackedInt64Array()
## 仅非暂停时推进的表现游戏秒数，独立于固定伤害累积器。
var _visual_time: float = 0.0
## 五档颜色只在画布建立时读取，逐帧绘制不复制色表字典。
var _colors: Array[Dictionary] = []
## 固定结算帧尚未消费的游戏秒数。
var _elapsed: float = 0.0
## 整个战场共用一份几何探针，每段调整长度。
var _probe := RectangleShape2D.new()
## 随显示帧更新的流光网格。
var _strokes := StrokeBatch.new()
## 单个实例批次绘制全部真实主线。
var _main_beams := MatrixBeams.new()


## 在同步矩阵结算中，按原候选顺序惰性读取世界范围；受击回调可使任何范围失效。
class FieldCandidates:
	## 已通过此物理步原始资格快照的角色，顺序决定同一线段内的命中顺序。
	var targets: Array[Character000Base] = []
	## 角色索引对应的最新安全包围盒，未知形状保留精确扫描。
	var bounds: Array[Rect2] = []
	## 每个包围盒的读取代数；零代表从未读取。
	var sample_epochs := PackedInt32Array()
	## 单个有效形状可直接交给矩阵碰撞探针，多形状和未知区域仍遍历真实拥有者。
	var shapes: Array[Shape2D] = []
	## 与安全包围盒和形状同代数的世界变换。
	var transforms: Array[Transform2D] = []
	## 单形状拥有者的索引；只在进入精确阶段时核对禁用状态。
	var owner_ids := PackedInt32Array()
	## 同一同步区间已核对的受击监听，按候选槽位复用。
	var audit := ElectricPeaShotContext.FieldAudit.new()
	## 当前没有外部回调介入的同步查询区间。遇到未知回调时开始新区间。
	var epoch: int = 1
	## 本区间已读取的有限包围盒数；未取得全体范围时不能使用整体粗筛。
	var _sample_count: int = 0
	## 本区间有无法用单个有限矩形安全筛选的范围。
	var _has_unknown: bool = false
	## 当前区间所有候选的联合范围。
	var _total_bounds := Rect2()

	## [param enemies] 保留原候选顺序，只保留有资格承受场伤的角色类别。
	func _init(enemies: Array[Character000Base]) -> void:
		for target: Character000Base in enemies: # 目标类别不会随受击改变。
			if target is Zombie000Base or target is ZB000Base:
				targets.append(target)
		bounds.resize(targets.size())
		sample_epochs.resize(targets.size())
		shapes.resize(targets.size())
		transforms.resize(targets.size())
		owner_ids.resize(targets.size())
		audit.flags.resize(targets.size())

	## 同步命中可移动、移除或重新配置任意受击区域，下次读取刷新受影响的查询。
	func invalidate() -> void:
		epoch += 1
		_sample_count = 0
		_has_unknown = false
		audit.flags.fill(0)

	## [param line_bounds] 只在当前代数内已读取全体有限范围时才进行整线排除。
	func outside(line_bounds: Rect2) -> bool:
		return not _has_unknown and _sample_count == targets.size() \
			and not line_bounds.intersects(_total_bounds, true)

	## 读取 [param index] 的即时几何和精确查询数据；未知区域保守走原有形状查询。
	func refresh(index: int) -> Rect2:
		var world: Rect2 = _read_geometry(index) # 仅同代数复用同一份形状和变换。
		sample_epochs[index] = epoch
		bounds[index] = world
		if not _has_unknown:
			if world.size.x < 0.0:
				_has_unknown = true
			else:
				_sample_count += 1
				if _sample_count == targets.size():
					_total_bounds = bounds[0]
					for slot: int in range(1, bounds.size()): # 只在收齐有限范围时统一合并。
						_total_bounds = _total_bounds.merge(bounds[slot])
		return world

	## 返回 [param index] 的单形状世界范围并记下精确查询所需数据，未知几何不参与粗筛。
	func _read_geometry(index: int) -> Rect2:
		shapes[index] = null
		var reference: Variant = targets[index] # 较早的命中可能已经释放了对象。
		if not is_instance_valid(reference) or not is_instance_valid(reference.hurt_box_component):
			return ElectricPeaFlightQuery.UNKNOWN_BOUNDS
		var area: Area2D = reference.hurt_box_component.hurt_box_real # 真正承受矩阵伤害的区域。
		if not is_instance_valid(area):
			return ElectricPeaFlightQuery.UNKNOWN_BOUNDS
		var owners: PackedInt32Array = area.get_shape_owners() # 同步改挂后立即读取新的形状清单。
		if owners.size() != 1 or area.shape_owner_get_shape_count(owners[0]) != 1:
			return ElectricPeaFlightQuery.UNKNOWN_BOUNDS
		var owner_id: int = owners[0] # 已确认只有一名拥有者及一个真实形状。
		var shape: Shape2D = area.shape_owner_get_shape(owner_id, 0) # 资源替换或改挂在本次读取生效。
		if shape == null or shape is WorldBoundaryShape2D:
			return ElectricPeaFlightQuery.UNKNOWN_BOUNDS
		var pose: Transform2D = area.global_transform * area.shape_owner_get_transform(owner_id) # 包含祖先的当前世界变换。
		var world: Rect2 = pose * shape.get_rect() # 同一形状精确碰撞前使用的世界包围盒。
		if not world.position.is_finite() or not world.size.is_finite():
			return ElectricPeaFlightQuery.UNKNOWN_BOUNDS
		shapes[index] = shape
		transforms[index] = pose
		owner_ids[index] = owner_id
		return world


## 只缓存表现用色；矩阵登记、排序和固定伤害时钟沿用原生命周期。
func _ready() -> void:
	add_child(_main_beams)
	for rank: int in range(5): # 五阶色表固定，所有同阶连线只读共享。
		_colors.append(PromotionArt.effect_colors(rank))


## 将 [param ball] 登记到其原战场，扩散和分裂后代沿用相同来源ID。
static func register_ball(ball: ElectricPeaProjectile) -> void:
	var container: Node2D = ball.get_parent() # 与所有电球共用战场容器的生命周期。
	var matrix: ElectricPeaMatrix = container.get_node_or_null(NodePath(NODE_NAME)) as ElectricPeaMatrix # 同一个容器仅建立一次。
	if matrix == null:
		matrix = ElectricPeaMatrix.new()
		matrix.name = NODE_NAME
		matrix.z_index = 349
		# 电球在默认优先级移动；矩阵观察本物理帧移动后的世界端点。
		matrix.process_physics_priority = 10
		matrix.process_mode = Node.PROCESS_MODE_ALWAYS
		container.add_child(matrix)
	var id: int = ball.shot.source_id # 本株死亡后不重新绑定来源。
	if not matrix._groups.has(id):
		matrix._groups[id] = []
	matrix._groups[id].append(ball)


## 在 [param delta] 游戏物理秒内消费所有应到的固定帧；暂停时只清理失效节点并更新画布。
func _physics_process(delta: float) -> void:
	_lines.clear()
	_line_ranks.clear()
	_line_seeds.clear()
	var networks: Array[Array] = [] # 只有至少两枚有效球的植株有可计算线段。
	var game: MainGameManager = null # 每个画布仅服务自己的唯一战场。
	var local_from_world: Transform2D = global_transform.affine_inverse() # 全部线段共用同一画布坐标变换。
	for id: int in _groups.keys(): # 已离场的电球不占据活跃列表。
		var balls: Array = _groups[id] # 按引用更新后续帧使用的列表。
		for index: int in range(balls.size() - 1, -1, -1): # 倒序清理失效的战局、轮次或阶段。
			var ball: Variant = balls[index] # 节点可能已经被释放。
			if not is_instance_valid(ball) or ball.is_queued_for_deletion() or not ball.shot.is_active():
				balls.remove_at(index)
		if balls.is_empty():
			_groups.erase(id)
			continue
		if balls.size() < 2:
			continue
		balls.sort_custom(_position_less)
		networks.append(balls)
		game = balls[0].shot.game
		var previous_point: Vector2 = local_from_world * balls[0].global_position # 同一球是两条相邻线的公共端点。
		var previous_id: int = balls[0].get_instance_id() # 每对当前邻居的稳定流光种子。
		for index: int in range(1, balls.size()): # 每个球只连接排序中的前一个球，总共 N-1 条。
			var ball: ElectricPeaProjectile = balls[index] # 当前线段右端球及其离手时的配色。
			var point: Vector2 = local_from_world * ball.global_position # 同时供下一条线的起点使用。
			var ball_id: int = ball.get_instance_id() # 球销毁前保持不变。
			_lines.append(previous_point)
			_lines.append(point)
			_line_ranks.append(clampi(ball.shot.appearance_rank, 0, 4))
			_line_seeds.append(previous_id ^ (ball_id * 31))
			previous_point = point
			previous_id = ball_id
	_redraw_pending = true
	if _groups.is_empty():
		queue_free()
		return
	if networks.is_empty():
		_elapsed = 0.0
		return
	if get_tree().paused:
		return
	_visual_time += delta
	_elapsed += delta
	if _elapsed + 0.000001 < STEP:
		return
	var candidates := FieldCandidates.new(ElectricPeaFlightQuery.all_targets(game)) # 保留同一物理帧全部矩阵线的资格快照。
	while _elapsed + 0.000001 >= STEP: # 时间倍率改变时执行全部应结算帧，没有视觉降级伤害。
		_elapsed = maxf(0.0, _elapsed - STEP)
		for balls: Array in networks: # 每株在此固定帧使用各自的去重账本。
			_strike(balls, candidates)


## [param _delta] 无需推进状态。显示更新只提交最新物理快照，暂停时也可移除失效连线。
func _process(_delta: float) -> void:
	if _redraw_pending:
		_redraw_pending = false
		queue_redraw()


## 对 [param balls] 的排序邻接线用真实几何求交 [param candidates]；每个实体每源每帧只结算一次。
func _strike(balls: Array, candidates: FieldCandidates) -> void:
	var targets: Array[Character000Base] = candidates.targets # 同步区间共享原候选顺序。
	var enemy_count: int = targets.size() # 整个结算阶段使用同一资格快照。
	if enemy_count == 0:
		return
	var enemy_bounds: Array[Rect2] = candidates.bounds # 数值筛选直接访问共享范围。
	var sample_epochs: PackedInt32Array = candidates.sample_epochs # 已缓存范围的代数与范围数组一一对应。
	var contacted := PackedByteArray() # 按去重后的候选索引保存本源本帧的接触记录。
	contacted.resize(enemy_count)
	var remaining: int = enemy_count # 本源还未接触的候选数，全部接触后无需再读取球和形状。
	var scope := CombatHitScope.new() # 本株此固定帧内共享的实际承伤资格。
	for index: int in range(1, balls.size()): # 顺序传递连线，不构造两两组合。
		var left: Variant = balls[index - 1] # 命中同步触发离场时原端点可能失效。
		var right: Variant = balls[index] # 右端的快照用于本线，保留自身出手伤害。
		if not is_instance_valid(left) or not is_instance_valid(right) or left.is_queued_for_deletion() \
				or right.is_queued_for_deletion() or not right.shot.is_active() or get_tree().paused:
			continue
		var shot: ElectricPeaShotContext = right.shot # 同组必须仍属于同一原战局。
		var start: Vector2 = left.global_position # 左端的实际世界位置。
		var finish: Vector2 = right.global_position # 右端的实际世界位置。
		var direction: Vector2 = finish - start # 根据实际世界段设置探针尺寸与角度。
		if direction.length_squared() <= 0.000001:
			continue
		var probe_size := Vector2(direction.length(), WIDTH) # 矩形探针仍以线段中心为原点。
		var transform := Transform2D(direction.angle(), start.lerp(finish, 0.5)) # 矩形探针覆盖实际电弧。
		var bounds: Rect2 = transform * Rect2(-probe_size * 0.5, probe_size) # 与探针的局部矩形一致，无需先更新资源。
		if candidates.outside(bounds):
			continue
		var probe_ready: bool = false # 粗筛命中时才更新物理形状。
		var epoch: int = candidates.epoch # 命中回调执行后重新读取剩余角色的几何。
		for candidate_index: int in range(enemy_count): # 命中后仍按原候选顺序继续。
			if contacted[candidate_index]:
				continue
			var world: Rect2 = enemy_bounds[candidate_index] if sample_epochs[candidate_index] == epoch \
				else candidates.refresh(candidate_index) # 远处候选只比较数值。
			if world.size.x >= 0.0 and not bounds.intersects(world, true):
				continue
			if not probe_ready:
				_probe.size = probe_size
				probe_ready = true
			var contact: FieldContact = _try_strike(candidates, candidate_index, contacted, shot, scope, transform, bounds) # 未知回调使当前区间失效。
			if contact != FieldContact.MISS:
				if contact == FieldContact.REFRESH:
					candidates.invalidate()
					epoch = candidates.epoch
				remaining -= 1
				if remaining == 0:
					return


## 用 [param shot] 的线段探针 [param transform]、[param bounds] 确认 [param candidates] 中的 [param index]。
## [param contacted] 与 [param scope] 保持原接触及承伤去重；返回接触结果和几何失效边界。
func _try_strike(candidates: FieldCandidates, index: int, contacted: PackedByteArray,
		shot: ElectricPeaShotContext, scope: CombatHitScope, transform: Transform2D, bounds: Rect2) -> FieldContact:
	var reference: Variant = candidates.targets[index] # 尚未接触的角色仍需即时核对资格。
	if not is_instance_valid(reference) or not ElectricPeaFlightQuery.can_hit(reference):
		return FieldContact.MISS
	var target: Character000Base = reference # 存活且在当前战斗中。
	var area: Area2D = target.hurt_box_component.hurt_box_real # 精确阶段读取当前启用状态。
	var shape: Shape2D = candidates.shapes[index] # 单形状的资源与变换已在粗筛阶段同步读取。
	if shape != null:
		if area.is_shape_owner_disabled(candidates.owner_ids[index]) \
				or not _probe.collide(transform, shape, candidates.transforms[index]):
			return FieldContact.MISS
	elif not _intersects(area, transform, bounds):
		return FieldContact.MISS
	contacted[index] = 1
	return FieldContact.REFRESH if shot.hit_field(target, scope, candidates.audit, index) else FieldContact.STABLE


## 确认 [param area] 的某个启用受击形状与 [param transform]、[param bounds] 定位的弧线探针相交。
func _intersects(area: Area2D, transform: Transform2D, bounds: Rect2) -> bool:
	if not is_instance_valid(area):
		return false
	for owner_id: int in area.get_shape_owners(): # 兼容具有多个真实受击盒的僵王。
		if area.is_shape_owner_disabled(owner_id):
			continue
		var target_transform: Transform2D = area.global_transform * area.shape_owner_get_transform(owner_id) # 形状所在的真实世界变换。
		for index: int in range(area.shape_owner_get_shape_count(owner_id)): # 同一受击区内逐形状确认。
			var shape: Shape2D = area.shape_owner_get_shape(owner_id, index) # 受击盒资源，可能为非矩形。
			if shape != null and bounds.intersects(target_transform * shape.get_rect(), true) \
					and _probe.collide(transform, shape, target_transform):
				return true
	return false


## 按 [param a] 与 [param b] 的世界横坐标、纵坐标及实例ID依次排序。
static func _position_less(a: ElectricPeaProjectile, b: ElectricPeaProjectile) -> bool:
	var first: Vector2 = a.global_position # 左项本次比较时的世界端点。
	var second: Vector2 = b.global_position # 右项本次比较时的世界端点。
	if first.x != second.x:
		return first.x < second.x
	if first.y == second.y:
		return a.get_instance_id() < b.get_instance_id()
	return first.y < second.y


## 按出手等阶批绘准确的连续主线，并在固定预算内添加小幅流动电光。
func _draw() -> void:
	_main_beams.update_lines(_lines, _line_ranks)
	if _lines.is_empty():
		return
	_strokes.clear()
	for index: int in range(mini(_line_ranks.size(), DECORATION_BUDGET)): # 超出预算只省略装饰，所有真实线与结算仍保留。
		_draw_current(_lines[index * 2], _lines[index * 2 + 1], _line_seeds[index],
			_colors[_line_ranks[index]])
	_strokes.submit(self)


## 在 [param start] 至 [param finish] 的真实直线上绘制短电流前沿。
## [param seed] 固定各连线错开的节奏，[param colors] 为出手三色；侧偏不足一像素，不冒充额外碰撞宽度。
func _draw_current(start: Vector2, finish: Vector2, seed: int, colors: Dictionary) -> void:
	var direction: Vector2 = finish - start # 主判定始终是未偏移的两点直线。
	var length: float = direction.length() # 过短的连线只保留准确主线。
	if length < 8.0:
		return
	var clock: float = _visual_time + ArcVisual.noise(seed, 1) * 0.54 # 每条线错开脉冲，避免整片矩阵同步频闪。
	var cycle: int = floori(clock / 0.54) # 每半秒只换一次固定细碎形态。
	var phase: float = fposmod(clock, 0.54) / 0.54 # 一个电流包由前端滑到后端。
	var energy: float = sin(phase * PI) * 0.76 # 在每轮首尾完全淡出后才切换形态。
	var span: float = minf(0.30, 28.0 / length) # 亮包只占短段，长连线也不出现大片光带。
	var head: float = lerpf(span, 1.0, phase) # 亮包的前端始终停在真实端点以内。
	var tail: Vector2 = start.lerp(finish, head - span) # 短包开始处精确贴合主线。
	var tip: Vector2 = start.lerp(finish, head) # 短包结束处精确贴合主线。
	var path: PackedVector2Array = ArcVisual.make_path(tail, tip, seed + cycle * 71, 0.85, 5.5, 7) # 最多七段且偏移小于真实半宽。
	_strokes.add_strand(path, colors, energy, 0.85)
	if phase > 0.25 and phase < 0.63:
		var root: Vector2 = path[path.size() / 2] # 短枝从当前电流包中段发出。
		var side: float = -1.0 if seed % 2 == 0 else 1.0 # 由线身份决定朝向，保持稳定。
		var spur := PackedVector2Array([root, root + direction.normalized() * 1.7 + direction.normalized().orthogonal() * side * 2.2,
			root + direction.normalized() * 4.0 + direction.normalized().orthogonal() * side * 3.8]) # 仅一根不超过四像素侧偏的小枝。
		_strokes.add_polyline(spur, Color(colors.rim, energy * 0.16), 1.6)
		_strokes.add_polyline(spur, Color(colors.core, energy * 0.36), 0.65)
