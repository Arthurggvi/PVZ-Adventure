## 玉米投手的共享投掷时钟。飞行、空袭与命中结算均使用紧凑数据。
extends Node

## 维持玉米投手原生的地面及水下攻击资格。
const DIRECT_MASK: int = 5
## 玉米炮的地面爆炸覆盖所有状态的有效敌人。
const BLAST_MASK: int = 31
## 从离手到第一次落雨及后续相邻雨点之间的游戏秒数。
const RAID_ARRIVAL: float = 0.72
## 六组下落各拥有一次明确的命中。
const RAID_STEP: float = Visual.RAIN_STEP
## 每锁定最多结算六次落雨。
const RAID_PULSES: int = 6
## 极端密集时分开限制到期事件准备和实际目标结算。
const EVENT_LIMIT: int = 72
## 每步最多消费的受击目标，包括后来退场的候选。
const HIT_LIMIT: int = 160
## 每个批处理阶段的墙钟预算，单位微秒。
const STEP_USEC: int = 2200
## 前一声炮响的主要低频尾音仍在播放的秒数。按未乘游戏倍速的物理帧间隔比较。
const COB_BOOM_REPEAT_WINDOW: float = 0.60
## 地面脚点的宽相桶宽；最后仍由棋盘原有的精确判格决定。
const FOOT_BUCKET: float = 128.0
## 使用真实炮弹底图的统一视觉画布。
const Visual = preload("res://scripts/adventure/research/corn_visual.gd")
## 四种实际结果与画布使用同一枚举。
const Kind = Visual.Kind
## 中毒只对实际承伤者叠层。
const Poison = preload("res://scripts/adventure/research/corn_poison.gd")
## 复用既有落点的活敌资格和准确脚点。
const Ground = preload("res://scripts/adventure/research/cabbage_landing.gd")

## 一枚投掷及其计时数据，可在队列中重复排下一个雨点。
class Drop:
	## 捕获的原局、卡面伤害与攻击归因。
	var shot: RepeaterShotContext
	## 画布与结算共用的弹种。
	var kind: Visual.Kind
	## 原生动画或空袭指派的锁定对象。
	var target: Character000Base
	## 起手时可确认的最后脚点。
	var foot: Vector2
	## 起手时最后瞄准的世界受击点。
	var aim: Vector2
	## 物理落点的逻辑行。
	var row: int
	## 追踪落下时确认的格子，动态平台可以带着此格移动。
	var cell: PlantCell
	## 本弹基础伤害已经应用卡片及赌徒的出手倍率。
	var damage: int
	## 每次粒弹命中加一层玉米中毒。
	var poison: bool
	## 仅黄油使用，黄油日把定身变为范围。
	var wide: bool
	## 黄油以原生四秒为基础。
	var butter_seconds: float = 4.0
	## 当前已经消费的雨点。
	var pulse: int = 0
	## 本事件到期的战斗时钟。
	var due: float
	## 同时到期按真实发射先后结算。
	var serial: int
	## 已创建的可视飞行可在第一滴雨后由真实落点更新。
	var visual: Visual.Flight

## 已在某次落点捕获的共享候选和进度，后续移入者不吃旧落点。
class Work:
	## 本次落点的只读数据。
	var drop: Drop
	## 最先结算的直接受击者。
	var direct: Character000Base
	## 期望先打直击，范围数组随后消费。
	var cursor: int
	## 格子范围目标，多个重叠空袭共享该数组。
	var area: Array[Character000Base] = []
	## 本次范围按实际承伤实体去重。
	var scope: CombatHitScope

