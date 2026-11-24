## 深蓝明灯：分路浪击退敌人，命中处的震颤随波前结算寒冷。
extends Node2D

## Cut-in 开始收幕时让浪提前在左缘外卷起。
const CutIn = preload("res://scripts/adventure/skills/character_skill_cut_in.gd")
## 每道浪两次发出震颤的最短间隔，单位为战斗秒。
const SHOCK_INTERVAL := 0.3
## 每次接触向刷怪侧移动的格数。
const PUSH_CELLS := 2.0
## 使用明灯的击退时长，单位为战斗秒。
const PUSH_TIME := 0.19
## 震颤施加抗火减速的战斗秒数。
const SLOW_TIME := 4.0
## 每道震颤对同一目标最多添加的冻结值。
const FREEZE_POINTS := 2.0
## 多路同时触发震颤时给水冠和尾迹保留对比度。
const SHOCK_BRIGHTNESS := 0.60

## 分路浪各自追踪命中及触发节拍，不让一条路的密集敌人压掉其他路的震颤。
class WaveContacts:
	## 此浪已经推过的僵尸实例。
	var pushed: Dictionary[int, bool] = {}
	## 上帧仍在浪前的僵尸横坐标，供双方相向移动时计算连续接触。
	var ahead: Dictionary[int, float] = {}
	## 下次允许触发震颤的施放时间，单位为战斗秒。
	var next_shock_at := 0.0

## 本次技能的目标过滤和棋盘身份。
var _context: CharacterSkillContext
## 离开原场景、阶段或轮次时，取消所有尚未完成的浪与震颤。
var _battle: RepeaterShotContext
## 波纹共用这一份战场照明通道。
var _lighting: MingLanternLighting
## 活跃水圈共用的战场折射快照。
var _shock_capture: BackBufferCopy
## 尚未离树的震颤数，最后一道水圈散去时停止读屏。
var _shock_count := 0
## 施放后的战斗秒数，只用于各路触发间隔。
var _elapsed := 0.0
## 初始 Cut-in 等待期间没有子特效；开始出浪后才允许自然回收。
var _launched := false

## 绑定原施放 [param context] 及其可供状态服务使用的 [param battle]。
func _init(context: CharacterSkillContext, battle: RepeaterShotContext) -> void:
	_context = context
	_battle = battle

## 在世界特效之上预留折射顺序，用实际秒把起浪对齐到 Cut-in 退场。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	z_index = 1
	_shock_capture = BackBufferCopy.new()
	_shock_capture.z_index = -1
	_shock_capture.copy_mode = BackBufferCopy.COPY_MODE_DISABLED
	add_child(_shock_capture)
	var lead_in: Tween = create_tween().set_ignore_time_scale(true) # 仅起手随 Cut-in 的实际秒数。
	lead_in.tween_interval(CutIn.EXIT_START)
	lead_in.tween_callback(_launch)

## 用 [param delta] 推进触发时钟；留到最后的水纹及音尾退出后一起回收。
func _process(delta: float) -> void:
	if not _battle.is_active() or (_launched and get_child_count() == 1):
		queue_free()
		return
	_elapsed += delta

## 从每条攻击行左侧放浪，浪冠错峰抬起，水光沿实际地块铺开。
func _launch() -> void:
	if not _context.is_active():
		queue_free()
		return
	_launched = true
	_lighting = MingLanternLighting.for_host(_context.game)
	var board: BoardRuntime = _context.board # 读取起浪时各行实际的世界范围。
	var bounds: Rect2 = BoardQueries.bounds(board.cells()) # 无种植格攻击行仍能用整个棋盘的左右外沿。
	for lane: int in range(board.extent.x): # 以正式攻击行数为准，涵盖陆地和水路。
		var rectangles: Array[Rect2] = [] # 按实格铺水光，保留空洞。
		var field := Rect2() # 用各格世界范围合并出本路浪身尺寸。
		for cell: PlantCell in board.row_cells(lane): # 格子可处于不同平台。
			if not is_instance_valid(cell) or cell.is_queued_for_deletion():
				continue
			var rect: Rect2 = cell.get_global_rect() # 起浪时的格子世界矩形。
			if rect.has_area():
				rectangles.append(rect)
				field = field.merge(rect) if field.has_area() else rect
		if not field.has_area():
			var foot: Vector2 = _context.game.to_global(board.lanes[lane].spawn_position) # 只有刷怪行时，以行的脚点定高度。
			var reference: PlantCell = board.nearest_cell(foot) # 邻近格只提供浪身高度。
			if reference == null:
				continue
			var height: float = reference.get_global_rect().size.y # 与其他行保持同一水面比例。
			field = Rect2(bounds.position.x, foot.y - height, bounds.size.x, height)
		var wave := MingLanternWave.for_lane(self, field, rectangles, true, lane, board.extent.x) # 镜像同一套翻卷和水膜。
		wave.wave_advanced.connect(_on_wave_advanced.bind(lane, WaveContacts.new(), wave))
		add_child(wave)
		_lighting.watch(wave, wave.draw_scene_light)
	var surf := AudioStreamPlayer.new() # 整批只播一道浪声，避免多路叠加盖过鲸鸣。
	surf.bus = &"SFX"
	surf.stream = MingLanternWave.SURF
	surf.volume_db = -8.0
	surf.finished.connect(surf.queue_free)
	add_child(surf)
	surf.play()

