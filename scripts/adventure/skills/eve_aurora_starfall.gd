## 共用的极光星弹。支持伊芙的索敌连发，以及指定落点和命中规则的 Boss 落星。
extends Node2D

## 最后一枚星弹命中或取消后发出一次，地表星空冰继续到自己的消散时刻。
signal impacts_finished

## 起飞与原生 Cut-in 的收幕对齐。
const CutIn = preload("res://scripts/adventure/skills/character_skill_cut_in.gd")
## 银针及窄条飞行表现，战场负责采样。
const Flight = preload("res://scripts/adventure/skills/eve_aurora_flight.gd")
## 触地后沿命中格延展的星空冰、冰雾和碎晶。
const Ice = preload("res://scripts/adventure/skills/eve_star_ice.gd")
## 每发在斜落入场前掠过的递降风声。
const FLIGHT_SOUND: AudioStream = preload("res://assets/adventure/audio/skills/eve_aurora_fall.ogg")
## 同步触地的咔响、冰层延展和晶体余音。
const ICE_SOUND: AudioStream = preload("res://assets/adventure/audio/skills/eve_star_ice_freeze.ogg")
## 每次施放的独立星弹数量。
const SHOT_COUNT := 6
## 六发起飞依次错开的战斗秒数。
const LAUNCH_SPACING := 0.083
## Boss 的错序落星给每发从入场到爆鸣留出更宽的间隔。
const FIXED_LAUNCH_SPACING := 0.196
## 掠风与收幕之间的短间隔，单位为战斗秒。
const FLIGHT_CUE_DELAY := 0.07
## 每次落点的基础伤害，用常规防御路由结算。
const IMPACT_DAMAGE := 200
## 以命中格为中心向两轴各延伸一格。
const RADIUS := 1
## 原生抗火特殊减速的战斗秒数。
const SLOW_SECONDS := 5.0
## 普通敌对僵尸每次实际落点命中后的独立魅惑概率。
const CHARM_CHANCE := 0.50
## 冰从落地到消散的总时长，与减速窗口相当；末段只做透明度演出。
const ICE_SECONDS := 5.0
## 冰缘消散的战斗秒数。
const ICE_FADE := 0.44
## 地表特效覆盖平台底图，低于第一行植株和僵尸。
const GROUND_Z_INDEX := 2
## 空中表现沿用 Bombs 的绝对深度，掠过僵王后仍由原前景及 HUD 遮挡。
const AIR_Z_INDEX := 4001

## 单发同时持有逻辑目的地和两段演出句柄，不从视效回调推导结算。
class Shot:
	## 发射序号，在同时落地时也用于稳定结算排序。
	var index: int
	## 锁定敌人的实例 ID；0 表示沿最后确定的落点继续下落。
	var target_id := 0
	## 飞行中更新的爆心格；触地后随该地块移动。
	var cell: PlantCell
	## 拖尾和冰内主星最终共享的地块局部点。
	var cell_anchor: Vector2
	## 弧线网格烘焙时的起点，使用演出本地坐标。
	var launch_anchor: Vector2
	## 弧线网格烘焙时的目的地；目标和平台运动通过末端偏移反映。
	var landing_anchor: Vector2
	## 专用于折面、侧弯、冰种及音高的种子。
	var visual_seed: int
	## 从起飞批次开始计时的发射时刻。
	var launch_at: float
	## 从起飞批次开始计时的命中时刻。
	var impact_at: float
	## 针尖与薄带直到收尽时释放。
	var flight: Flight
	## 已结算后才生成的地表冰，离场一起回收。
	var ice: Ice
	## 已在发射时检查候选；没有可锁定目标时沿当前落点继续飞行。
	var launched := false
	## 已经经过这发的掠风时刻，避免暂停恢复后重播。
	var flight_cued := false
	## 游戏钟经过命中时刻后置位，演出句柄的可见性不影响结算。
	var impacted := false
	## 地块失效或本发消散结束时停止取样。
	var completed := false