## 战场实例身份，空闲时仍可被三行攻击时钟惰性查询。
var _game: MainGameManager
## 只在存有定时工作时推进。
var _clock: float = 0.0
## 下一个稳定发射序号。
var _serial: int = 0
## 到期先后的小根堆，休眠飞行不逐弹进行物理遍历。
var _heap: Array[Drop] = []
## 需要分帧的实际命中，按真实到达顺序处理。
var _work: Array[Work] = []
## 已消费的工作索引，批次尾部一次性回收。
var _head: int = 0
## 候选脚点最多每物理步取样一次。
var _sampled_frame: int = -1
## 能作为空袭随机锁定的活体。
var _raid_targets: Array[Character000Base] = []
## 空袭目标对应的真实格子。
var _raid_cells: Array[PlantCell] = []
## 按真实地址直接定位候选组。
var _grid: Dictionary[Vector2i, Array] = {}
## 黄油日包含正常入场区域，按行复用候选，无需遍历全盘。
var _rows: Dictionary[int, Array] = {}
## 同中心3×3在本物理步共用候选，已经在途的工作保留原快照。
var _squares: Dictionary[Vector2i, Array] = {}
## 僵王可能有多个跨行真实受击框。
var _bosses: Array[ZB000Base] = []
## 不存在的宽相桶使用仍然有类型的空集合。
var _empty_cells: Array[PlantCell] = []
## 仅有僵王时调用一次共享几何查询。
var _boss_shape := RectangleShape2D.new()
## 活跃表现无需弹体节点或独立计时器。
var _visual: Visual
## 大量同时落炮只使用少数共用声部。
var _next_boom: float = 0.0
## 上一次获准发声的物理帧；首次落炮前为 -1，休眠期间仍按全局物理帧拉开间隔。
var _last_boom_frame: int = -1
## 粒雨和黄油用单个冷却时间合并密集命中声。
var _next_tap: float = 0.0

## [param game] 只创建一个玉米运行时，置于原生弹体容器。
static func for_battle(game: MainGameManager) -> Node:
	var runtime: Node = game.bullets.get_node_or_null(^"CornBattle") # 当前战场生命周期。
	if runtime == null:
		runtime = (load("res://scripts/adventure/research/corn_battle.gd") as Script).new()
		runtime.name = "CornBattle"
		runtime._game = game
		game.bullets.add_child(runtime)
	return runtime

## 安装唯一的发射和落点画布，视觉与物理各自按活动状态休眠。
func _ready() -> void:
	_visual = Visual.new()
	add_child(_visual)
	_visual.z_as_relative = false
	_visual.z_index = 370
	set_physics_process(false)

## 从 [param plant] 前方的三行取最靠近防线的目标，有本行时优先本行。
func butter_target(plant: Plant000Base) -> Character000Base:
	_refresh_grid()
	var nearest: Character000Base # 跨行比较横坐标，跳过身后目标。
	var best: float = INF # 同行候选优先。
	for row: int in [plant.lane, plant.lane - 1, plant.lane + 1]: # 一次只看到三行的活敌。
		if row != plant.lane and nearest != null and nearest.lane == plant.lane:
			break
		for reference: Variant in _rows.get(row, []): # 允许还在盘外入场线上的目标。
			if not is_instance_valid(reference) or not Ground.can_hit(reference, DIRECT_MASK):
				continue
			var x: float = reference.hurt_box_component.global_position.x # 范围在投手前方。
			if x >= plant.global_position.x and x < best:
				best = x
				nearest = reference
	return nearest

## [param count] 粒优先随机锁不同活敌，敌人不足时再从候选中选取。
func raid_locks(count: int) -> Array[int]:
	_refresh_grid()
	var result: Array[int] = [] # 不复制整份怪群快照。
	var size: int = _raid_targets.size() # 空盘时仍保留各自朝天发射的表现。
	var shuffled: Dictionary[int, int] = {} # 小范围惰性洗牌，只写实际抽取的下标。
	for index: int in range(count): # 一粒一锁。
		if size == 0:
			result.append(-1)
		elif index >= size:
			result.append(randi_range(0, size - 1))
		else:
			var selected: int = randi_range(index, size - 1) # 尚未选的范围。
			result.append(int(shuffled.get(selected, selected)))
			shuffled[selected] = int(shuffled.get(index, index))
	return result

