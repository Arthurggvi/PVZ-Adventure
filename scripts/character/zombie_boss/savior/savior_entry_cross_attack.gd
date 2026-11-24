## 救主入场十字的物理轨迹与命中。表现从同一个 Cross 读取着地位置。
extends RefCounted

## 第一次创建轨迹时通知表现分配四束光。
signal cross_started(cross: Cross)
## 角色消失或本轮结束，归还对应表现。
signal cross_ended(cross: Cross)
## 同一批四向柱共同触地，只震动、播放一次。
signal landed(caster_count: int)
## 中断时收回仍在播放的触地音。
signal interrupted

## 四束柱光的世界方向。首束也负责显示原始触地的冲击纹。
const DIRECTIONS: Array[Vector2] = [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]
## 常规入场一位，噩梦合演至多三位。
const MAX_CASTERS := 3
## 柱尖从高处下落至脚点的战斗秒数。
const LAND_SECONDS := 0.32
## 触地后在四个方向向外扫过棋盘的战斗秒数。
const SWEEP_SECONDS := 1.10
## 柱尖离地后到红光消失的战斗秒数。
const RELEASE_SECONDS := 0.36
## 每名救主的十字对每株植物提交一次基础伤害。
const DAMAGE := 100
## 命中后的永久劣化比例，沿用已有的取最强值通道。
const DEGRADATION := 0.30

## 一名施法者的轨迹与去重状态。points 始终保存最后一个物理步的真实位置。
class Cross:
	## 正式出战的施法者，死亡时回收这一组柱。
	var caster: ZB000Base
	## 施法者真实脚点，落地那一刻冻结为四道轨迹的原点。
	var origin: Vector2
	## 按邻近地块跨度确定接触半径，单位为世界像素。
	var radius: float
	## 每道柱从脚点走到对应棋盘边缘以外的距离。
	var travel := PackedFloat32Array()
	## 物理步提交的柱底世界位置，下一步据此进行连续接触。
	var points := PackedVector2Array()
	## 同一株植物无论占格数或经过的柱数，在此十字内只命中一次。
	var hit_ids: Dictionary[int, bool] = {}

## 用当前棋盘格和植物层结算十字。
var _board: BoardRuntime
## 本轮棋盘的世界范围，用来决定四个方向的终点。
var _floor: Rect2
## 本轮每位真实救主的独立十字。
var _crosses: Array[Cross] = []
## 小于零时为休眠态。其他值为物理轨迹已推进的战斗秒数。
var _elapsed := -1.0
## 大帧跨过触地时保留余量，下一帧接着横扫。
var _carry := 0.0

## 渲染以此战斗年龄采样材质参数，不独立计时。
var age: float:
	get:
		return _elapsed

## [param board] 提供真实格距、地块及实时种植状态。
func configure(board: BoardRuntime) -> void:
	_board = board

## 让 [param casters] 中至多三位出战救主同步下落。重复实体与已离场实体不会增加一组柱。
## 上一轮尚未结束时只替换本入场演出自己的柱体、照明和音效。
func begin(casters: Array[ZB000Base]) -> void:
	clear()
	_floor = BoardQueries.bounds(_board.cells())
	if not _floor.has_area():
		return
	var seen: Dictionary[int, bool] = {} # 防止重复登记同一个施法者。
	for caster: ZB000Base in casters: # 坐标从真实出战节点读取。
		if _crosses.size() >= MAX_CASTERS:
			break
		if not _caster_is_present(caster) or seen.has(caster.get_instance_id()):
			continue
		seen[caster.get_instance_id()] = true
		var cross := Cross.new() # 四道柱体和命中记录均在本组独立维护。
		cross.caster = caster
		var foot: Vector2 = caster.shadow.global_position # 与教堂现有的身体投影使用相同地面垂足。
		var nearest: PlantCell = BoardQueries.nearest(_board, foot) # 兼容棋盘右沿和场内出场。
		if nearest == null:
			continue
		var size: Vector2 = nearest.get_global_rect().size # 当前关卡的真实地面格距。
		cross.radius = maxf(size.x, size.y) * 0.64
		_move_origin(cross, foot)
		_crosses.append(cross)
		cross_started.emit(cross)
	if not _crosses.is_empty():
		_elapsed = 0.0

## 返回本轮是否仍有活动柱体，用于衔接关卡演出。
func is_running() -> bool:
	return _elapsed >= 0.0

