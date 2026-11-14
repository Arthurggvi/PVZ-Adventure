## 酷刑全场唯一的低频采样时钟。路径按棋盘内固定小段去重，接触按每个僵尸合并。
extends Node2D
class_name SnowPeaIceTrail

## 战场子节点名；同一战场只创建一个控制器。
const RUNTIME_NAME: StringName = &"SnowPeaIceTrail"
## 路径采样间隔，单位为有效战斗秒。
const TICK: float = 0.125
## 每个僵尸最多每八次采样接受一次冰痕词条。
const CONTACT_TICKS: int = 8
## 每格划分的横向冰痕小段数。
const BINS_PER_CELL: int = 4
## 每次采样最多插值的路径点，限制非常规远距离传送消耗。
const MAX_SAMPLES: int = 16
## 每个僵尸持有一个活动路径；重复命中更新后续新段的词条。
class Track:
	## 负责未来新路径段的来源。
	var shot: SnowPeaShot
	## 最近记录的地面世界坐标。
	var previous: Vector2
	## 记录时的攻击行，改变行时在新行重新开始采样。
	var lane: int

## 独立期限与来源的地面小段。
class Segment:
	## 已存在的小段不叠加，新命中可续时并替换词条来源。
	var shot: SnowPeaShot
	## 当前小段到期的节拍。
	var until: int
	## 地块弱引用；不延长已被移除地块的寿命。
	var cell: WeakRef
	## 以地块局部比例记录，移动平台随当前几何绘制。
	var local_point: Vector2

## 运行时当前的战局身份；清空后接受同场下一轮。
var _battle: RepeaterShotContext
## 按僵尸 ID 跟踪移动，同一目标的并发命中合并。
var _tracks: Dictionary[int, Track] = {}
## 僵尸接触许可，以自身实例 ID 按整秒限制所有重叠痕迹。
var _last_contact: Dictionary[int, int] = {}
## 活跃小段按地块实例及横向槽唯一，密度上限为每格四段。
var _segments: Dictionary[int, Segment] = {}
## 下个采样前积累的有效秒数。
var _accumulator: float = 0.0
## 当前战斗采样节拍，只由本运行时推进。
var _step: int = 0

## 记录 [param target] 在 [param shot] 有效战局内的路径。
## 入口从弹体命中延迟提交，避免在物理冲刷中添加战场节点。
static func track(target: Zombie000Base, shot: SnowPeaShot) -> void:
	if not is_instance_valid(target) or target.is_death or target.is_hypno \
			or target.is_queued_for_deletion() or not shot.battle.is_active() \
			or not shot.battle.game.is_ancestor_of(target):
		return
	var game: MainGameManager = shot.battle.game # 运行时按战场挂载和回收。
	var runtime := game.get_node_or_null(NodePath(RUNTIME_NAME)) as SnowPeaIceTrail # 每场景只使用一个采样器。
	if runtime == null:
		runtime = SnowPeaIceTrail.new()
		runtime.name = RUNTIME_NAME
		runtime.z_index = 3
		game.add_child(runtime)
	if runtime._battle != null and not runtime._battle.is_same_battle():
		runtime._clear()
	runtime._battle = shot.battle
	runtime._register(target, shot)

## 为 [param target] 保存本次 [param shot]，若已有轨迹则保留上次坐标。
func _register(target: Zombie000Base, shot: SnowPeaShot) -> void:
	var id: int = target.get_instance_id() # 不强持有僵尸，死亡离场后及时停止跟踪。
	var path: Track = _tracks.get(id) # 合并同一僵尸的同时首击。
	if path == null:
		path = Track.new()
		path.previous = target.global_position
		path.lane = target.lane
		_tracks[id] = path
	path.shot = shot
	_mark(target.global_position, target.lane, shot)
	set_physics_process(true)

## 返回 [param shot] 的书目时长换算出的采样节拍数。
func _duration(shot: SnowPeaShot) -> int:
	return maxi(1, ceili(shot.loadout.number(&"torment", &"seconds") / TICK))

## [param delta] 只推进活动战斗；场景树暂停时没有采样或伤害。
func _physics_process(delta: float) -> void:
	if _battle == null or not _battle.is_active():
		_clear()
		return
	_accumulator += delta
	if _accumulator < TICK:
		return
	var elapsed: int = floori(_accumulator / TICK) # 慢帧推进期限，但不积攒额外接触脉冲。
	_accumulator -= elapsed * TICK
	_step += elapsed
	_sample_tracks()
	_sample_contacts()
	queue_redraw()
	if _tracks.is_empty() and _segments.is_empty() and _last_contact.is_empty():
		set_physics_process(false)

