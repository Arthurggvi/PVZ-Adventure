## 同一战场的卷心菜特殊落点。多发同帧共用脚点索引和一张短效画布。
extends Node2D

## 一颗炮弹可以保存多个独立触发的词条。
enum Payload { GOLD = 1, HELL = 2, HOMERUN = 4, BLACK = 8 }
## 黑菜地爆的基础伤害与僵王实际承伤上限。
const BLACK_DAMAGE: int = 600
## 在僵王易伤等结算之后限制本次爆炸。
const BOSS_CAP: int = 300
## 同时保留的落点画面上限，逻辑伤害独立结算。
const VISUAL_LIMIT: int = 48
## 单步允许的受击工作量与时间预算，实际受击仍保留原先的顺序。
const TARGET_BUDGET: int = 160
## 即使有等阶回调，下一批目标也不得继续占满整个物理步。
const TARGET_BUDGET_USEC: int = 2300

## 从原生碰撞或弧线终点冻结一次特殊落点。
class Impact:
	## 原回合、伤害修正和击杀归因。
	var shot: RepeaterShotContext
	## 直接接触的受击者，落空时为空。
	var direct: Character000Base
	## 所属行的实际脚点。
	var foot: Vector2
	## 敌人所在行，空中相交时仍用真实落点行。
	var row: int
	## 已应用三倍基础和卡面加成后的普通投弹伤害。
	var base_damage: int
	## 此弹实际生效的特殊词条。
	var flags: int
	## 200%只为特殊弹增加范围伤害。
	var splash: bool
	## 原生卷心菜可攻击的僵尸状态掩码。
	var statuses: int

## 图形只保存短期坐标和颜色，不延长弹体或目标寿命。
class Burst:
	## 真实世界脚点转换后的画布坐标。
	var point: Vector2
	## 主色与内圈高光。
	var tint: Color
	## 椭圆按实际格距和词条区分轻重。
	var size: Vector2
	## 已经过的游戏秒数。
	var age: float = 0
	## 退出画面的游戏秒数。
	var duration: float
	## 黑菜的深色冲击轮廓。
	var heavy: bool

## 着地时锁定的目标，极密战场才分步消化。
class Work:
	## 冻结的投弹快照。
	var impact: Impact
	## 已捕获的共享范围候选，避免多发复制同一批密集目标。
	var targets: Array[Character000Base] = []
	## 一格金菜的目标集合。
	var inner: Dictionary[int, bool]
	## 原本的真实直击实体即使退场也保留其身份。
	var direct_id: int = 0
	## 原生代伤跨物理步也必须避免重复扣血。
	var scope: CombatHitScope
	## 在本发捕获所有候选后冻结的溅射值。
	var spread_damage: int
	## 下一个范围候选，负一表示先结算直击。
	var cursor: int = 0

## 等待物理碰撞通知结束的落点，不引用弹体节点。
var _pending: Array[Impact] = []
## 已经安排同批结算时不重复排延迟调用。
var _scheduled: bool = false
## 正在处理的批次，空闲时关闭物理处理。
var _work: Array[Work] = []
## 已完成的批次索引，直到整队消费后一起清理。
var _work_head: int = 0
## 同物理步按棋格地址复用真正站在其中的普通僵尸。
var _by_cell: Dictionary[Vector2i, Array] = {}
## 上一次实际取样的物理步。
var _grid_frame: int = -1
## 当前帧中心格和范围相同的爆炸共用候选，保留已经排队批次的旧快照。
var _footprints: Dictionary[Vector3i, Dictionary] = {}
## 僵王用真实受击盒补齐跨行几何，普通棋格无需做物理查询。
var _boss_query := RectangleShape2D.new()
## 仅在落点表现活跃时更新。
var _bursts: Array[Burst] = []
## 暗爆声音节流使用同一物理时钟。
var _next_boom: int = 0

## [param game] 的弹体容器按需创建一次落点运行时。
static func for_battle(game: MainGameManager) -> Node2D:
	var runtime := game.bullets.get_node_or_null(^"CabbageLandings") as Node2D # 只拥有当前战场寿命。
	if runtime == null:
		runtime = (load("res://scripts/adventure/research/cabbage_landing.gd") as Script).new()
		runtime.name = "CabbageLandings"
		runtime.z_as_relative = false
		runtime.z_index = 151
		game.bullets.add_child(runtime)
	return runtime

## 延迟实例化后先休眠，只有使用画布时需要渲染更新。
func _ready() -> void:
	set_process(false)
	set_physics_process(false)