## 伊芙的玩家施放来源。Boss 固定落点时为空，命中由调用者处理。
var _context: CharacterSkillContext
## 供场景、阶段、暂停和原有状态系统共同检查的快照。
var _battle: RepeaterShotContext
## 无目标时的备用落点抽样及后续魅惑使用的随机流。
var _combat_random := RandomNumberGenerator.new()
## 固定落星的命中回调，接收单发覆盖的 3×3 地块。
var _fixed_impact: Callable
## 固定落点可指定逐发起飞时刻，空表沿用常规错峰。
var _fixed_launch_times: PackedFloat32Array
## 正式 Boss 死亡演出提供其等待结算的资格，普通技能留空。
var _fixed_validity: Callable
## 当前施放的两套声音，落星几何不依赖音源。
var _flight_audio: AudioStream
var _impact_audio: AudioStream
## 已按命中时刻排序的星弹记录。
var _shots: Array[Shot] = []
## 从首发起飞计的战斗秒，暂停期间固定。
var _clock := 0.0
## Cut-in 即将收完时允许推进飞行时钟。
var _launched := false
## 战斗倍率改变时正在播放的音轨继续与动作对齐。
var _sound_rate := 1.0
## 完成通知只发布一次，提前卸载也会归还等待者。
var _reported_impacts: bool = false

## [param board] 中的 [param cell] 仍为可见、可定位的同一实际地块时返回 true。
static func is_landing_cell(board: BoardRuntime, cell: PlantCell) -> bool:
	return is_instance_valid(cell) and not cell.is_queued_for_deletion() and cell.is_visible_in_tree() \
		and cell.board == board and board.cell_by_id(cell.cell_id) == cell \
		and cell.size.x > 0.0 and cell.size.y > 0.0

## 保存 [param context]、[param battle] 和随机 [param cast_seed]，为六发分配初始目标。
## 没有可锁定的敌人时，从合法 [param cells] 中优先选取不同的备用格。
## [param context] 为空时，按给定 [param cells] 逐个错序入场，由 [param fixed_impact] 结算实际落点。
## [param flight_audio] 和 [param impact_audio] 可替换掠风与触地音色，留空不播放对应音效。
## [param fixed_launch_times] 为固定落星的逐发游戏秒。[param fixed_validity] 可允许已经接受胜利的死亡演出继续完成。
func _init(context: CharacterSkillContext, battle: RepeaterShotContext,
		cells: Array[PlantCell], cast_seed: int, fixed_impact: Callable = Callable(),
		flight_audio: AudioStream = FLIGHT_SOUND, impact_audio: AudioStream = ICE_SOUND,
		fixed_launch_times: PackedFloat32Array = PackedFloat32Array(), fixed_validity: Callable = Callable()) -> void:
	_context = context
	_battle = battle
	_fixed_impact = fixed_impact
	_fixed_launch_times = fixed_launch_times
	_fixed_validity = fixed_validity
	_flight_audio = flight_audio
	_impact_audio = impact_audio
	_combat_random.seed = cast_seed
	var decorations := RandomNumberGenerator.new() # 视觉采样次数不会影响下一次魅惑判定。
	decorations.seed = cast_seed ^ 0x4BB291CD
	var targets: Dictionary[int, PlantCell] = {} # 仅伊芙索取敌对僵尸。
	if context != null:
		targets = _target_cells()
	var available: Array[PlantCell] = cells.duplicate() # 无目标时优先无放回地覆盖合法位置。
	var count: int = SHOT_COUNT if context != null else cells.size() # Boss 逐格使用已分配的真实落点。
	for index: int in range(count): # 格数不足时仍保留每发独立身份。
		var shot := Shot.new() # 每发持有同一条发射及落地记录。
		shot.index = index
		shot.visual_seed = decorations.randi()
		if context == null:
			shot.cell = cells[index]
			shot.cell_anchor = _surface_anchor(shot.cell)
		elif not _lock_target(shot, targets):
			if not available.is_empty():
				var picked: int = _combat_random.randi_range(0, available.size() - 1) # 未覆盖位置等概率。
				shot.cell = available[picked]
				available.remove_at(picked)
			else:
				shot.cell = cells[_combat_random.randi_range(0, cells.size() - 1)]
			shot.cell_anchor = _surface_anchor(shot.cell)
		_shots.append(shot)

## 读取当前可受击且位于实际地块内的敌人，按实例 ID 保留各自的爆心格。
func _target_cells() -> Dictionary[int, PlantCell]:
	var targets: Dictionary[int, PlantCell] = {} # 同格敌人仍是独立目标。
	for target: Character000Base in _context.hostile_targets(): # 与实际伤害沿用相同的敌对目标类别。
		var cell: PlantCell = _target_cell(target, _target_point(target)) # 盘外及缺格无需纳入分配。
		if cell != null:
			targets[target.get_instance_id()] = cell
	return targets

