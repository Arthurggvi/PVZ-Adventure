## 「呼啸」的雪暴。雪弹共享按行的碰撞缓存，雪墙及雪弹各按行合批绘制。
extends Node2D

## 默认抽取的攻击行数，供一阶段使用。
const LANE_LIMIT: int = 2
## 默认每路弹数，和 [constant DAMAGE] 一起给出一阶段每路 1200 点伤害预算。
const SHOTS_PER_LANE: int = 120
## 每枚雪弹首次撞到植物时提交的普通伤害。
const DAMAGE: int = 10
## 沿世界 X 轴向左推进的速度，单位为像素每秒。
const SPEED: float = 1260.0
## 施法白闪先抬亮，随后雪墙从右侧进入。
const LEAD: float = 0.14
## 相邻两路雪墙的起势间隔，单位为秒。
const LANE_STAGGER: float = 0.11
## 每路全部雪弹的发射窗口，单位为秒。
const RELEASE: float = 1.27
## 每路最多同时绘制的撞击雪屑团数。
const IMPACT_CAPACITY: int = 8
## 连续雪弹命中时每路的雪屑绘制间隔，单位为秒。
const IMPACT_GAP: float = 0.044
## 每团雪屑的消散时间，单位为秒。
const IMPACT_LIFE: float = 0.30
## 雪雾带相对脚点的顶部及底部偏移，单位为世界像素。
const MIST_Y := Vector2(-72.0, 25.0)
## 雪墙的翻卷、雪粉与细雪线共用一条贴坡网格。
const MIST_SHADER: Shader = preload("res://shaders/adventure/cailleach_howl_mist.gdshader")
## 雪弹及撞击雪屑共用一个批次的材质。
const SHOT_SHADER: Shader = preload("res://shaders/adventure/cailleach_howl_shots.gdshader")

## 独立一路的坡面、发射序列和绘制实例。
class Lane:
	## 本行有效种植点，实体随物理步重新读取。
	var cells: Array[PlantCell]
	## 由右往左的地面折点，相邻两点间线性插值。
	var path: Array[Vector2]
	## 装填时间、相对脚点的高度、雪弹外形种子。
	var shots := PackedVector3Array()
	## 每弹已到达的坡面段，下标为 -1 表示已命中或离场。
	var segments := PackedInt32Array()
	## 第一枚尚未进入物理处理的弹。
	var next_shot: int = 0
	## 跳过已经全部结算的头部弹区间。
	var first_live: int = 0
	## 这路雪墙的起始时间，供推进气流和发射采样。
	var begins: float
	## 当前雪弹实际抵达的最左世界 X，让雪雾与雪弹共用推进边界。
	var reach_x: float
	## 上个物理步的推进边界，供雪墙插值。
	var previous_reach_x: float
	## 同一物理步内复用的活株与其实际受击区的粗筛包围盒。
	var targets: Array[Plant000Base] = []
	## 和 [member targets] 一一对应的世界矩形。
	var bounds: Array[Rect2] = []
	## 同步去掉同一株植物的多格登记。
	var seen: Dictionary[Plant000Base, bool] = {}
	## 两维位置和出现时间，负时间表示未使用。
	var impacts := PackedVector3Array()
	## 本路可以画下一团撞击雪屑的时刻。
	var next_impact: float = 0.0
	## 最近一次使用的雪屑位。
	var impact_slot: int = 0
	## 本行雾墙的时间参数只需下发一次。
	var mist: ShaderMaterial
	## 本行可见弹头、拖尾与接触雪屑合用同一批次。
	var batch: MultiMesh

## 施放时的战场、轮次及棋盘身份。
var _battle: RepeaterShotContext
## 玩家退出战斗或施法来源失效后拒绝结算在途雪弹。
var _source_active: Callable
## 雪弹命中植物时共用的真实伤害归因。
var _plant_hit: CombatHitScope
## 本轮选路和外观使用同一独立随机流。
var _rng := RandomNumberGenerator.new()
## 本次最多选择的不同攻击行数。
var _lane_limit: int
## 本次选择的每路真实弹数。
var _shots_per_lane: int
## 已选中且有实际种植点的攻击行及其弹道实例。
var _lanes: Array[Lane] = []
## 共享碰撞探针，只做真实植物形状的窄相检测。
var _query := BloomerangFlightQuery.new()
## 上一个物理步的时间，供正常帧率下的视觉插值。
var _previous_age: float = 0.0
## 从技能结算触发时计起的战斗秒数。
var _age: float = 0.0
## 最靠左一路的余雪散尽时间。
var _ends: float = 0.0