## [param target] 必须仍属于可攻击阵营和状态 [param statuses]。
static func can_hit(target: Character000Base, statuses: int) -> bool:
	return CombatExplosion.can_hit_plant_blast(target, -1, -1, statuses) \
		and not (target is Zombie000Base and target.retiring_from_battle)

## [param shot] 提供棋盘。[param target] 有真实脚点时优先取用，否则从 [param x] 和 [param row] 投影。
static func foot_at(shot: RepeaterShotContext, target: Character000Base, x: float, row: int) -> Vector2:
	if is_instance_valid(target) and target is Zombie000Base:
		return target.global_position
	var rows: Array = shot.game.zombie_manager.all_zombie_rows # 敌人离场及多行僵王使用该炮弹锁定的行。
	var baseline: Vector2 = rows[row].zombie_create_position.global_position if row >= 0 and row < rows.size() else Vector2(x, 0) # 原生行基线。
	var cell: PlantCell = shot.board.nearest_cell(Vector2(x, baseline.y), row) # 从真实地块采样高低差。
	return Vector2(x, cell.get_spawn_global_position().y if cell != null else baseline.y)

## [param flags] 决定颜色。组合弹的外层以黑、红、金顺序突出最强的伤害形态。
static func tint_for(flags: int) -> Color:
	if flags & Payload.BLACK:
		return Color(0.76, 0.47, 0.94)
	if flags & Payload.HELL:
		return Color(1.0, 0.33, 0.20)
	if flags & Payload.GOLD:
		return Color(1.0, 0.78, 0.20)
	return Color(0.69, 0.99, 0.31)

## [param impact] 只记录一次，范围查询和新增状态节点统一推迟到安全时点。
func submit(impact: Impact) -> void:
	_pending.append(impact)
	if not _scheduled:
		_scheduled = true
		_flush.call_deferred()

## 消费当前批次，后续重入提交会安排自己的批次。
func _flush() -> void:
	var batch: Array[Impact] = _pending # 结算往往同步触发场景和角色状态变化。
	_pending = []
	_scheduled = false
	for impact: Impact in batch: # 已经切换轮次或离开场景的弹不再生效。
		if impact.shot.is_active():
			_prepare(impact)
	if not is_physics_processing():
		_drain()

## 只在需要范围命中的第一个落点更新 [param shot] 的棋格索引。
func _refresh_grid(shot: RepeaterShotContext) -> void:
	var frame: int = Engine.get_physics_frames() # 同帧数十颗落地仍只扫描一次登记表。
	if _grid_frame == frame:
		return
	_grid_frame = frame
	_by_cell.clear()
	_footprints.clear()
	for target: Zombie000Base in shot.game.zombie_manager.all_zombies_1d: # 只索引仍然在棋盘内的敌对实体。
		if not is_instance_valid(target) or not can_hit(target, 31):
			continue
		var cell: PlantCell = shot.board.cell_at_ground_point(target.global_position, target.lane) # 使用脚点处理浮台和空洞。
		if cell != null:
			if not _by_cell.has(cell.row_col):
				_by_cell[cell.row_col] = []
			_by_cell[cell.row_col].append(target)

## 为 [param impact] 在落地时捕获候选和伤害值，预算跨帧时仍沿用原目标。
func _prepare(impact: Impact) -> void:
	var shot: RepeaterShotContext = impact.shot # 即使原株已被铲除仍能落地。
	var black: bool = (impact.flags & Payload.BLACK) != 0 # 黑菜按落点绝对爆伤结算。
	var gold: bool = (impact.flags & Payload.GOLD) != 0 # 金菜对正中心格提供双倍伤害。
	var giant: bool = (impact.flags & Payload.HOMERUN) != 0 # 巨菜的抛飞与伤害独立。
	var square: bool = black or giant or impact.splash # 只有正中心时跳过八格查询。
	var center: PlantCell = shot.board.cell_at_ground_point(impact.foot, impact.row) if gold or square else null # 空洞及盘外不吸附。
	var item := Work.new() # 同一颗卷心菜的所有伤害共用实际承伤者资格。
	item.impact = impact
	item.scope = CombatHitScope.new()
	item.scope.boss_damage_cap = BOSS_CAP if black else -1
	item.inner = {}
	if is_instance_valid(impact.direct) and can_hit(impact.direct, impact.statuses):
		item.direct_id = impact.direct.get_instance_id()
		item.cursor = -1
	if center != null:
		var footprint: Dictionary = _area_for(impact, center, square) # 一格金菜和三格溅射读取同一帧坐标。
		item.inner = footprint["inner"]
		item.targets = footprint["members"]
		if impact.splash:
			var recipients: int = _splash_count(footprint, item.direct_id, impact.statuses, gold) # 间接目标不重复消费直击。
			item.spread_damage = mini(int(float(impact.base_damage) / 3.0), int(float(impact.base_damage) / maxi(1, recipients)))
	if item.direct_id != 0 or not item.targets.is_empty():
		_work.append(item)
	_burst_at(impact, center, square)