## 从 [param targets] 为 [param shot] 选出并锁定目标。先选被瞄准次数最少的敌人，
## 再最大化到其他爆心格的最短行列距离。无目标时解除锁定并返回 false。
func _lock_target(shot: Shot, targets: Dictionary[int, PlantCell]) -> bool:
	if targets.is_empty():
		shot.target_id = 0
		return false
	var aim_counts: Dictionary[int, int] = {} # 同一轮内其他星弹对各敌人的锁定次数，含已落地的星弹。
	var centers: Array[Vector2] = [] # 当前有效的其他爆心格，供本发比较距离。
	for other: Shot in _shots: # 取消的星弹没有产生覆盖，也不再占用目标。
		if other == shot or (other.completed and not other.impacted):
			continue
		aim_counts[other.target_id] = aim_counts.get(other.target_id, 0) + 1
		if is_landing_cell(_context.board, other.cell):
			centers.append(Vector2(other.cell.row_col))
	var midpoint := Vector2(_context.board.extent - Vector2i.ONE) * 0.5 # 首发优先选择靠棋盘边缘的敌人。
	var picked := 0 # 当前最佳敌人的实例 ID。
	var fewest_aims := SHOT_COUNT # 用本轮总发数作为锁定次数的初始上界。
	var best_distance := -1.0 # 当前最佳候选与最近爆心的距离平方。
	for target_id: int in targets: # 相同评分沿用权威敌人列表的顺序。
		var address := Vector2(targets[target_id].row_col) # 以格数衡量远近，避免透视和平台偏移影响范围分布。
		var aim_count: int = aim_counts.get(target_id, 0) # 没有锁定记录的敌人优先。
		if aim_count > fewest_aims:
			continue
		var distance: float = address.distance_squared_to(midpoint) if centers.is_empty() else INF # 首发用距棋盘中心的距离评分。
		for center: Vector2 in centers: # 最大化到任一既有落点的最短距离。
			distance = minf(distance, address.distance_squared_to(center))
		if aim_count < fewest_aims or (aim_count == fewest_aims and distance > best_distance):
			picked = target_id
			fewest_aims = aim_count
			best_distance = distance
	shot.target_id = picked
	var target := instance_from_id(picked) as Character000Base # 同一帧重新取出刚采集的目标。
	_aim_at(shot, targets[picked], _target_point(target))
	return true

## 返回 [param target] 用于定位落点的世界坐标；普通僵尸取脚点，僵王取真实受击中心。
func _target_point(target: Character000Base) -> Vector2:
	return target.global_position if target is Zombie000Base else AdventureJalapenoFootprint.hit_center(target)

## 用 [param target] 的 [param point] 查询真实地块，沿用原有的行约束和受击位置。
func _target_cell(target: Character000Base, point: Vector2) -> PlantCell:
	var board: BoardRuntime = _context.board # 只在当前技能所属的棋盘内索敌。
	var cell: PlantCell = board.cell_at_ground_point(point, target.lane) if target is Zombie000Base \
		else board.pick_cell(point) # 无固定行的僵王按世界几何查询。
	return cell if is_landing_cell(board, cell) else null

## 让 [param shot] 追向 [param cell] 上的世界坐标 [param point]，保留触地后随平台移动的局部锚。
func _aim_at(shot: Shot, cell: PlantCell, point: Vector2) -> void:
	shot.cell = cell
	shot.cell_anchor = cell.get_global_transform().affine_inverse() * point

## 更新未落地的 [param shot]。发射时或追踪失效时允许改锁，找不到敌人则保留最后一个落点。
func _track_target(shot: Shot) -> void:
	if shot.target_id == 0 and shot.launched:
		return
	shot.launched = true
	if shot.target_id != 0:
		var target := instance_from_id(shot.target_id) as Character000Base # 释放节点后不保留已失效的对象引用。
		if CharacterSkillTargetQuery.is_valid_hostile(_context, target):
			var point: Vector2 = _target_point(target) # 同一位置用于找格与确定弹道终点。
			var cell: PlantCell = _target_cell(target, point) # 跨格时更新实际爆心格。
			if cell != null:
				_aim_at(shot, cell, point)
				return
	_lock_target(shot, _target_cells())

## 在斜幕内准备窄条几何；真正的起飞由共用 Cut-in 收幕时钟开启。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	global_transform = Transform2D.IDENTITY
	var view_origin: Vector2 = get_global_transform_with_canvas().affine_inverse() \
		* get_viewport_rect().position # 视口左上角在当前战场的坐标。
	for shot: Shot in _shots: # 准备时只创建空中网格，冰在实际触地时入树。
		_prepare_flight(shot, view_origin)
	_shots.sort_custom(_earlier_impact)
	if _context == null:
		_launched = true
		return
	var intro: Tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_STOP).set_ignore_time_scale(true) # 与 Cut-in 同用实际秒。
	intro.tween_interval(CutIn.DURATION - 0.04)
	intro.tween_callback(func() -> void: _launched = true)