## [param shot] 的 [param kind] 从 [param origin] 出手。[param aim] 与 [param row] 是动画锁定的快照。
## [param delay] 错开同轮弹幕，[param damage] 先冻结原始粒弹强度。[param lock] 为独立空袭锁。
## [param poison]、[param wide] 与 [param butter_seconds] 只针对本枚弹的对应结算。
func launch(shot: RepeaterShotContext, kind: Visual.Kind, target: Character000Base, origin: Vector2,
		aim: Vector2, row: int, delay: float, damage: int, poison: bool,
		wide: bool, butter_seconds: float, lock: int = -1) -> void:
	var event := Drop.new() # 每枚飞行只创建一个小数据对象。
	event.shot = shot
	event.kind = kind
	if kind == Kind.RAID:
		event.target = _raid_targets[lock] if lock >= 0 and lock < _raid_targets.size() else null
		event.cell = _raid_cells[lock] if lock >= 0 and lock < _raid_cells.size() else null
	else:
		event.target = target
	event.aim = aim
	event.row = event.cell.combat_lane if event.cell != null else row
	event.foot = event.cell.get_spawn_global_position() if event.cell != null else Ground.foot_at(shot, target, aim.x, row)
	event.damage = damage
	event.poison = poison
	event.wide = wide
	event.butter_seconds = butter_seconds
	_serial += 1
	event.serial = _serial
	var duration: float = clampf(origin.distance_to(aim) / 600.0 + 0.33, 0.54, 1.32) # 常规投手保留抛物线和长短差。
	if kind == Kind.RAID:
		duration = RAID_ARRIVAL
	elif kind == Kind.COB:
		duration = 0.91
	event.due = _clock + delay + duration
	_push(event)
	event.visual = _visual.flight(kind, origin, aim, event.cell, event.foot, event.target, delay, duration, event.serial)
	set_physics_process(true)

## [param delta] 推进游戏时钟。两个独立预算避免大量雨点全部压在一帧。
func _physics_process(delta: float) -> void:
	_clock += delta
	var start: int = Time.get_ticks_usec() # 捕获落点、候选和下一次雨点。
	var count: int = 0 # 批次至少推进一个到期事件。
	while not _heap.is_empty() and _heap[0].due <= _clock + 0.000001 and count < EVENT_LIMIT:
		if count > 0 and Time.get_ticks_usec() - start >= STEP_USEC:
			break
		_arrive(_pop())
		count += 1
	_drain()
	set_physics_process(not _heap.is_empty() or not _work.is_empty())

## 完成 [param event] 的一次真正落地，同一空袭复用记录继续安排后五次。
func _arrive(event: Drop) -> void:
	if not event.shot.is_active():
		return
	if event.kind == Kind.RAID and not is_instance_valid(event.cell):
		return
	var direct: Character000Base # 空袭和炮弹的计伤只由落点决定。
	if event.kind != Kind.RAID or event.pulse == 0:
		if is_instance_valid(event.target) and Ground.can_hit(event.target, DIRECT_MASK) and (event.kind == Kind.RAID \
				or absf(event.target.hurt_box_component.global_position.x - event.aim.x) <= 200.0):
			var target_row: int = event.target.lane # 地面 target 已换行则跟随。
			event.row = target_row if target_row >= 0 else event.row
			event.foot = Ground.foot_at(event.shot, event.target, event.target.hurt_box_component.global_position.x, event.row)
			var current: PlantCell = event.shot.board.cell_at_ground_point(event.foot, event.row) # 的确站在合法落点。
			if event.kind != Kind.RAID or current != null:
				event.cell = current
			if event.kind == Kind.KERNEL or event.kind == Kind.BUTTER:
				direct = event.target
		elif event.kind != Kind.RAID:
			event.cell = event.shot.board.cell_at_ground_point(event.foot, event.row)
			if event.kind == Kind.KERNEL or event.kind == Kind.BUTTER:
				direct = _fallback(event.cell, event.foot)
	var area: bool = event.kind == Kind.RAID or event.kind == Kind.COB or (event.kind == Kind.BUTTER and event.wide) # 黄油日只有定身范围。
	var work := Work.new() # 按到达时的实际候选产生一份顺序工作。
	work.drop = event
	work.direct = direct
	work.cursor = -1 if is_instance_valid(direct) else 0
	if area and is_instance_valid(event.cell):
		work.area = _square(event.cell)
		work.scope = CombatHitScope.new()
	if work.cursor < 0 or not work.area.is_empty():
		_work.append(work)
	var floor: Vector2 = event.cell.get_spawn_global_position() if is_instance_valid(event.cell) and area else event.foot # 范围锚点随真实格走。
	if event.visual != null and event.pulse == 0:
		event.visual.foot = floor
		event.visual.cell = event.cell
		event.visual.landed = true
	var pitch: Vector2 = event.shot.board.local_pitch(event.cell) if is_instance_valid(event.cell) else event.shot.cell_pitch # 画布按原棋格缩放。
	var impact: Vector2 = (direct.hurt_box_component.global_position if is_instance_valid(direct) else event.aim) + Vector2(0, -18) # 直击与弧线结束一致。
	_visual.impact(event.kind, floor, impact, pitch, area, event.pulse, event.poison)
	if event.kind == Kind.COB and _clock >= _next_boom:
		_next_boom = _clock + 0.18
		var frame: int = Engine.get_physics_frames() # 倍速会压缩游戏秒数，音效播放长度仍固定。
		var follows_recent: bool = _last_boom_frame >= 0 \
			and frame - _last_boom_frame < COB_BOOM_REPEAT_WINDOW * Engine.physics_ticks_per_second # 只衰减前一炮尾音内的跟发。
		_last_boom_frame = frame
		SoundManager.play_corn_cob_impact_SFX(self, floor, follows_recent)
		EventBus.push_event(MainGameCamera.SHAKE_EVENT, [Vector2(4.0, 6.0), 0.14, 23.0])
	elif event.kind != Kind.COB and _clock >= _next_tap and (work.cursor < 0 or not work.area.is_empty()):
		_next_tap = _clock + 0.071
		SoundManager.play_bullet_attack_SFX(SoundManagerClass.TypeBulletSFX.Butter \
			if event.kind == Kind.BUTTER else SoundManagerClass.TypeBulletSFX.Corn, self, floor if area else impact)
	if event.kind == Kind.RAID:
		event.pulse += 1
		if event.pulse < RAID_PULSES:
			event.due = maxf(event.due + RAID_STEP, _clock + RAID_STEP * 0.70)
			_push(event)