## [param battle] 为战场身份，[param seed_value] 复现抽路与发射次序，[param source_active] 核对施法阶段。
## [param lane_limit] 和 [param shots_per_lane] 控制本次路数和每路弹数，任一为非正数时不发动。
## [param plant_hit] 保存雪弹的伤害来源。
func _init(battle: RepeaterShotContext, seed_value: int, source_active: Callable,
		lane_limit: int = LANE_LIMIT, shots_per_lane: int = SHOTS_PER_LANE, plant_hit: CombatHitScope = null) -> void:
	name = "CailleachHowl"
	_battle = battle
	_source_active = source_active
	_plant_hit = plant_hit
	_rng.seed = seed_value
	_lane_limit = lane_limit
	_shots_per_lane = shots_per_lane

## 从仍有合法种植点的行中无放回抽取，按棋盘真实脚点建立坡面。
func _ready() -> void:
	if _lane_limit <= 0 or _shots_per_lane <= 0:
		queue_free()
		return
	top_level = true
	global_transform = Transform2D.IDENTITY # 本节点存放棋盘世界坐标，继承战斗的画布与暂停。
	var eligible: Array[int] = [] # 有合法种植点的行均可被抽中。
	for lane_id: int in range(_battle.board.lanes.size()): # 攻击行按棋盘定义编号。
		if not _battle.board.row_cells(lane_id).is_empty():
			eligible.append(lane_id)
	for order: int in range(mini(_lane_limit, eligible.size())): # 行不足时只生成实际可用的路。
		var lane_id: int = eligible.pop_at(_rng.randi_range(0, eligible.size() - 1)) # 固定这路的战斗编号和渲染排序。
		_lanes.append(_make_lane(lane_id, order))
	if _lanes.is_empty():
		queue_free()

## 为 [param lane_id] 建立从生成标记右侧到最左格外的坡面，[param order] 决定错峰秒数。
func _make_lane(lane_id: int, order: int) -> Lane:
	var lane := Lane.new() # 一路只分配一次存储，飞行中沿用。
	lane.cells = _battle.board.row_cells(lane_id)
	lane.begins = LEAD + LANE_STAGGER * order
	var game: MainGameManager = _battle.game # 与僵尸出生点和屋顶弹道共用世界坐标。
	var slope: MainGameSlope = game.main_game_slope # 平地时为空。
	var foot: Vector2 = lane.cells[0].get_slot_anchor_global_position(CharacterRegistry.PlacePlantInCell.Norm) # 真实普通层脚点。
	var level_y: float = foot.y - BloomerangFlightQuery.height_at(slope, foot.x) # 还原未叠加坡高的行基线。
	var left: float = lane.cells[0].get_global_rect().position.x # 可自定义格序，逐格求横向边界。
	var right: float = game.to_global(_battle.board.lanes[lane_id].spawn_position).x # 保持在最右种植格外起飞。
	for cell: PlantCell in lane.cells: # 扫描本行可能不连续的种植点。
		var rect: Rect2 = cell.get_global_rect() # 左右边由真实棋盘宽度决定。
		left = minf(left, rect.position.x)
		right = maxf(right, rect.end.x + 32.0)
	left -= 50.0
	lane.path = BloomerangFlightQuery.path_points(
		Vector2(right, level_y + BloomerangFlightQuery.height_at(slope, right)),
		Vector2(left, level_y + BloomerangFlightQuery.height_at(slope, left)), slope, level_y)
	lane.reach_x = right
	lane.previous_reach_x = right
	_ends = maxf(_ends, lane.begins + RELEASE + (right - left) / SPEED + IMPACT_LIFE + 0.28)
	lane.shots.resize(_shots_per_lane)
	lane.segments.resize(_shots_per_lane)
	for index: int in range(_shots_per_lane): # 起飞有随机密度起伏，序列仍严格按时间排序。
		var progress: float = (float(index) + _rng.randf()) / _shots_per_lane # 一次分槽取样，维持完整伤害预算。
		var birth: float = lane.begins + RELEASE * (progress + 0.038 * sin(progress * TAU * 3.0)) # 三股疏密起伏，保留严格递增的发射顺序。
		lane.shots[index] = Vector3(birth, _rng.randf_range(-26.0, -10.0), _rng.randf())
	lane.impacts.resize(IMPACT_CAPACITY)
	lane.impacts.fill(Vector3(0.0, 0.0, -1.0))
	_make_visuals(lane, lane_id)
	return lane