## 由 [param view_origin] 与 [param shot] 的落点单独定一个场外高空起点，预烘焙该条斜落弧线。
func _prepare_flight(shot: Shot, view_origin: Vector2) -> void:
	var cell: PlantCell = shot.cell # 用施放时的落点预烘焙初始弧线。
	var ground: Transform2D = cell.get_global_transform() # 用格自身的尺寸，屋顶错列的高度差不等于格高。
	shot.landing_anchor = to_local(ground * shot.cell_anchor)
	var tile: Vector2 = (Vector2(ground.x.length(), ground.y.length()) * cell.size).max(Vector2.ONE) # 屏幕地面的尺寸基准。
	var sky_depth: float = maxf(1.70 * tile.y, shot.landing_anchor.y - view_origin.y + tile.y * 0.21) # 从视口上缘外入场。
	var drop: float = sky_depth + tile.y * (float(shot.index) * 0.033 + float(shot.visual_seed % 4) * 0.006) # 即使重复命中同格也拉开起点。
	var slope: float = 0.42 + float((shot.visual_seed >> 5) % 6) * 0.030 # 保持雨幕共同朝右下落，角度略有变化。
	var margin: float = tile.x * (0.04 + float(shot.index) * 0.062) # 左侧每发也有单独的天际入口。
	var horizontal_room: float = maxf(tile.x * 0.60, shot.landing_anchor.x - view_origin.x - margin) # 近边优先从上方入场。
	var spread: float = tile.x * (float(shot.index) - 2.5) * 0.072 # 同时命中同格时的横向起点差。
	shot.launch_anchor = shot.landing_anchor - Vector2(minf(drop * slope, horizontal_room) + spread, drop)
	if _context == null:
		shot.launch_at = _fixed_launch_times[shot.index] if shot.index < _fixed_launch_times.size() else (
			float(shot.index) * FIXED_LAUNCH_SPACING + float(shot.visual_seed % 6) * 0.009)
	else:
		shot.launch_at = float(shot.index) * LAUNCH_SPACING
	var distance_in_tiles: float = minf(drop / tile.y, 7.2) # 非常小的地块也在同一轮雨幕内到达。
	var duration: float = 0.43 + 0.062 * distance_in_tiles # 给后排更长的下坠时间，保持雨幕有节奏地扫过。
	shot.impact_at = shot.launch_at + duration
	shot.flight = Flight.new()
	shot.flight.z_as_relative = false
	shot.flight.z_index = AIR_Z_INDEX
	add_child(shot.flight)
	shot.flight.configure(shot.launch_anchor, shot.landing_anchor, tile.x, duration, shot.visual_seed)

## 返回 [param cell] 的实际格内落点，不受承托物动画偏移；不规则格优先取靠近种植锚的内部点。
func _surface_anchor(cell: PlantCell) -> Vector2:
	var ground: Vector2 = cell.get_slot_anchor_global_position(CharacterRegistry.PlacePlantInCell.Norm) # 原始表面锚，不含抬高的承托物。
	var anchor: Vector2 = (cell.get_global_transform().affine_inverse() * ground).clamp(Vector2.ZERO, cell.size) # 地块局部点。
	var polygon: PackedVector2Array = cell.board_definition.hit_polygon # 旧格为空，直接使用矩形内的锚。
	if polygon.is_empty() or Geometry2D.is_point_in_polygon(anchor, polygon):
		return anchor
	var triangles: PackedInt32Array = Geometry2D.triangulate_polygon(polygon) # 棋盘已预检，合法轮廓至少有一面。
	var nearest: Vector2 = anchor # 在分解出的实体内部选取离原始地表锚最近的三角形重心。
	var nearest_distance: float = INF # 最近点与原始锚之间的平方距离。
	for index: int in range(0, triangles.size(), 3): # 每组三个索引指向一个内部三角形。
		var center: Vector2 = (polygon[triangles[index]] + polygon[triangles[index + 1]] + polygon[triangles[index + 2]]) / 3.0 # 三角形重心。
		var distance: float = center.distance_squared_to(anchor) # 与原始种植锚的局部距离。
		if distance < nearest_distance:
			nearest = center
			nearest_distance = distance
	return nearest