## 对极少数同帧海量命中分批处理。普通落点仍在到期步即时兑现。
func _drain() -> void:
	var start: int = Time.get_ticks_usec() # 回调触发的受击动画也纳入预算。
	var count: int = 0 # 同时计数后来失效的候选。
	while _head < _work.size() and count < HIT_LIMIT:
		if count > 0 and Time.get_ticks_usec() - start >= STEP_USEC:
			break
		var work: Work = _work[_head] # 重入时保持先后顺序。
		if not work.drop.shot.is_active() or work.cursor >= work.area.size():
			_work[_head] = null
			_head += 1
		else:
			var direct: bool = work.cursor < 0 # 黄油日只有主目标承担普通黄油伤害。
			var target: Variant = work.direct if direct else work.area[work.cursor] # 前一个命中可同步移除它。
			work.cursor += 1
			if is_instance_valid(target) and (direct or target != work.direct):
				_hit(work, target, direct)
		count += 1
	if _head == _work.size():
		_work.clear()
		_head = 0
	elif _head >= 128 and _head * 2 >= _work.size():
		_work = _work.slice(_head)
		_head = 0

## [param work] 的 [param target] 保留防具、免疫、代伤和击杀归属；[param direct] 为真正直击。
func _hit(work: Work, target: Character000Base, direct: bool) -> void:
	var event: Drop = work.drop # 已冻结的出手结果不从当前原株重新读取。
	if not Ground.can_hit(target, BLAST_MASK if event.kind == Kind.COB else DIRECT_MASK):
		return
	if direct or event.kind == Kind.RAID or event.kind == Kind.COB:
		var context: PlantAttackContext = event.shot.attack_context # 原生词条逐目标修饰。
		var damage: int = context.modify_damage(event.damage, target) if context != null else event.damage # 保留出手时倍率。
		var mode := BulletRegistry.AttackMode.Penetration if event.kind == Kind.COB else BulletRegistry.AttackMode.Real # 炮弹遵守爆炸防具规则。
		var receipt: Variant = {} if event.poison else null # 只有毒需要取得代伤后的真实接收者。
		if target is Zombie000Base:
			var armor: float = context.armor_multiplier if context != null else 1.0 # 通用内容沿原生入口。
			event.shot.on_kill((target.hp_component as HpComponentZombie).apply_hit(damage, mode, true,
				false, true, armor, 0, -1, receipt, work.scope))
		else:
			target.be_attacked_bullet(damage, mode, true, false, 0, -1, receipt, work.scope)
			if is_instance_valid(target) and target.is_death and target is ZB000Base:
				event.shot.on_kill(target)
		if receipt is Dictionary and not receipt.get("duplicate_hit", false):
			var actual: Variant = receipt.get("recipient") # 有效的同一次直击才加毒。
			if is_instance_valid(actual):
				Poison.add_hit(actual, event.shot)
	if event.kind == Kind.BUTTER and is_instance_valid(target) and target is Zombie000Base \
			and not target.is_death and is_instance_valid(target.head_node):
		var timer: Timer = target.all_timer[Character000Base.E_TimerType.Butter] # 弱黄油不覆盖更长的定身。
		if not is_instance_valid(timer) or timer.time_left < event.butter_seconds:
			target.be_butter(event.butter_seconds)