## 为 [param lane] 建立两批绘制，按 [param lane_id] 沿用普通弹体的战斗排序。
func _make_visuals(lane: Lane, lane_id: int) -> void:
	var vertices := PackedVector2Array() # 雾墙只在真实坡面折点布置一对顶点。
	var uvs := PackedVector2Array() # U 是沿行从右往左的归一化距离，V 是离地高度比例。
	var indices := PackedInt32Array() # 相邻顶点对之间用两个三角形连接。
	var start_x: float = lane.path[0].x # 世界 X 的飞行原点。
	var span: float = start_x - lane.path.back().x # 从右向左的全长，单位为世界像素。
	for index: int in range(lane.path.size()): # 毛边和弧度交给着色器，坡折点严格贴地。
		var point: Vector2 = lane.path[index] # 由坡面真实高度提供的脚点。
		var u: float = (start_x - point.x) / span # 保证不同坡段采样密度相同。
		vertices.append(point + Vector2(0.0, MIST_Y.x))
		vertices.append(point + Vector2(0.0, MIST_Y.y))
		uvs.append(Vector2(u, 0.0))
		uvs.append(Vector2(u, 1.0))
		if index > 0:
			var edge: int = (index - 1) * 2 # 前一对顶点的起始下标。
			indices.append_array(PackedInt32Array([edge, edge + 1, edge + 2, edge + 2, edge + 1, edge + 3]))
	var arrays: Array = [] # Godot 的二维 mesh 顶点、纹理坐标和索引槽。
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var ribbon := ArrayMesh.new() # 一路雪墙共用一片带状网格。
	ribbon.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	lane.mist = ShaderMaterial.new()
	lane.mist.shader = MIST_SHADER
	lane.mist.set_shader_parameter(&"span", span)
	lane.mist.set_shader_parameter(&"speed", SPEED)
	lane.mist.set_shader_parameter(&"release", RELEASE)
	lane.mist.set_shader_parameter(&"seed", _rng.randf())
	var veil := MeshInstance2D.new() # 位于可见雪弹的下层。
	veil.mesh = ribbon
	veil.material = lane.mist
	veil.z_index = lane_id * 50 + 44
	add_child(veil)
	var quad := QuadMesh.new() # 同一片面支持横向雪弹拖尾和散开的接触雪屑。
	quad.size = Vector2(62.0, 24.0)
	lane.batch = MultiMesh.new()
	lane.batch.transform_format = MultiMesh.TRANSFORM_2D
	lane.batch.use_custom_data = true
	lane.batch.mesh = quad
	lane.batch.instance_count = _shots_per_lane + IMPACT_CAPACITY
	lane.batch.visible_instance_count = 0
	var material := ShaderMaterial.new() # 实例自定义色提供类型和随机差异。
	material.shader = SHOT_SHADER
	var sprites := MultiMeshInstance2D.new() # 合并全部实际在途雪弹及少量撞击雪屑。
	sprites.multimesh = lane.batch
	sprites.material = material
	sprites.z_index = veil.z_index + 1
	add_child(sprites)

## 按 [param delta] 的战斗秒数推进一个物理步，扫掠每枚弹跨过的完整路径。
func _physics_process(delta: float) -> void:
	if not _source_active.is_valid() or not _source_active.call():
		queue_free()
		return
	_previous_age = _age
	_age += delta
	for lane: Lane in _lanes: # 碰撞成本与被选中的攻击行数量相关。
		lane.previous_reach_x = lane.reach_x
		if _age < lane.begins or lane.first_live == _shots_per_lane:
			continue
		while lane.next_shot < _shots_per_lane and lane.shots[lane.next_shot].x <= _age:
			lane.next_shot += 1
		_collect_targets(lane)
		for index: int in range(lane.first_live, lane.next_shot): # 按发射先后推进，前一弹可以先移除阻挡株。
			if lane.segments[index] >= 0:
				_advance_shot(lane, index)
		while lane.first_live < lane.next_shot and lane.segments[lane.first_live] < 0:
			lane.first_live += 1
	if _age >= _ends:
		queue_free()

