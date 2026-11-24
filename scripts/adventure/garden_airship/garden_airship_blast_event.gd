## 一次爆炸的局部部件、不可复用身份和战斗时间轴。它不拥有载具或粒子。
extends Node2D

## 三个时间槽使用战斗秒。轻机在出画前先引爆机头，重机按真实断裂逐次放热。
const TIMES := {
	&"fighter": Vector3(0.115, 0.245, INF),
	&"turret": Vector3(0.145, 0.295, INF),
	&"arbiter": Vector3(0.115, 0.233, 0.346),
	&"transport": Vector3(0.10, 0.22, INF),
}

## 本场导演为事件登记的顺序编号。
var token: int
## 选择热团数量、次爆时刻和声音的机体类别。
var kind: StringName
## 继承载具原美术比例的效果尺寸。
var size: float
## 主爆后经过的战斗秒数。
var age: float = 0.0
## 主爆实际发生的处理帧，避免出生时多消费一个时间步。
var born_frame: int
## 代表声源的真实世界速度，用于承接少量独立燃烧尾迹。
var anchor_velocity := Vector2.ZERO
## 运输舰上层外壳的可发射余火数。
var _embers_left: int = 3
## 上一拍声源及上一束余火的真实世界位置。
var _anchor_previous := Vector2.INF
var _ember_origin := Vector2.INF
## 相对主挂点的下一个次爆编号。
var next_part: int = 0
## 当前代表性残骸声部是否已提交播放。
var tail_active: bool = false
## 移动声部走完或离场后不重新申请。
var tail_done: bool = false
## 主残骸或碎片的对象身份，源节点释放后无需访问它。
var _anchor_id: int = 0
## 代表声源在主残骸局部坐标中的位置。
var _tail_offset := Vector2.ZERO
## 可发射次爆的局部部件点，按事件发生时的姿态恢复。
var points := PackedVector2Array()
## 已独立的部件可以各自拥有姿态。未指定时由快照提供同一姿态。
var _pieces := PackedInt64Array()
## 本帧与上帧实际位置差换算的世界 px/s，保留各片不同的独立动量。
var _velocities := PackedVector2Array()
## 最近一次部件取样世界点。失效时为 INF，不回到死亡起点。
var _positions := PackedVector2Array()
## 主爆发生时从真实运动入口获得的世界 px/s。
var initial_velocity := Vector2.ZERO


## [param anchor] 是已交接的可见机壳。[param local_points] 与 [param pieces] 给出次爆挂点。
## [param tail_offset] 是相对机壳的声源位置。普通机体沿用事先保存的快照局部点。
func bind_pose(anchor: Node2D, local_points: PackedVector2Array, pieces: Array[Node2D],
		tail_offset: Vector2) -> void:
	if not is_instance_valid(anchor) or anchor.is_queued_for_deletion():
		return
	_anchor_id = anchor.get_instance_id()
	_tail_offset = tail_offset
	_anchor_previous = anchor.to_global(tail_offset)
	_ember_origin = _anchor_previous
	anchor_velocity = initial_velocity
	if not local_points.is_empty():
		points = local_points
	_pieces.resize(pieces.size())
	for index: int in pieces.size(): # 片体离开后按本编号取消，而不改用另一个片体。
		var piece: Node2D = pieces[index] # 处理已经被原演出释放的部件。
		_pieces[index] = piece.get_instance_id() if is_instance_valid(piece) else 0
	_positions.resize(points.size())
	_velocities.resize(points.size())
	for index: int in points.size(): # 初始化真实的每点位置和继承速度。
		_positions[index] = _part_position(index)
		_velocities[index] = initial_velocity


## [param delta] 为战斗秒。返回代表声源的当前世界位置或 Vector2.INF。
func sample_pose(delta: float) -> Vector2:
	var anchor: Node2D = _live_node(_anchor_id) # 双向绑定不延长实际残骸的寿命。
	if anchor == null:
		return Vector2.INF
	for index: int in range(next_part, points.size()): # 已经发射的次爆不再跟随。
		var world: Vector2 = _part_position(index) # 世界点包括镜像、部件转动和重挂父系。
		if world.is_finite() and _positions[index].is_finite() and delta > 0.0:
			_velocities[index] = (world - _positions[index]) / delta
		_positions[index] = world
	var world_anchor: Vector2 = anchor.to_global(_tail_offset) # 代表动声和火星共用当前可见片体。
	if _anchor_previous.is_finite() and delta > 0.0:
		anchor_velocity = ((world_anchor - _anchor_previous) / delta).limit_length(3600.0)
	_anchor_previous = world_anchor
	return world_anchor


## 当前 [param world] 实际移出 [param spacing] 世界像素后，允许一束尾部火星。
func take_ember(world: Vector2, spacing: float) -> bool:
	if kind != &"transport" or age > 0.43 or _embers_left <= 0:
		return false
	if world.distance_squared_to(_ember_origin) < spacing * spacing:
		return false
	_ember_origin = world
	_embers_left -= 1
	return true


## 返回下一次部件爆炸在真实世界的位置、继承速度。使用 Vector2.INF 标记失效。
func next_position() -> Vector2:
	return _positions[next_part]


## 返回下一片体的世界移动速度，已限制异常尺寸或重挂带来的跳值。
func next_velocity() -> Vector2:
	return _velocities[next_part].limit_length(3600.0)


## 返回是否已跨过下一部件时间，未绑定或消失的挂点不会发射。
func part_due() -> bool:
	var schedule: Vector3 = TIMES.get(kind, Vector3(INF, INF, INF)) # 火箭小鬼没有次爆。
	return _anchor_id != 0 and next_part < mini(points.size(), 3) and age >= schedule[next_part]


## 用 [param index] 读取该片体或快照所持的本地挂点。
func _part_position(index: int) -> Vector2:
	var id: int = _pieces[index] if index < _pieces.size() else _anchor_id # 单独片体已释放不回退。
	var piece: Node2D = _live_node(id) # 仍在当前画布中的实际绘制节点。
	return piece.to_global(points[index]) if piece != null else Vector2.INF


## 返回 [param id] 仍存续的可见外观，开始释放的节点也不继续取样。
func _live_node(id: int) -> Node2D:
	var anchor := instance_from_id(id) as Node2D if id != 0 else null # 弱身份可在任一帧失效。
	return anchor if is_instance_valid(anchor) and anchor.is_inside_tree() and not anchor.is_queued_for_deletion() else null