## 普通抛投目标离场时，[param cell] 内离 [param foot] 最近的有效僵尸可接到落弹。
func _fallback(cell: PlantCell, foot: Vector2) -> Character000Base:
	if not is_instance_valid(cell):
		return null
	_refresh_grid()
	var result: Character000Base # 沿用真正落点，不再重新全场追踪。
	var best: float = 35.0 # 只有落点边上的身体可接触此弹。
	for entry: Variant in _grid.get(cell.row_col, []): # 站在同一可用格。
		if is_instance_valid(entry) and Ground.can_hit(entry, DIRECT_MASK):
			var distance: float = absf(entry.global_position.x - foot.x) # 距实际入地线的水平差。
			if distance < best:
				best = distance
				result = entry
	return result

## 活敌与脚点按需一次采样，每次发射或空袭脉冲不从头扫描。
func _refresh_grid() -> void:
	var frame: int = Engine.get_physics_frames() # 一物理步只读一次世界名单。
	if frame == _sampled_frame:
		return
	_sampled_frame = frame
	_raid_targets.clear()
	_raid_cells.clear()
	_grid.clear()
	_rows.clear()
	_squares.clear()
	_bosses = _game.zombie_manager.get_living_bosses()
	var buckets: Dictionary[Vector2i, Array] = {} # 世界横坐标和逻辑行共同裁掉绝大多数无关地块。
	var fallback_rows: Dictionary[int, bool] = {} # 极宽自定义平台不填充任意数量的桶。
	for cell: PlantCell in _game.board.cells(): # 一份棋盘宽相供所有脚点查询。
		var bounds: Rect2 = cell.get_global_transform() * Rect2(Vector2.ZERO, cell.size) # 旋转平台也能被保守地覆盖。
		var first: int = floori(bounds.position.x / FOOT_BUCKET) # 与脚点采用相同坐标。
		var last: int = floori(bounds.end.x / FOOT_BUCKET) # 保留格底闭边和右侧相邻边。
		if last - first > 32:
			fallback_rows[cell.combat_lane] = true
			continue
		for slot: int in range(first, last + 1): # 一般一个格只写到一至两个桶。
			var key := Vector2i(cell.combat_lane, slot) # 不把相同行号的不同平台混成一个格。
			if not buckets.has(key):
				var entries: Array[PlantCell] = [] # 公共判格入口接收真实地块数组。
				buckets[key] = entries
			buckets[key].append(cell)
	for target: Zombie000Base in _game.zombie_manager.all_zombies_1d: # 含普通及炮弹可命中的特殊姿态。
		if not Ground.can_hit(target, BLAST_MASK):
			continue
		var direct: bool = (target.curr_be_attack_status & DIRECT_MASK) != 0 # 黄油日范围包括入场中的可攻击敌人。
		if direct:
			_index_for_row(target, target.lane)
		var foot: Vector2 = target.global_position # 受击碰撞高度不用于定位站立的格子。
		var key := Vector2i(target.lane, floori(foot.x / FOOT_BUCKET)) # 极远入场者在索敌表内，暂无落点。
		var candidates: Array[PlantCell] = _game.board.row_cells(target.lane) if fallback_rows.has(target.lane) else buckets.get(key, _empty_cells) # 原有稀疏棋盘边界保留。
		var cell: PlantCell = BoardQueries.ground_cell_from(_game.board, foot, target.lane, candidates) # 精确验证地块和可选多边形。
		if cell == null:
			continue
		if not _grid.has(cell.row_col):
			_grid[cell.row_col] = []
		_grid[cell.row_col].append(target)
		if direct:
			_raid_targets.append(target)
			_raid_cells.append(cell)
	for boss: ZB000Base in _bosses: # 无上的 Boss 用真实受击锚点落格。
		if not Ground.can_hit(boss, DIRECT_MASK):
			continue
		var cell: PlantCell = _game.board.pick_cell(boss.hurt_box_component.global_position) # 空中场景仍须位于实际盘内。
		if cell != null:
			_raid_targets.append(boss)
			_raid_cells.append(cell)
			_index_for_row(boss, cell.combat_lane)

