## 冲锋的战场时间轴。受击扫掠和血马绘制共用各行的路线、加速曲线与枪锋坐标。
extends Node2D

## 独立绘制血马、残像与命中反馈，所有位置使用同一世界坐标。
const ChargeVisual = preload("res://scripts/adventure/skills/don_quixote_charge_visual.gd")
## 每批的登场喷鼻和首蹄音轨。
const ARRIVAL_SOUND: AudioStream = preload("res://assets/adventure/audio/don_quixote_arrival.ogg")
## 每批推过棋盘时的马蹄音轨。
const GALLOP_SOUND: AudioStream = preload("res://assets/adventure/audio/don_quixote_gallop.ogg")
## 真实碰撞的闷击和金属短响。
const HIT_SOUND: AudioStream = preload("res://assets/adventure/audio/don_quixote_hit.ogg")
## 送入原生受击路由的基础伤害。
const DAMAGE: int = 700
## 命中后施加的原生增伤、减攻比例，重复施加取最强。
const DEGRADATION: float = 0.50
## 退幕露出棋盘时开始第一匹血马的预兆，单位实际秒。
const ENTRY_TIME: float = 1.10
## 每匹马的蓄力长度，单位实际秒。
const WINDUP: float = 0.28
## 一匹马沿当前整行推过的实际秒。
const FLIGHT: float = 1.22
## 同批每行的起步间隔，单位实际秒。
const ROW_GAP: float = 0.070
## 偶数行最后一匹与奇数行首匹的起步间隔，单位实际秒。
const GROUP_GAP: float = 0.30
## 最后一匹的残像、火花和音效收净所需的实际秒。
const TAIL: float = 0.55

## 一匹血马的实际攻击行、脚点路线和启动时点。
class Run:
	## 从零起算的棋盘行。
	var lane: int
	## 棋盘左沿的登场锚点，单位为世界像素。
	var start: Vector2
	## 冲出棋盘的目的地，单位为世界像素。
	var end: Vector2
	## 使用实际行高决定绘制和枪锋偏移，世界像素。
	var pitch: float
	## 旧屋顶和多段地势复用僵尸实际行走的坡面查询。
	var slope: MainGameSlope
	## 屋顶局部高度转为世界坐标使用的行纵轴。
	var slope_axis: Vector2
	## 出手后到该匹马登场的实际秒。
	var arrival: float
	## 登场之后，马蹄离开原位的实际秒。
	var launch: float = WINDUP
	## 登场之后，枪锋结束扫掠的实际秒。
	var finish: float = WINDUP + FLIGHT
	## 所属批次，0 为偶数行，1 为奇数行。
	var wave: int
	## 是否是当前批次的首匹马，只由它触发马蹄和出场声音。
	var is_lead: bool

	## 返回从 [param age] 登场后开始加速的脚点。窗口外钳制在端点。
	func feet_at(age: float) -> Vector2:
		var t: float = clampf(inverse_lerp(launch, finish, age), 0.0, 1.0) # 离地前后分别钳制在端点。
		var point: Vector2 = start.lerp(end, t * (0.28 + t * (0.96 - 0.24 * t))) # 起跑聚力，越过半场明显提速。
		if is_instance_valid(slope):
			point += slope_axis * slope.get_all_slope_y(point.x)
		return point

	## 返回与 [param age] 脚点共用同一运动的枪锋接触中心。
	func lance_at(age: float) -> Vector2:
		return feet_at(age) + Vector2(0.57, -0.54) * pitch

## 此次施放的敌方查询和能力结算权限。
var _context: CharacterSkillContext
## 战局与阶段的活性，普通暂停不会令战局来源失效。
var _battle: RepeaterShotContext
## 各行按偶数行、奇数行排序，同批从上往下。
var _runs: Array[Run] = []
## 穿过时复用标准受击形状扫掠，探针覆盖枪身和前胸的接触区域。
var _probe := ElectricPeaFlightQuery.new(1.42)
## 同一实际承伤者在本次施放只扣一次，包含保护者代伤。
var _hit_scope := CombatHitScope.new()
## 记住已造成受击反馈的候选，避免长受击框持续扫掠。
var _contacted: Dictionary[int, bool] = {}
## 画面只消费本脚本计算的运动时间及确认过的撞击。
var _visual: Node2D
## 上一个时间轴采样，供连续扫掠和音效边沿触发。
var _previous: float = 0.0
## 整个表现自然回收的时间点，包含最后一匹马的残留。
var _finish_time: float
## 下一次允许播放碰撞音与微震的实际秒。紧邻多目标仍有各自的视觉火花。
var _next_hit_cue: float = 0.0