## [param a] 先于 [param b] 命中时返回 true；同帧积压的命中保持事件先后。
func _earlier_impact(a: Shot, b: Shot) -> bool:
	return a.index < b.index if a.impact_at == b.impact_at else a.impact_at < b.impact_at

## 跟随有效战斗时间 [param delta]；场景或阶段失效时先回收全部临时表现。
func _process(delta: float) -> void:
	if not _cast_is_active() or (_context == null and not _fixed_impact.is_valid()):
		queue_free()
		return
	if not _launched or get_tree().paused or PVZCheat.is_open():
		return
	_sync_sound_rate()
	_clock += delta
	var active_shots := 0 # 到最后一块冰淡尽才归还整次施放。
	var pending_impact: bool = false # 仍有在途星弹时，Boss 继续维持施法。
	for shot: Shot in _shots: # 跨过多个命中点时按实际命中顺序依次兑现。
		if not _cast_is_active() or (_context != null and not _context.is_active()):
			queue_free()
			return
		if shot.completed:
			continue
		_sample(shot)
		active_shots += int(not shot.completed)
		pending_impact = pending_impact or (not shot.completed and not shot.impacted)
	if not pending_impact:
		_notify_impacts_finished()
	if active_shots == 0:
		queue_free()

## 战斗身份始终受棋盘与轮次约束，只有死亡落星能继续处于已接受的 Boss 结算。
func _cast_is_active() -> bool:
	if _context != null or _fixed_validity.is_null():
		return _battle.is_active()
	return _battle.is_same_battle() and _fixed_validity.is_valid() and _fixed_validity.call()

## 通知等待最后一发结算的施法节点，不干预已经生成的星空冰。
func _notify_impacts_finished() -> void:
	if not _reported_impacts:
		_reported_impacts = true
		impacts_finished.emit()

## 战斗失效提前收走本次落星时，也归还施法等待。
func _exit_tree() -> void:
	_notify_impacts_finished()

## 按当前时钟采样 [param shot]，结算前更新索敌，结算后让末端和冰面随爆心格移动。
func _sample(shot: Shot) -> void:
	var ice_age: float = _clock - shot.impact_at # 负值表示仍在飞行。
	var flight_age: float = _clock - shot.launch_at # 用同一时钟取样来声和飞行。
	if flight_age < 0.0:
		return
	if not shot.impacted and _context != null:
		_track_target(shot)
	if not is_landing_cell(_battle.board, shot.cell):
		_clear(shot)
		return
	var landing: Vector2 = to_local(shot.cell.get_global_transform() * shot.cell_anchor) # 按当前实际落点取世界锚。
	var displacement: Vector2 = landing - shot.landing_anchor # 目标移动时，拖尾末端与地表当帧对齐。
	var pitch: float = 0.93 + float(shot.visual_seed % 11) * 0.016 # 少量变调让错开的声像易于辨别。
	if not shot.flight_cued and flight_age >= FLIGHT_CUE_DELAY:
		shot.flight_cued = true
		if ice_age < 0.0:
			_play_sound(_flight_audio, -8.0, pitch)
	if ice_age >= 0.0 and not shot.impacted:
		shot.impacted = true
		var cells: Array[PlantCell] = _footprint(shot.cell) # 同一组格同时决定渲染裁切和本发结算。
		if ice_age < ICE_SECONDS:
			_show_impact(shot, cells, landing, displacement)
		if ice_age < 0.18:
			_play_sound(_impact_audio, -5.5 if _context == null else -7.0, pitch)
		if _context != null:
			_resolve_impact(cells)
		elif _fixed_impact.is_valid():
			_fixed_impact.call(cells)
	if ice_age >= ICE_SECONDS:
		_clear(shot)
		return
	if is_instance_valid(shot.flight):
		shot.flight.set_age(flight_age, displacement)
		if ice_age >= Flight.RETRACT_SECONDS:
			shot.flight.queue_free()
			shot.flight = null
	if is_instance_valid(shot.ice):
		shot.ice.position = landing
		shot.ice.set_age(ice_age, 1.0 - smoothstep(ICE_SECONDS - ICE_FADE, ICE_SECONDS, ice_age))