## 将 [param target] 缓存在 [param row] 的索敌表中，不要求进入种植区域。
func _index_for_row(target: Character000Base, row: int) -> void:
	if row < 0:
		return
	if not _rows.has(row):
		_rows[row] = []
	_rows[row].append(target)

## [param center] 的真实3×3短期共享候选。
func _square(center: PlantCell) -> Array[Character000Base]:
	_refresh_grid()
	if _squares.has(center.row_col):
		return _squares[center.row_col]
	var result: Array[Character000Base] = [] # 同一脚点只能位于一个真实格。
	var bounds: Rect2 = center.get_global_rect() # 仅僵王需要几何宽相。
	for cell: PlantCell in _game.board.neighbors(center, 1): # 不跨断开的种植平台。
		if cell.board_definition.surface_id != center.board_definition.surface_id \
				or absi(cell.row_col.x - center.row_col.x) > 1 or absi(cell.row_col.y - center.row_col.y) > 1:
			continue
		result.append_array(_grid.get(cell.row_col, []))
		bounds = bounds.merge(cell.get_global_rect())
	if not _bosses.is_empty():
		_boss_shape.size = bounds.size
		var areas: Array[Area2D] = CombatExplosion.query_shape(_game.get_world_2d().direct_space_state,
			_boss_shape, Transform2D(0.0, bounds.get_center()), RepeaterFieldQueries.ENEMY_HURT_MASK) # 共用真实受击框。
		for area: Area2D in areas: # 同一僵王多个框只加一次。
			var boss := area.owner as ZB000Base # 普通目标已由脚点定位。
			if is_instance_valid(boss) and not result.has(boss):
				result.append(boss)
	_squares[center.row_col] = result
	return result

## [param a] 是否早于 [param b]；同时到期按发射顺序。
static func _earlier(a: Drop, b: Drop) -> bool:
	return a.due < b.due or (a.due == b.due and a.serial < b.serial)

## 将 [param event] 按到期时间插入，不排序或遍历所有在途弹。
func _push(event: Drop) -> void:
	var index: int = _heap.size() # 候选先放在叶子位置。
	_heap.append(event)
	while index > 0:
		var parent: int = (index - 1) / 2 # 二叉堆父结点。
		if not _earlier(event, _heap[parent]):
			break
		_heap[index] = _heap[parent]
		index = parent
	_heap[index] = event

## 取出最早到期项，余项只做一次向下修复。
func _pop() -> Drop:
	var result: Drop = _heap[0] # 当前真实到期项。
	var last: Drop = _heap.pop_back() # 用原最后一项修复空根。
	if _heap.is_empty():
		return result
	var index: int = 0 # 当前空位。
	var left: int = 1 # 最先检查左子树。
	while left < _heap.size():
		var next: int = left + 1 if left + 1 < _heap.size() and _earlier(_heap[left + 1], _heap[left]) else left # 较早的一侧。
		if not _earlier(_heap[next], last):
			break
		_heap[index] = _heap[next]
		index = next
		left = index * 2 + 1
	_heap[index] = last
	return result