## 在一次未暂停物理步中推进 [param delta] 战斗秒，并以连续线段结算跨步命中。
func advance(delta: float) -> void:
	if not is_running():
		return
	var previous_age: float = _elapsed # 判断本帧是否首次触地或覆盖最后一段扫掠。
	var sweep_end: float = LAND_SECONDS + SWEEP_SECONDS # 到达末端后停止新的接触。
	var end: float = sweep_end + RELEASE_SECONDS # 灯光与柱身同时结束其生命周期。
	var next: float = minf(_elapsed + delta + _carry, end) # 合并触地帧留下的未消费时间。
	_carry = 0.0
	for cross: Cross in _crosses.duplicate(): # 施法者退场只移除这一组。
		if not _caster_is_present(cross.caster):
			_crosses.erase(cross)
			cross_ended.emit(cross)
		elif previous_age < LAND_SECONDS and cross.origin != cross.caster.shadow.global_position:
			_move_origin(cross, cross.caster.shadow.global_position)
	if _crosses.is_empty():
		clear()
		return
	if previous_age < LAND_SECONDS and next >= LAND_SECONDS:
		_carry = next - LAND_SECONDS
		next = LAND_SECONDS
		landed.emit(_crosses.size())
	_elapsed = next
	var since_impact: float = _elapsed - LAND_SECONDS # 材质、横扫位置与接触音效共用此时间。
	var progress: float = smoothstep(0.0, SWEEP_SECONDS, since_impact) # 柱底从脚点加速，靠近棋盘边缘时减速。
	var cells: Array[PlantCell] = [] # 仅在可命中阶段读取本帧的实际棋盘。
	if since_impact >= 0.0 and previous_age < sweep_end:
		cells = _board.cells()
	for cross: Cross in _crosses.duplicate(): # 植物亡语可能同步结束整场战斗。
		if not _crosses.has(cross):
			return
		if not _caster_is_present(cross.caster):
			continue
		var points := PackedVector2Array() # 同一组柱底供渲染和连续判定使用。
		for index: int in range(DIRECTIONS.size()): # 各方向保持垂直或水平，不从世界坐标斜切。
			points.append(cross.origin + DIRECTIONS[index] * cross.travel[index] * progress)
		if not cells.is_empty():
			_sweep_plants(cross, points, cells)
		cross.points = points
	if _elapsed >= end:
		_release_all()

## 中断本轮并撤销所有活动十字，重复执行只会让声音保持停止。
func clear() -> void:
	_release_all()
	interrupted.emit()

## 返回 [param caster] 是否还有实际且有效的脚点。
func _caster_is_present(caster: ZB000Base) -> bool:
	return is_instance_valid(caster) and caster.is_inside_tree() and not caster.is_death \
		and not caster.is_queued_for_deletion() and is_instance_valid(caster.shadow)

## 将未触地的 [param cross] 贴回 [param foot]，并分别求四个方向的有效行程。
func _move_origin(cross: Cross, foot: Vector2) -> void:
	cross.origin = foot
	var exit_margin: float = cross.radius * 1.55 # 完整扫过边缘足底后，给柱尖留出退场空间。
	cross.travel = PackedFloat32Array([foot.x - _floor.position.x, _floor.end.x - foot.x,
		foot.y - _floor.position.y, _floor.end.y - foot.y])
	for index: int in range(DIRECTIONS.size()): # 施法者在棋盘边缘时，向外仍能拉开一段柱距。
		cross.travel[index] = maxf(0.0, cross.travel[index]) + exit_margin
	cross.points.resize(DIRECTIONS.size())
	cross.points.fill(foot)

## 让 [param cross] 从上一帧扫到 [param points]。只结算 [param cells] 中当前实际存活的植物层。
func _sweep_plants(cross: Cross, points: PackedVector2Array, cells: Array[PlantCell]) -> void:
	var radius_squared: float = cross.radius * cross.radius # 连续接触只比较平方距离。
	for cell: PlantCell in cells: # 从棋盘的真实占位枚举常规层、承托层和伴生层。
		if not is_instance_valid(cell) or cell.is_queued_for_deletion():
			continue
		for plant: Plant000Base in cell.living_plants(): # 每次扣血可能改变同格另一株的存活状态。
			if not is_instance_valid(plant) or plant.is_death or plant.is_queued_for_deletion():
				continue
			var id: int = plant.get_instance_id() # 同一实例跨方向、跨帧与跨格共享一次命中。
			if cross.hit_ids.has(id) or not is_instance_valid(plant.shadow):
				continue
			var foot: Vector2 = plant.shadow.global_position # 支撑物偏移后的实际足底。
			if plant.plant_cell != cell and is_instance_valid(plant.plant_cell):
				foot += cell.get_global_rect().get_center() - plant.plant_cell.get_global_rect().get_center()
			for index: int in range(points.size()): # 四道轴对齐的扫掠段包含两帧之间的所有位置。
				var start: Vector2 = cross.points[index] # 第一落地帧的起点也是原始脚点。
				var closest: Vector2 = foot.clamp(start.min(points[index]), start.max(points[index])) # 轴对齐线段上的最近点。
				if foot.distance_squared_to(closest) > radius_squared:
					continue
				cross.hit_ids[id] = true
				plant.be_hit_from(DAMAGE, cross.caster, BulletRegistry.AttackMode.Real, false)
				if not _crosses.has(cross) or not _caster_is_present(cross.caster):
					return
				AdventurePlantNegativeEffects.apply(plant, AdventurePlantNegativeEffects.Kind.DEGRADATION, 0, DEGRADATION)
				break

## 自然结束只撤销轨迹，触地声音可播完尾音。
func _release_all() -> void:
	_elapsed = -1.0
	_carry = 0.0
	for cross: Cross in _crosses: # 逐位归还与该轨迹绑定的表现。
		cross_ended.emit(cross)
	_crosses.clear()