## 从 [param context] 的真实行建立路线，[param battle] 用于战局失效时取消未兑现的演出。
func _init(context: CharacterSkillContext, battle: RepeaterShotContext) -> void:
	_context = context
	_battle = battle
	for parity: int in [1, 0]: # 索引 1、3、5 对应画面上的偶数行。
		var row_offset: int = 0 # 同批行只错开少量时间。
		for lane: int in range(parity, context.board.extent.x, 2): # 遍历规则或稀疏棋盘上实际存在的行。
			var cells: Array[PlantCell] = context.board.row_cells(lane) # 行端点沿用棋盘归属及脚点。
			var bounds: Rect2 = BoardQueries.bounds(cells) # 用实际行宽，兼容非九列关卡。
			if not bounds.has_area():
				continue
			var first: PlantCell = context.board.nearest_cell(Vector2(bounds.position.x, bounds.get_center().y), lane) # 左缘地块。
			var last: PlantCell = context.board.nearest_cell(Vector2(bounds.end.x, bounds.get_center().y), lane) # 刷怪侧地块。
			var row: ZombieRow = context.game.zombie_manager.all_zombie_rows[lane] # 保留僵尸行的坡面坐标基准。
			var spawn: Vector2 = row.zombie_create_position.global_position # 覆盖出生位置前的可达区。
			var run := Run.new() # 几何与时间轴都在出手前提交。
			run.lane = lane
			run.pitch = clampf(first.size.y, 55.0, 132.0)
			run.start = Vector2(bounds.position.x - 0.91 * run.pitch, first.get_spawn_global_position().y - 3.0)
			run.end = Vector2(maxf(bounds.end.x + 2.10 * run.pitch, spawn.x + run.pitch), last.get_spawn_global_position().y - 3.0)
			var slope: MainGameSlope = context.game.main_game_slope # 路线端点取水平基线时，补上全程地形偏移。
			if is_instance_valid(slope) and (context.board.definition == null or slope.sample_walking_height):
				run.slope = slope
				run.slope_axis = row.global_transform.y
			run.wave = 1 - parity
			run.is_lead = row_offset == 0
			run.arrival = ENTRY_TIME + row_offset * ROW_GAP
			if run.wave == 1 and not _runs.is_empty():
				run.arrival = maxf(run.arrival, _runs[-1].arrival + (GROUP_GAP if run.is_lead else ROW_GAP))
			_runs.append(run)
			row_offset += 1

## 有至少一条有效的冲锋路线时允许提交和开启冷却。
func has_runs() -> bool:
	return not _runs.is_empty()

## 准备可暂停的战局时间轴，实时推进发生在物理步。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_visual = ChargeVisual.new(_runs)
	add_child(_visual)
	_visual.top_level = true
	_visual.global_transform = Transform2D.IDENTITY
	_finish_time = _runs[-1].arrival + _runs[-1].finish + TAIL

## [param _delta] 不推进动画；即使暂停也持续检查战局身份。
func _process(_delta: float) -> void:
	if not _battle.is_active():
		queue_free()

## [param delta] 是本物理步的战斗秒，折回正常速率后只累计一次，和 Cut-in 保持节拍。
func _physics_process(delta: float) -> void:
	if get_tree().paused or not _context.is_active() or is_queued_for_deletion():
		return
	var elapsed: float = minf(_finish_time, _previous + delta / Engine.time_scale) # 使用物理步长保证掉帧时的采样仍连续。
	_advance(elapsed)
	if elapsed >= _finish_time:
		queue_free()