## [param _delta] 只提供下一步执行机会，目标在着地时已经捕获。
func _physics_process(_delta: float) -> void:
	_drain()

## 正常落地当帧结算，极端同帧爆炸按受击次数和时间预算继续。
func _drain() -> void:
	var start: int = Time.get_ticks_usec() # 单个命中不被中断，有等阶回调时下一名顺延。
	var processed: int = 0 # 同时计算被跳过的旧目标，防止大量无效项阻塞一帧。
	while _work_head < _work.size() and processed < TARGET_BUDGET:
		if processed > 0 and Time.get_ticks_usec() - start >= TARGET_BUDGET_USEC:
			break
		var item: Work = _work[_work_head] # 每个卷心菜内部保持碰撞原顺序。
		if not item.impact.shot.is_active() or item.cursor == item.targets.size():
			_work[_work_head] = null
			_work_head += 1
		else:
			var direct: bool = item.cursor < 0 # 直击优先消费本次实际承伤资格。
			var target: Variant = item.impact.direct if direct else item.targets[item.cursor] # 击杀或魅惑后索引可能失效。
			item.cursor += 1
			if is_instance_valid(target) and (direct or target.get_instance_id() != item.direct_id) \
					and can_hit(target, item.impact.statuses):
				_apply(item, target)
		processed += 1
	if _work_head == _work.size():
		_work.clear()
		_work_head = 0
	elif _work_head >= 256 and _work_head * 2 >= _work.size():
		_work = _work.slice(_work_head)
		_work_head = 0
	set_physics_process(not _work.is_empty())

## [param item] 已固定范围和单发资格，[param target] 是下一名实际命中的角色。
func _apply(item: Work, target: Character000Base) -> void:
	var impact: Impact = item.impact # 用着地快照判定形态。
	var black: bool = (impact.flags & Payload.BLACK) != 0 # 黑爆替代同弹同目标的伤害。
	var gold: bool = (impact.flags & Payload.GOLD) != 0 # 双倍适用于中心及直击。
	var id: int = target.get_instance_id() # 直击实例在跨帧后仍可识别。
	var direct: bool = id == item.direct_id # 炎弹附着于直击真实接收者。
	var core: bool = direct or (gold and item.inner.has(id)) # 中心不重复收溅射。
	var damage: int = BLACK_DAMAGE if black else (impact.base_damage * (2 if gold else 1) if core else item.spread_damage) # 同一发重叠伤害只结算一次。
	if damage > 0 or (direct and (impact.flags & Payload.HELL) != 0):
		_hit(impact, target, damage, black or not core, direct, item.scope)
	if (impact.flags & Payload.HOMERUN) != 0 and is_instance_valid(target) and target is Zombie000Base and not target.is_death:
		_launch_target(impact.shot, target)

## [param impact] 同一物理步且命中 [param center] 相同范围 [param square] 时只收集一份格内对象。
func _area_for(impact: Impact, center: PlantCell, square: bool) -> Dictionary:
	_refresh_grid(impact.shot)
	var key := Vector3i(center.row_col.x, center.row_col.y, int(square)) # 拓扑键只在当前帧有效。
	if not _footprints.has(key):
		var targets: Dictionary[int, Character000Base] = {} # 原生实体可有多个受击区。
		var inner: Dictionary[int, bool] = {} # 真实一格命中。
		_collect_area(impact, center, square, targets, inner)
		var members: Array[Character000Base] = [] # 同范围后续卷心菜共享实体数组。
		members.assign(targets.values())
		_footprints[key] = {"targets": targets, "inner": inner, "members": members, "splash_counts": {}}
	return _footprints[key]

## [param footprint] 兼容 [param statuses] 的候选数；扣除 [param primary] 和 [param gold] 中心格。
func _splash_count(footprint: Dictionary, primary: int, statuses: int, gold: bool) -> int:
	var cache: Dictionary = footprint["splash_counts"] # 同帧同范围同掩码只遍历一次溅射对象。
	var key := Vector2i(statuses, int(gold)) # 金弹已经伤到中心格，不与外圈分摊。
	var entities: Dictionary = footprint["targets"] # 数字候选 ID 也能核对直击是否处在外圈。
	var inner: Dictionary = footprint["inner"] # 真实一格集合。
	if not cache.has(key):
		var count: int = 0 # 只统计能实际受效的目标。
		for id: int in entities: # 可碰撞的脚点不保证同状态可受伤。
			var target: Variant = entities[id] # 同帧已有其他爆炸可能移除了它。
			if (not gold or not inner.has(id)) and is_instance_valid(target) and can_hit(target, statuses):
				count += 1
		cache[key] = count
	var direct: Variant = entities.get(primary) # 可能未落在当前真实范围内。
	return int(cache[key]) - int(is_instance_valid(direct) and (not gold or not inner.has(primary)) and can_hit(direct, statuses))