## [param previous] 至 [param current] 为本帧浪尖轨迹；[param lane] 和 [param contacts] 只属于 [param wave]。
## 相向移动也按整段轨迹判断，遇到多个目标时仍逐个推动并选最早接触的位置起震颤。
func _on_wave_advanced(previous: float, current: float, lane: int, contacts: WaveContacts, wave: MingLanternWave) -> void:
	if not _context.is_active() or current <= previous or is_queued_for_deletion():
		return
	var rows: Array[Array] = _context.game.zombie_manager.all_zombies_2d # 实时登记可覆盖新入场的敌人。
	var previous_ahead: Dictionary[int, float] = contacts.ahead # 持有上一帧的快照，丢弃已经离场的记录。
	contacts.ahead = {}
	var impact := Vector2.INF # 等到本帧所有接触都处理完再发出一道震颤。
	var earliest: float = INF # 首个接触占本帧时长的比例。
	var can_shock: bool = _elapsed >= contacts.next_shock_at # 冷却内照常推动，跳过震颤。
	for zombie: Zombie000Base in rows[lane]: # 强制水平位移不会更改行索引。
		if not is_instance_valid(zombie) or zombie.lane != lane:
			continue
		var identity: int = zombie.get_instance_id() # 一道浪只处理目标的首次有效接触。
		if contacts.pushed.has(identity):
			continue
		var foot: Vector2 = zombie.global_position # 与明灯按地面脚点接触一致。
		var after: float = foot.x - current # 正数表示脚点仍在浪之前。
		if after > 0.0:
			contacts.ahead[identity] = foot.x
			continue
		var before: float = float(previous_ahead.get(identity, foot.x)) - previous # 首见目标使用当前脚点。
		if before < 0.0 or not CharacterSkillTargetQuery.is_valid_hostile(_context, zombie):
			continue
		contacts.pushed[identity] = true
		var fraction: float = before / (before - after) if before > 0.0 else 0.0 # 线性估算交点发生在本帧的时刻。
		var contact_x: float = lerpf(previous, current, fraction) # 水花和震颤使用同一个交点。
		wave.splash_at(contact_x)
		if can_shock and fraction < earliest:
			earliest = fraction
			impact = Vector2(contact_x, foot.y)
		if is_instance_valid(zombie.move_component):
			var cell: PlantCell = _nearest_cell(foot, lane) # 无种植格的攻击行也使用邻近地块的格距。
			var distance: float = _context.board.local_pitch(cell).x * PUSH_CELLS # 按接触处真实格距计位移。
			if distance > 0.0:
				zombie.move_component.apply_forced_displacement(Vector2(distance, 0.0), PUSH_TIME)
	if impact.is_finite():
		contacts.next_shock_at = _elapsed + SHOCK_INTERVAL
		_spawn_shock(impact, lane)

## 在 [param lane] 优先寻找 [param point] 附近的格子；无种植点时向其他行借取尺寸。
func _nearest_cell(point: Vector2, lane: int) -> PlantCell:
	var board: BoardRuntime = _context.board # 查询接触时即时棋盘几何。
	var cell: PlantCell = board.nearest_cell(point, lane) # 同行最近格。
	return cell if cell != null else board.nearest_cell(point)