## 每步只为 [param lane] 的真实受击区构造一次粗筛数据，可响应种植、铲除和快照后的死亡。
func _collect_targets(lane: Lane) -> void:
	lane.targets.clear()
	lane.bounds.clear()
	lane.seen.clear()
	for cell: PlantCell in lane.cells: # 收集实际植物，不向坡面碰撞体提交查询。
		if not is_instance_valid(cell) or cell.is_queued_for_deletion():
			continue
		for plant: Plant000Base in cell.living_plants(): # 包含底座、外壳和不占位伴生。
			if lane.seen.has(plant) or not is_instance_valid(plant.hurt_box_component) or not plant.hurt_box_component.is_enabling:
				continue
			lane.seen[plant] = true
			var area: Area2D = plant.hurt_box_component.hurt_box_real # 使用已经叠加地形及承托偏移的受击形状。
			if not is_instance_valid(area) or area.is_queued_for_deletion():
				continue
			var bounds := Rect2() # 合并启用形状的世界矩形，只作粗筛。
			for owner_id: int in area.get_shape_owners(): # 多形状植物仍只保存一次候选。
				if area.is_shape_owner_disabled(owner_id):
					continue
				var pose: Transform2D = area.global_transform * area.shape_owner_get_transform(owner_id) # 计入形状自身偏移。
				for shape_index: int in range(area.shape_owner_get_shape_count(owner_id)): # 包含形状的真实尺寸和缩放。
					var shape: Shape2D = area.shape_owner_get_shape(owner_id, shape_index) # 读取形状资源，无需请求物理空间候选。
					if shape != null:
						var extent: Rect2 = pose * shape.get_rect() # 世界空间的保守边界。
						bounds = bounds.merge(extent) if bounds.has_area() else extent
			if bounds.has_area():
				lane.targets.append(plant)
				lane.bounds.append(bounds)

## [param lane] 的第 [param index] 枚弹逐段穿过坡折，命中或离开整行后立即回收。
func _advance_shot(lane: Lane, index: int) -> void:
	var shot: Vector3 = lane.shots[index] # X 为装填时间，Y 为相对地面高度。
	var from_x: float = lane.path[0].x - SPEED * maxf(0.0, _previous_age - shot.x) # 首帧只扫已经出膛的距离。
	var to_x: float = maxf(lane.path.back().x, lane.path[0].x - SPEED * (_age - shot.x)) # 末帧止于棋盘外缘。
	var section: int = lane.segments[index] # 已经越过的线段无需再次进入。
	while section < lane.path.size() - 1:
		var edge: float = lane.path[section + 1].x # 当前直线段的左端折点。
		var stop_x: float = maxf(to_x, edge) # 即使一帧跨越多个坡面也按顺序扫掠。
		if not lane.bounds.is_empty() and _strike(lane,
				_point(lane, section, from_x, shot.y), _point(lane, section, stop_x, shot.y)):
			lane.segments[index] = -1
			return
		if to_x > edge:
			break
		section += 1
		from_x = stop_x
	lane.reach_x = minf(lane.reach_x, to_x)
	lane.segments[index] = section if section < lane.path.size() - 1 else -1