## 使用 [param center] 的实际同平台邻格，将 [param impact] 的 [param square] 命中汇入 [param targets] 与 [param inner]。
func _collect_area(impact: Impact, center: PlantCell, square: bool,
		targets: Dictionary[int, Character000Base], inner: Dictionary[int, bool]) -> void:
	var bounds: Rect2 = center.get_global_rect() # 僵王面积采样的外框随棋格移动。
	var cells: Array[PlantCell] = [center] # 显式拓扑仅取实际相邻格。
	if square:
		cells = impact.shot.board.neighbors(center, 1)
	for cell: PlantCell in cells: # 不跨独立平台或超出三列、三行。
		if cell.board_definition.surface_id != center.board_definition.surface_id \
				or absi(cell.row_col.x - center.row_col.x) > 1 or absi(cell.row_col.y - center.row_col.y) > 1:
			continue
		bounds = bounds.merge(cell.get_global_rect())
		for target: Variant in _by_cell.get(cell.row_col, []): # 物理步开始时已采样局部脚点。
			if is_instance_valid(target):
				var id: int = target.get_instance_id() # 本次局部击中最多一次。
				targets[id] = target
				if cell == center:
					inner[id] = true
	if impact.shot.game.zombie_manager.get_living_bosses().is_empty():
		return
	var area: Rect2 = bounds.grow_individual(0.0, bounds.size.y * 0.20, 0.0, 0.0) # 多行僵王仍以真实碰撞为准。
	_boss_query.size = area.size
	var areas: Array[Area2D] = CombatExplosion.query_shape(impact.shot.game.get_world_2d().direct_space_state,
		_boss_query, Transform2D(0.0, area.get_center()), RepeaterFieldQueries.ENEMY_HURT_MASK) # 普通僵尸已由格索引精确筛选。
	for hitbox: Area2D in areas: # 单个僵王可能有多行受击区。
		var boss := hitbox.owner as ZB000Base # 只补齐僵王几何。
		if not is_instance_valid(boss):
			continue
		var id: int = boss.get_instance_id() # 复用全局实体去重。
		targets[id] = boss
		for child: Node in hitbox.get_children(): # 碰撞边界用于判定金色中心格。
			if child is CollisionShape2D and not child.disabled and child.shape != null \
					and center.get_global_rect().intersects(child.global_transform * child.shape.get_rect()):
				inner[id] = true
				break

## 按 [param impact] 的共享来源对 [param target] 结算 [param damage]。[param blast] 走穿透，[param direct] 赋予红菜状态。
## [param scope] 阻止保护者因为代伤重复进入同一击，并维持黑菜僵王上限。
func _hit(impact: Impact, target: Character000Base, damage: int, blast: bool, direct: bool, scope: CombatHitScope) -> void:
	var shot: RepeaterShotContext = impact.shot # 单个目标读取自身距离和伤害上下文。
	var red: bool = direct and (impact.flags & Payload.HELL) != 0 # 红菜只作用于直击。
	var receipt: Dictionary = {} # 核对真实承伤者及受击后的击杀。
	var mode := BulletRegistry.AttackMode.Penetration if blast else BulletRegistry.AttackMode.Real # 沿用原卷心菜真伤模式。
	var amount: int = shot.attack_context.modify_damage(damage, target) if shot.attack_context != null else damage # 黑菜封顶在减伤阶段处理。
	if target is Zombie000Base:
		var armor: float = shot.attack_context.armor_multiplier if shot.attack_context != null else 1.0 # 防具路由仍在组件内。
		shot.on_kill((target.hp_component as HpComponentZombie).apply_hit(amount, mode, true, false, true,
			armor, 0, -1, receipt, scope))
	else:
		target.be_attacked_bullet(amount, mode, true, false, 0, -1, receipt, scope)
		shot.on_kill(receipt.get("casualty") as Character000Base)
	var struck: Variant = receipt.get("recipient") # 保护者替被瞄准者承担直击时也接收红菜效果。
	if red and not receipt.get("duplicate_hit", false) and is_instance_valid(struck):
		AdventurePlantNegativeEffects.apply(struck, AdventurePlantNegativeEffects.Kind.BURN, shot.source_id, 3.0, 0.0,
			{"on_kill": func(casualty: Character000Base) -> void: shot.on_kill(casualty),
				"source_active": func() -> bool: return shot.is_active()})
		AdventurePlantNegativeEffects.apply(struck, AdventurePlantNegativeEffects.Kind.DETONATION_CHARGE, shot.source_id,
			1.5, 0.0, {"on_detonate": RepeaterAreaEffects.detonate.bind(shot)})