## 跟踪存活目标走过的线段；跨行从新行起点采样，避免连出斜线。
func _sample_tracks() -> void:
	for id: int in _tracks.keys(): # 使用键快照安全移除失效跟踪。
		var target := instance_from_id(id) as Zombie000Base # 弱身份在此重新确认。
		var path: Track = _tracks[id] # 当前目标的唯一路径状态。
		if not is_instance_valid(target) or target.is_death or target.is_hypno \
				or target.is_queued_for_deletion() or not target.is_inside_tree() \
				or not _battle.game.is_ancestor_of(target):
			_tracks.erase(id)
			continue
		var current: Vector2 = target.global_position # 原生根节点是地面脚点。
		if path.lane != target.lane:
			path.previous = current
			path.lane = target.lane
			_mark(current, path.lane, path.shot)
		if current == path.previous:
			continue
		var resolution: float = maxf(4.0, path.shot.battle.cell_pitch.x / (BINS_PER_CELL * 2.0)) # 每段走过多个槽也能补齐。
		var count: int = clampi(ceili(path.previous.distance_to(current) / resolution), 1, MAX_SAMPLES) # 对远距离传送设上限。
		for index: int in range(1, count + 1): # 在扫过的路径上逐段登记。
			_mark(path.previous.lerp(current, float(index) / count), path.lane, path.shot)
		path.previous = current

## 将 [param point] 在 [param lane] 命中的 [param shot] 来源小段登记为五秒冰痕。
func _mark(point: Vector2, lane: int, shot: SnowPeaShot) -> void:
	var cell: PlantCell = _battle.board.cell_at_ground_point(point, lane) # 不把盘外路径吸附到地块。
	if cell == null:
		return
	var key: int = _key(cell, point) # 一个地块横向小段只有一个入口。
	var segment: Segment = _segments.get(key) # 复用已存在的同一空间痕迹。
	if segment == null:
		segment = Segment.new()
		segment.cell = weakref(cell)
		_segments[key] = segment
	segment.shot = shot
	segment.until = _step + _duration(shot)
	segment.local_point = (cell.get_global_transform().affine_inverse() * point) / cell.size
	segment.local_point.x = (posmod(key, BINS_PER_CELL) + 0.5) / BINS_PER_CELL

## 对 [param cell] 的地面 [param point] 计算唯一横向槽位。
func _key(cell: PlantCell, point: Vector2) -> int:
	var x: float = (cell.get_global_transform().affine_inverse() * point).x # 采用平台当前的局部坐标。
	var slot: int = clampi(floori(x / cell.size.x * BINS_PER_CELL), 0, BINS_PER_CELL - 1) # 当前地块内的横向槽。
	return cell.get_instance_id() * BINS_PER_CELL + slot

## 回收失效痕迹，复用波次管理器的活僵尸集合做单次接触扫描。
func _sample_contacts() -> void:
	for key: int in _segments.keys(): # 独立期限不受同一条路径上的其他小段影响。
		if _segments[key].until <= _step or _segments[key].cell.get_ref() == null:
			_segments.erase(key)
	for id: int in _last_contact.keys(): # 接触限频状态最多保留一秒。
		if _last_contact[id] + CONTACT_TICKS <= _step:
			_last_contact.erase(id)
	if _segments.is_empty():
		return
	for zombie: Zombie000Base in _battle.game.zombie_manager.all_zombies_1d: # 当次扫描每个普通僵尸最多一次。
		if not is_instance_valid(zombie) or zombie.is_death or zombie.is_hypno or zombie.is_queued_for_deletion() \
				or _last_contact.has(zombie.get_instance_id()):
			continue
		var point: Vector2 = zombie.global_position # 接触使用地面脚点，不把高空精灵当作地面。
		var cell: PlantCell = _battle.board.cell_at_ground_point(point, zombie.lane) # 稀疏棋盘不跨空洞。
		if cell == null:
			continue
		var segment: Segment = _segments.get(_key(cell, point)) # 空间位置只取唯一有效来源。
		if segment != null and SnowPeaImpact.apply_trail_status(zombie, segment.shot):
			_last_contact[zombie.get_instance_id()] = _step

## 阶段、轮次变化时清空所有路径及限频数据。
func _clear() -> void:
	_battle = null
	_tracks.clear()
	_segments.clear()
	_last_contact.clear()
	_accumulator = 0.0
	_step = 0
	set_physics_process(false)
	queue_redraw()

## 在地面绘制当前痕迹；同一位置最多一条，仅随低频时钟重绘。
func _draw() -> void:
	for segment: Segment in _segments.values(): # 每格最多四个地面碎片。
		var cell := segment.cell.get_ref() as PlantCell # 已移除地块不再绘制。
		if not is_instance_valid(cell) or not cell.is_inside_tree():
			continue
		var center: Vector2 = to_local(cell.get_global_transform() * (segment.local_point * cell.size)) # 当前平台变换。
		var width: float = cell.size.x / BINS_PER_CELL * 0.62 # 接近槽宽的冰屑轮廓。
		draw_line(center - Vector2(width, 0.0) * 0.5, center + Vector2(width, 0.0) * 0.5,
			Color(0.44, 0.82, 1.0, 0.63), 3.0, true)