## 找到 [param lane] 上 [param start] 至 [param finish] 的首次精确接触，有命中就消耗本枚雪弹。
func _strike(lane: Lane, start: Vector2, finish: Vector2) -> bool:
	var reach := Rect2(start.min(finish), (finish - start).abs()).grow(BloomerangFlightQuery.HALF_SIZE + 0.01) # 方形探针扫掠包围盒。
	var first: float = INF # 线段上的第一次真实接触比例。
	var hit: Plant000Base # 通过矩形筛选后，按受击形状的位置比较先后。
	for index: int in range(lane.bounds.size()): # 正常飞行阶段主要是便宜的矩形比较。
		if not reach.intersects(lane.bounds[index], true):
			continue
		var plant: Plant000Base = lane.targets[index] # 前一发可能已杀死或移除此株。
		if not is_instance_valid(plant) or plant.is_death or plant.is_queued_for_deletion() or not plant.hurt_box_component.is_enabling:
			continue
		var contact: float = _query.area_fraction(plant.hurt_box_component.hurt_box_real, start, finish) # 排除形状角落的假命中。
		if contact < first:
			first = contact
			hit = plant
	if hit == null or not _source_active.call():
		return false
	var target: Plant000Base = BulletLinear000Base.first_plant_in_cell(hit) # 沿用南瓜等同格保护层。
	if target == null:
		target = hit
	var point: Vector2 = start.lerp(finish, first) # 将雪墙前缘和撞击雪屑止于真实命中位置。
	lane.reach_x = minf(lane.reach_x, point.x)
	target.be_attacked_bullet(DAMAGE, BulletRegistry.AttackMode.Norm, true, false, 0, -1, null, _plant_hit)
	if _age >= lane.next_impact:
		lane.impacts[lane.impact_slot] = Vector3(point.x, point.y, _age)
		lane.impact_slot = (lane.impact_slot + 1) % IMPACT_CAPACITY
		lane.next_impact = _age + IMPACT_GAP
	return true

## 取 [param lane] 的 [param section] 段中横坐标 [param x] 处的地面，加上弹道高度 [param height]。
static func _point(lane: Lane, section: int, x: float, height: float) -> Vector2:
	var right: Vector2 = lane.path[section] # 当前地面段的高 X 端。
	var left: Vector2 = lane.path[section + 1] # 当前地面段的低 X 端。
	return Vector2(x, lerpf(right.y, left.y, (right.x - x) / (right.x - left.x)) + height)

## 渲染仅上传当前可见实例，[param _delta] 不推进物理时钟。
func _process(_delta: float) -> void:
	var interpolation: float = Engine.get_physics_interpolation_fraction() # 雪墙前缘和弹道在同一时刻采样。
	var paint_age: float = lerpf(_previous_age, _age, interpolation) # 使低物理帧率下的雪弹平滑移动。
	for lane: Lane in _lanes: # 每路只更新一个雪墙时钟及一个可见实例范围。
		lane.mist.set_shader_parameter(&"age", paint_age - lane.begins)
		lane.mist.set_shader_parameter(&"reach", lane.path[0].x - lerpf(lane.previous_reach_x, lane.reach_x, interpolation))
		var visible_count: int = 0 # 可见弹头和碰撞雪屑紧密排在批次最前面。
		for index: int in range(lane.first_live, lane.next_shot): # 跳过已出界或撞碎的雪弹。
			var section: int = lane.segments[index] # 这一物理步末的坡段。
			var shot: Vector3 = lane.shots[index] # 出生时间、高度和外观种子。
			if section < 0 or paint_age < shot.x:
				continue
			var x: float = lane.path[0].x - SPEED * (paint_age - shot.x) # 使用和碰撞同一条世界路径。
			while section > 0 and x > lane.path[section].x:
				section -= 1
			var direction: Vector2 = (lane.path[section] - lane.path[section + 1]).normalized() # 纹理尾部指向右侧来路。
			var point: Vector2 = _point(lane, section, x, shot.y) + direction * 15.0 # 将片面左侧的亮弹头对齐探针。
			lane.batch.set_instance_transform_2d(visible_count, Transform2D(direction.angle(), point))
			lane.batch.set_instance_custom_data(visible_count, Color(0.0, shot.z, 0.0, 1.0))
			visible_count += 1
		for index: int in range(IMPACT_CAPACITY): # 固定容量的撞击雪屑与现有雪弹共用材质。
			var impact: Vector3 = lane.impacts[index] # XY 是接触位置，Z 是开始时间。
			var life: float = (paint_age - impact.z) / IMPACT_LIFE # 标准化生命周期供着色器散开。
			if impact.z < 0.0 or life < 0.0 or life >= 1.0:
				continue
			lane.batch.set_instance_transform_2d(visible_count, Transform2D(
				0.0, Vector2(1.25, 1.45), 0.0, Vector2(impact.x + 15.0, impact.y - life * 6.0)))
			lane.batch.set_instance_custom_data(visible_count, Color(1.0, float(index) / IMPACT_CAPACITY, life, 1.0))
			visible_count += 1
		lane.batch.visible_instance_count = visible_count