## [param shot] 决定 [param zombie] 当地格距。眩晕免疫和抛飞免疫均由原生组件判断。
func _launch_target(shot: RepeaterShotContext, zombie: Zombie000Base) -> void:
	if AdventurePlantNegativeEffects.apply(zombie, AdventurePlantNegativeEffects.Kind.STUN, shot.source_id, 1.0):
		var pitch: Vector2 = shot.pitch_at(zombie.global_position, zombie.lane) # 按每名受击者的一格折算。
		zombie.move_component.apply_forced_displacement(Vector2(pitch.x, 0.0), 0.36, maxf(18.0, pitch.y * 0.44))

## 为 [param impact] 的落点创建同色短效；[param cell] 存在时用真实格距，[param large] 区分范围冲击。
func _burst_at(impact: Impact, cell: PlantCell, large: bool) -> void:
	var heavy: bool = (impact.flags & Payload.BLACK) != 0 # 黑菜爆破声和暗紫冲击。
	if heavy and Engine.get_physics_frames() >= _next_boom and impact.shot.is_same_battle():
		_next_boom = Engine.get_physics_frames() + ceili(Engine.physics_ticks_per_second * 0.14)
		SoundManager.play_character_SFX(&"CherryBomb", self, impact.foot, 2)
	if _bursts.size() >= VISUAL_LIMIT:
		return
	var burst := Burst.new() # 只在共享画布中保留视觉值。
	burst.point = to_local(impact.foot)
	burst.tint = tint_for(impact.flags)
	burst.heavy = heavy
	var pitch: Vector2 = impact.shot.board.local_pitch(cell) if cell != null else impact.shot.cell_pitch # 空落点沿用来源格宽。
	burst.size = pitch * (Vector2(0.93, 0.53) if large else Vector2(0.39, 0.24))
	burst.duration = 0.47 if heavy else (0.39 if large else 0.26)
	_bursts.append(burst)
	set_process(true)

## [param delta] 推进落点视觉，不持有实体或额外计时器。
func _process(delta: float) -> void:
	for index: int in range(_bursts.size() - 1, -1, -1): # 倒序回收短效。
		_bursts[index].age += delta
		if _bursts[index].age >= _bursts[index].duration:
			_bursts.remove_at(index)
	queue_redraw()
	set_process(not _bursts.is_empty())

## 用地面椭圆和碎叶呈现各类投弹落点。
func _draw() -> void:
	for burst: Burst in _bursts: # 最多固定数量的可见落点。
		var t: float = burst.age / burst.duration # 归一化短效时间。
		var remain: float = 1.0 - t # 光屑逐渐淡出。
		var reach: float = 0.25 + (1.0 - remain * remain) * 0.99 # 冲击先快后慢。
		var rim := PackedVector2Array() # 地面椭圆而非圆形光圈。
		for index: int in range(25): # 闭合地纹按固定采样绘制。
			rim.append(burst.point + Vector2.RIGHT.rotated(TAU * index / 24.0) * burst.size * reach)
		if burst.heavy:
			draw_colored_polygon(rim, Color(0.09, 0.04, 0.16, remain * 0.51))
		draw_polyline(rim, Color(burst.tint, remain * 0.92), 2.0 + remain * 2.5, true)
		draw_circle(burst.point - Vector2(0, 11), burst.size.x * (0.13 + 0.31 * t), Color(burst.tint, 0.36 * remain * remain), true, -1, true)
		for index: int in range(9 if burst.heavy else 6): # 固定扇面碎叶，不创建粒子节点。
			var ray: Vector2 = Vector2.RIGHT.rotated(TAU * index / (9.0 if burst.heavy else 6.0)) # 颗粒朝四周散落。
			var tip: Vector2 = burst.point + ray * burst.size * reach - Vector2(0, sin(PI * t) * (15.0 + 4 * (index % 3))) # 抛散后落回真实脚点附近。
			draw_line(tip - Vector2(11, -7) * ray * remain, tip,
				Color(burst.tint.lerp(Color.WHITE, 0.5), remain), 1.6 + 2.6 * remain, true)