## [param elapsed] 驱动各行的起手与扫掠，并把已确认的时间提交给画面。
func _advance(elapsed: float) -> void:
	var targets: Array[Character000Base] = [] # 进入首匹马的命中区后，每步只取一次目标快照。
	var sampled: bool = false # 空棋盘仍只读一次目标登记。
	for run: Run in _runs: # 低帧率跨过时点时依然保持顺序。
		var age: float = elapsed - run.arrival # 相对当前血马出场的实际秒。
		var before: float = _previous - run.arrival # 上一采样相同坐标系的时间。
		if run.is_lead and before < 0.0 and age >= 0.0:
			_play_sound(ARRIVAL_SOUND, -6.0 - 2.5 * run.wave, 1.0 + 0.10 * run.wave)
		if run.is_lead and before < run.launch and age >= run.launch:
			_play_sound(GALLOP_SOUND, -3.0 - 3.5 * run.wave, 0.97 + 0.10 * run.wave)
			EventBus.push_event(MainGameCamera.SHAKE_EVENT, [Vector2(4.5, 6.0), 0.18, 28.0])
		if before >= run.finish or age < run.launch:
			continue
		if not sampled:
			targets = _context.hostile_targets()
			sampled = true
		_sweep(run, before, age, elapsed, targets)
		if not _context.is_active():
			return
	_previous = elapsed
	_visual.paint(elapsed)

## 对 [param run] 的枪锋从 [param before] 至 [param age] 做真实扫掠。
## [param elapsed] 为绝对时间，[param targets] 在本物理步共享。穿过目标后继续扫掠。
func _sweep(run: Run, before: float, age: float, elapsed: float, targets: Array[Character000Base]) -> void:
	var start: Vector2 = run.lance_at(before) # 首次和末次都钳制到真正可命中的路线端点。
	var finish: Vector2 = run.lance_at(age) # 用整段位移避免跳过窄受击框。
	var contacts: Array[Vector2] = [] # x 为先后比例，y 为当前目标快照中的索引。
	for index: int in range(targets.size()): # 检查普通僵尸的登记行，跨行 Boss 使用实际受击几何。
		var target: Character000Base = targets[index] # 本步先前的冲锋可能已经释放目标。
		if not ElectricPeaFlightQuery.can_hit(target) or _contacted.has(target.get_instance_id()):
			continue
		if target is Zombie000Base and target.lane != run.lane:
			continue
		var contact: float = _probe.contact_fraction(target.hurt_box_component.hurt_box_real, start, finish) # 获取最早真正碰撞的点。
		if is_finite(contact):
			contacts.append(Vector2(contact, index))
	if contacts.size() > 1:
		contacts.sort_custom(func(left: Vector2, right: Vector2) -> bool: return left.x < right.x) # 同一步也按沿途顺序结算。
	for contact: Vector2 in contacts: # 一次命中有可能通过信号结束本战斗。
		var target: Character000Base = targets[int(contact.y)] # 逐击重新检查有效性，避免结算已删除的节点。
		if not _context.is_active():
			return
		if ElectricPeaFlightQuery.can_hit(target):
			_strike(target, start.lerp(finish, contact.x), elapsed)

## 命中 [param target] 后依回执对真正承伤者施加劣化，并在 [param point]、[param elapsed] 反馈。
func _strike(target: Character000Base, point: Vector2, elapsed: float) -> void:
	var receipt: Dictionary = {} # 原生护甲、代伤与防御保持正常，劣化在本次扣血之后施加。
	target.be_attacked_bullet(DAMAGE, BulletRegistry.AttackMode.Norm, true, false, 0, -1, receipt, _hit_scope)
	if not _context.is_active() or int(receipt.get("actual_loss", 0)) <= 0:
		return
	if is_instance_valid(target):
		_contacted[target.get_instance_id()] = true
	var recipient: Variant = receipt.get("recipient") # 可能是拦截命中的保护者，也可能已死亡。
	if is_instance_valid(recipient):
		_contacted[recipient.get_instance_id()] = true
		if CharacterSkillTargetQuery.can_receive_negative(_context, recipient):
			recipient.hp_component.apply_degradation(DEGRADATION)
	_visual.impact(point, elapsed)
	if elapsed >= _next_hit_cue:
		_next_hit_cue = elapsed + 0.095
		_play_sound(HIT_SOUND, -4.0, 0.91 + fmod(elapsed * 0.9, 0.17))
		EventBus.push_event(MainGameCamera.SHAKE_EVENT, [Vector2(3.0, 2.25), 0.12, 29.0])

## [param stream] 随本次冲锋回收；[param gain] 为分贝，[param pitch] 是播放速率和音高倍率。
func _play_sound(stream: AudioStream, gain: float, pitch: float) -> void:
	var player := AudioStreamPlayer.new() # 数量受出击分组、命中限流与音轨长度约束。
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	player.stream = stream
	player.bus = SoundManager.spatial_sfx_bus()
	player.volume_db = gain
	player.pitch_scale = pitch
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