## 在 [param impact] 的横向接点以及 [param lane] 的水面高度起震颤，复用原折射、水光和鲸鸣。
func _spawn_shock(impact: Vector2, lane: int) -> void:
	var board: BoardRuntime = _context.board # 以命中时的棋盘几何确定水圈透视。
	var source: PlantCell = _nearest_cell(impact, lane) # 最近格提供高度、格子尺寸以及投光范围。
	if source == null:
		return
	var rect: Rect2 = source.get_global_rect() # 有格攻击行沿用明灯的格心高程。
	if not rect.has_area():
		return
	var surface_y: float = rect.get_center().y if source.row_col.x == lane else impact.y - rect.size.y * 0.45 # 无格行用脚点校准水面。
	var center := Vector2(impact.x, surface_y) # 波心水平坐标保留实际命中位置。
	var lit_cells: Array[Rect2] = [] # 波前经过的实际地块依次照亮。
	var reach: int = MingLanternShockRing.GRID_RADIUS # 复用明灯的五格范围。
	for neighbor: PlantCell in board.neighbors(source, reach): # 捕获当前几何，便于整圈稳定扩散。
		lit_cells.append(neighbor.get_global_rect())
	var ring := MingLanternShockRing.at_contact(self, center, rect.size, lit_cells) # 结算半径和折射前沿共用同一时间轴。
	ring.brightness = SHOCK_BRIGHTNESS
	var touched: Dictionary[int, bool] = {} # 单个水圈只施加一次状态，多次水圈可累积冻结值。
	ring.ring_advanced.connect(_on_ring_advanced.bind(center, ring.extent, lane, touched))
	_shock_count += 1
	_shock_capture.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	ring.tree_exiting.connect(_on_shock_exiting, CONNECT_ONE_SHOT)
	add_child(ring)
	_lighting.watch(ring, ring.draw_scene_light)
	MingLanternShockRing.play_voice(self, center)

## [param progress] 为当前扩散比例；[param center]、[param extent] 与 [param lane] 描述水圈几何。
## [param touched] 记录此圈已结算的身份；控制在水圈抵达敌人脚点时生效。
func _on_ring_advanced(progress: float, center: Vector2, extent: Vector2, lane: int,
		touched: Dictionary[int, bool]) -> void:
	if not _context.is_active() or progress <= 0.0 or is_queued_for_deletion():
		return
	var radius: Vector2 = extent * progress # 原始水面折射的当前椭圆半径。
	var reach: int = MingLanternShockRing.GRID_RADIUS # 从命中路向上下各覆盖两条攻击行。
	var half_width: float = extent.x / MingLanternShockRing.EXTENT_SCALE * (float(reach) + 0.5) # 波心左右各两格半，包含刚被推出棋盘的敌人。
	var rows: Array[Array] = _context.game.zombie_manager.all_zombies_2d # 读取震颤到达时仍在范围里的敌人。
	for row: int in range(maxi(0, lane - reach), mini(rows.size(), lane + reach + 1)): # 场地边缘裁掉无效行。
		for zombie: Zombie000Base in rows[row]: # 减速和冻结值不直接造成伤亡或改变行索引。
			if not is_instance_valid(zombie) or zombie.lane != row:
				continue
			var offset: Vector2 = zombie.global_position - center # 取脚点与波心的世界距离。
			var identity: int = zombie.get_instance_id() # 单个水圈的结算键。
			if touched.has(identity) or absf(offset.x) > half_width or (offset / radius).length_squared() > 1.0:
				continue
			if not CharacterSkillTargetQuery.can_receive_cold(_context, zombie, false):
				continue
			touched[identity] = true
			AdventureDeepCold.apply_to(zombie, _battle, SLOW_TIME, 0.0, AdventureIceShroomCast.ALL_ZOMBIE_STATUSES)
			AdventureFreezeChargeEffect.apply_to(zombie, FREEZE_POINTS, true)

## 最后一个仍可见的水圈退场后关闭共享折射快照。
func _on_shock_exiting() -> void:
	_shock_count -= 1
	if _shock_count == 0 and is_instance_valid(_shock_capture):
		_shock_capture.copy_mode = BackBufferCopy.COPY_MODE_DISABLED