## [param shot] 触地时从 [param landing] 向 [param cells] 凝冰；[param displacement] 修正实际的末段切线。
func _show_impact(shot: Shot, cells: Array[PlantCell], landing: Vector2, displacement: Vector2) -> void:
	var incoming: Vector2 = shot.flight.impact_tangent(displacement) if is_instance_valid(shot.flight) \
		else (landing - shot.launch_anchor).normalized() # 裁去空中网格后仍按发射方向生成冰。
	shot.ice = Ice.new()
	shot.ice.position = landing
	shot.ice.z_as_relative = false
	shot.ice.z_index = GROUND_Z_INDEX
	add_child(shot.ice)
	shot.ice.configure(shot.cell, cells, shot.cell_anchor, incoming, shot.visual_seed, AIR_Z_INDEX)

## 返回 [param center] 周围的 3×3 实格，缺格、隐藏格与盘外位置不进入结算或绘制。
func _footprint(center: PlantCell) -> Array[PlantCell]:
	var board: BoardRuntime = _battle.board # 按当前稀疏棋盘的实际地址取格。
	var cells: Array[PlantCell] = [] # 固定三行三列，包含实际存在的斜邻格。
	for row: int in range(-RADIUS, RADIUS + 1): # 以爆心为零点的行偏移。
		for column: int in range(-RADIUS, RADIUS + 1): # 以爆心为零点的列偏移。
			var cell: PlantCell = board.cell_at(center.row_col + Vector2i(row, column)) # 跳过盘外、缺失或隐藏的地块。
			if is_landing_cell(board, cell):
				cells.append(cell)
	return cells

## [param cells] 是这发的有效范围，每发对目前仍敌对的目标独立结算。
func _resolve_impact(cells: Array[PlantCell]) -> void:
	var scope := CombatHitScope.new() # 保护者转伤也只承受每个落点的一次 200 点基础伤害。
	for target: Character000Base in _context.hostile_targets(): # 普通僵尸与可受击的僵王共用生命入口。
		if not CharacterSkillTargetQuery.is_valid_hostile(_context, target) or not _inside(target, cells):
			continue
		target.be_attacked_bullet(IMPACT_DAMAGE, BulletRegistry.AttackMode.Norm, true, false, 0, -1, null, scope)
		var zombie := target as Zombie000Base # 控制沿用寒冷与魅惑系统，不把设施或僵王当作普通僵尸。
		if not CharacterSkillTargetQuery.can_receive_negative(_context, zombie):
			continue
		AdventureDeepCold.apply_to(zombie, _battle, SLOW_SECONDS, 0.0, AdventureIceShroomCast.ALL_ZOMBIE_STATUSES)
		if _combat_random.randf() < CHARM_CHANCE:
			AdventurePlantNegativeEffects.apply(zombie, AdventurePlantNegativeEffects.Kind.CHARM)

## 播放 [param stream] 的单次撞击或掠风，[param gain] 是分贝，[param pitch] 是音高倍率，随战斗一起暂停及清场。
func _play_sound(stream: AudioStream, gain: float, pitch: float) -> void:
	if stream == null:
		return
	var player := AudioStreamPlayer.new() # 每发音轨互不截断，由结尾或施放节点回收。
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	player.stream = stream
	player.bus = SoundManager.spatial_sfx_bus()
	player.volume_db = gain
	player.pitch_scale = pitch * _sound_rate
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()

## 按当前战斗倍率更新这轮已有的掠风和凝固声，切换速度时不重播。
func _sync_sound_rate() -> void:
	var rate: float = maxf(0.10, Engine.time_scale) # 播放器要求正的速率。
	if is_equal_approx(_sound_rate, rate):
		return
	for child: Node in get_children(): # 飞行和冰面节点已经按相同战斗时钟推进。
		if child is AudioStreamPlayer:
			child.pitch_scale *= rate / _sound_rate
	_sound_rate = rate

## [param target] 的卡位或真实受击中心须落入 [param cells]，盘外与空洞不吸附到邻格。
func _inside(target: Character000Base, cells: Array[PlantCell]) -> bool:
	var point: Vector2 = _target_point(target) # 结算与索敌使用同种世界位置。
	if target is Zombie000Base:
		return cells.has(_context.board.cell_at_ground_point(point, target.lane))
	for cell: PlantCell in cells: # 不把整片棋盘的包围框当作有效格。
		if cell.contains_world_point(point):
			return true
	return false

## 释放 [param shot] 尚在场上的起飞和落地表现，禁止该记录之后再结算。
func _clear(shot: Shot) -> void:
	shot.completed = true
	if is_instance_valid(shot.flight):
		shot.flight.queue_free()
		shot.flight = null
	if is_instance_valid(shot.ice):
		shot.ice.queue_free()
		shot.ice = null
