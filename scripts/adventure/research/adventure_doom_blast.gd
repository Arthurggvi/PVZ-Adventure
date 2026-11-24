## 毁灭菇的首爆与连锁共用原生爆炸、承伤归因和战场生命周期。
extends Node
class_name AdventureDoomBlast

## 三种爆炸各有独立几何和伤害倍率。
enum Kind { MAIN, CROSS, BURST }
## 每段最多处理的目标或爆心数，一次原生扣血保持原子。
const MAX_WORK_PER_FRAME: int = 48
## 一段结算的目标耗时上限，单位为微秒。
const WORK_BUDGET_USEC: int = 5000
## 同一格同时只保留一份焚的原版火浪。
const CROSS_FLAME_NAME: StringName = &"DoomCrossFlame"
## 空的现有爆炸场景，首次实际引爆时加载。
const BURST_SCENE_PATH: String = "res://scenes/fx/cherry_blast.tscn"

## 按击杀时的地面位置安排派生爆炸，无须保留尸体节点。
class Wave:
	## 火焰十字或九宫格爆炸。
	var kind: Kind
	## 致死前的实际世界脚点。
	var origin: Vector2
	## 致死前的真实攻防行。
	var lane: int

## 原场景、棋盘、轮次和攻击加成。
var _battle: RepeaterShotContext
## 先完成基础与出战修饰的普通、僵王伤害。
var _damage: Vector2i
## 两类目标各自的末乘倍率。
var _final_gain: Vector2
## 三种爆炸各自对两类目标的伤害比例。
var _fractions: Dictionary[int, Vector2] = {}
## 惧所施加的脆弱、劣化、恐惧和灼烧。
var _fear: Dictionary
## 原生爆炸可命中的状态和碰撞层位。
var _statuses: int
## 查询原生受击框、设施和梯子的掩码。
var _mask: int
## 当前爆炸冻结的几何候选。
var _targets: Array[Character000Base] = []
## 下一个尚未处理的命中。
var _target_index: int = 0
## 单次爆炸的实际承伤去重与致死前观察。
var _scope: CombatHitScope
## 当前是在结算主爆或哪一种连锁。
var _kind: Kind = Kind.MAIN
## 本击死者致死前的脚点与行，尤其用于代伤接管者。
var _death_origin: Vector2 = Vector2.INF
var _death_lane: int = -1
## 同一来源的连锁内，实际死者只能传播一次。
var _credited: Dictionary[int, bool] = {}
## 已登记的连锁按先入先出消费。
var _waves: Array[Wave] = []
## 下一次尚未选取目标的爆心。
var _wave_index: int = 0
## 同一来源的矩形查询复用形状资源。
var _rect := RectangleShape2D.new()
## 已清理过冰道的横行。
var _scorched_lanes: Dictionary[int, bool] = {}
## 空所用的原生表现资源。
var _burst_scene: PackedScene

## 在 [param battle] 复制 [param bomb] 的原生范围，保存 [param damage]、[param final_gain] 和 [param rules]。
static func begin(battle: RepeaterShotContext, bomb: BombComponentNorm, damage: Vector2i,
		final_gain: Vector2, rules: Dictionary[String, Dictionary]) -> void:
	var blast := AdventureDoomBlast.new() # 由战场持有，原株消耗不使连锁提前失效。
	blast._battle = battle
	blast._damage = damage
	blast._final_gain = final_gain
	blast._statuses = bomb.can_attack_zombie_status
	blast._mask = bomb.area_2d_bomb.collision_mask
	blast._fear = rules.get("doom_fear", {})
	blast._fractions[Kind.MAIN] = Vector2.ONE
	for key: String in ["doom_cross", "doom_burst"]: # 两种派生规则可同时存在。
		if rules.has(key):
			var rule: Dictionary = rules[key] # 比例分别来自书目本身。
			blast._fractions[Kind.CROSS if key == "doom_cross" else Kind.BURST] = Vector2(rule["normal"], rule["boss"])
	battle.game.bombs.add_child(blast)
	var screen: bool = rules.has("doom_screen") # 只有尽以可见战场替换原生首爆区域。
	var areas: Array[Area2D] = blast._screen_areas() if screen else bomb.area_2d_bomb.get_overlapping_areas() # 保留原生碰撞范围。
	blast._begin_wave(Kind.MAIN, areas, battle.lane, -1 if screen else bomb.bomb_lane)
	blast._advance()

## [param _delta] 为物理时间步。正常暂停时保留队列。
func _physics_process(_delta: float) -> void:
	_advance()

## 在原战场有效时继续一段预算，完成当前爆炸后再处理下一个爆心。
func _advance() -> void:
	var started: int = Time.get_ticks_usec() # 实时耗时只决定继续处理的帧。
	for step: int in range(MAX_WORK_PER_FRAME): # 一步为一次查询或一次实际伤害。
		if not _battle.is_active() or (_target_index >= _targets.size() and _wave_index >= _waves.size()):
			set_physics_process(false)
			queue_free()
			return
		if step > 0 and Time.get_ticks_usec() - started >= WORK_BUDGET_USEC:
			return
		if _target_index < _targets.size():
			var target: Variant = _targets[_target_index] # 前一击可能已同步移除或魅惑它。
			_target_index += 1
			if is_instance_valid(target) and CombatExplosion.can_hit_plant_blast(target, -1, -1, _statuses):
				_hit(target)
		else:
			var wave: Wave = _waves[_wave_index] # 爆心来自已冻结的实际死亡位置。
			_wave_index += 1
			_begin_secondary(wave)

## 用 [param areas] 冻结 [param kind] 的候选，从 [param lane] 根据 [param radius] 过滤。
func _begin_wave(kind: Kind, areas: Array[Area2D], lane: int, radius: int) -> void:
	_kind = kind
	_target_index = 0
	_targets = CombatExplosion.plant_blast_targets(areas, lane, radius, _statuses)
	CombatExplosion.clear_plant_blast_ladders(areas, lane, radius)
	_scope = CombatHitScope.new()
	if _fractions.size() > 1:
		_scope.before_death = _remember_death

## [param target] 已通过候选资格，生命组件处理灰烬、代伤、僵王抗性与真实死亡。
func _hit(target: Character000Base) -> void:
	_death_origin = Vector2.INF
	var boss: bool = target is ZB000Base # 普通与僵王使用各自的主爆基准和连锁倍率。
	var context: PlantAttackContext = _battle.attack_context # 出战装备及被动词条依然应用到每次有效命中。
	var base: int = _damage.y if boss else _damage.x # 此时已计入基础增幅和卡片成长。
	var fraction: Vector2 = _fractions[_kind] # x 用于普通敌人，y 用于僵王。
	var gain: float = _final_gain.y * fraction.y if boss else _final_gain.x * fraction.x # 该次爆炸的目标类别倍率。
	var amount: int = roundi((context.modify_damage(base, target) if context != null else base) * gain) # 末乘晚于其他来源修正。
	var casualty: Character000Base = CombatExplosion.hit_plant_blast_target(
		target, amount, true, context.armor_multiplier if context != null else 1.0, _scope)
	if context != null:
		context.resolve_kill(casualty)
	if is_instance_valid(casualty) and _fractions.size() > 1:
		_enqueue_death(casualty)
	if not _fear.is_empty() and is_instance_valid(target) and not target.is_death:
		_apply_fear(target)

## 承伤路由在 [param target] 真正死亡前保存世界脚点和攻击行。
func _remember_death(target: Character000Base) -> void:
	_death_origin = target.global_position
	_death_lane = target.lane

## [param casualty] 的实际击杀在本轮各触发一次所选连锁。后续击杀继续入队。
func _enqueue_death(casualty: Character000Base) -> void:
	var id: int = casualty.get_instance_id() # 区分同一位置的多个真实死者。
	if _credited.has(id):
		return
	_credited[id] = true
	if not _death_origin.is_finite():
		_remember_death(casualty)
	for kind: Kind in [Kind.CROSS, Kind.BURST]: # 同一死者先排辣椒火浪，再排九宫格。
		if _fractions.has(kind):
			var wave := Wave.new() # 两个波次独立去重，允许分别命中同一存活者。
			wave.kind = kind
			wave.origin = _death_origin
			wave.lane = _death_lane
			_waves.append(wave)

## 惧在实际爆炸后对仍存活的 [param target] 施加公共状态，由其原生入口处理免疫。
func _apply_fear(target: Character000Base) -> void:
	var effect := AdventurePlantNegativeEffects.Kind # 复用已经登记的脆弱、劣化、恐惧、灼烧。
	var seconds: float = _fear["seconds"] # 恐惧和灼烧各自维持五秒。
	AdventurePlantNegativeEffects.apply(target, effect.BRITTLENESS, 0, float(_fear["stacks"]))
	AdventurePlantNegativeEffects.apply(target, effect.DEGRADATION, 0, float(_fear["degradation"]))
	AdventurePlantNegativeEffects.apply(target, effect.FEAR, 0, seconds)
	AdventurePlantNegativeEffects.apply(target, effect.BURN, 0, seconds)

## 用战斗画布的实际可见范围选敌，屏外等待入场的僵尸仍需走入画面。
func _screen_areas() -> Array[Area2D]:
	var game: MainGameManager = _battle.game # 战斗相机与界面的坐标不是同一画布。
	var view: Rect2 = game.get_viewport_rect() # 当前视口真实大小。
	_rect.size = view.size
	var canvas_to_world: Transform2D = game.get_canvas_transform().affine_inverse() # 保留相机缩放和变换。
	return CombatExplosion.query_shape(game.get_world_2d().direct_space_state, _rect,
		canvas_to_world * Transform2D(0.0, view.get_center()), _mask, true)

## 从 [param wave] 的原死者落点求区域。棋盘空洞中仍保留该位置。
func _begin_secondary(wave: Wave) -> void:
	var board: BoardRuntime = _battle.board # 拓扑不变时读取当前活动地块和平台世界变换。
	var cell: PlantCell = board.cell_at_ground_point(wave.origin, wave.lane) # 确切命中才使用逻辑行列。
	var nearest: PlantCell = cell if cell != null else board.nearest_cell(wave.origin, wave.lane) # 盘外只取比例。
	var pitch: Vector2 = board.local_pitch(nearest).max(Vector2.ONE) # 真实行列间距，单位为世界像素。
	if wave.lane < 0 and nearest != null:
		wave.lane = nearest.combat_lane
	if wave.kind == Kind.CROSS:
		_begin_cross(wave, cell, pitch)
	else:
		_begin_burst(wave, cell, pitch)

## [param wave] 的实际横行和纵列合并成一次伤害。[param origin] 缺失时按 [param pitch] 取物理列宽。
func _begin_cross(wave: Wave, origin: PlantCell, pitch: Vector2) -> void:
	var board: BoardRuntime = _battle.board # 横臂使用实际攻防行，纵臂使用逻辑列。
	var row: Array[PlantCell] = board.row_cells(wave.lane) # 原生行完整进入火焰横臂。
	var grid: Array[PlantCell] = board.cells() # 列及战场边界共用同一份地块索引。
	var column: Array[PlantCell] = [] # 属于火焰纵臂的实际地块。
	for cell: PlantCell in grid: # 离格死亡时由实际脚点横坐标选择列。
		if origin != null:
			if cell.row_col.y == origin.row_col.y and cell.board_definition.surface_id == origin.board_definition.surface_id:
				column.append(cell)
		elif absf(cell.get_global_rect().get_center().x - wave.origin.x) < pitch.x * 0.5:
			column.append(cell)
	var field: Rect2 = BoardQueries.bounds(grid) # 让 Boss 的真实受击框也能命中所在横行。
	var row_rect: Rect2 = BoardQueries.bounds(row) # 使用当前行的世界高度。
	var areas: Array[Area2D] = _rect_areas(Rect2(field.position.x, row_rect.position.y, field.size.x, row_rect.size.y))
	areas.append_array(_rect_areas(BoardQueries.bounds(column)))
	_begin_wave(Kind.CROSS, areas, wave.lane, -1)
	_retain_grid_targets(column, wave.lane)
	_append_row_targets(wave.lane)
	if wave.lane >= 0 and wave.lane < _battle.game.zombie_manager.all_ice_roads.size() and not _scorched_lanes.has(wave.lane):
		_scorched_lanes[wave.lane] = true
		EventBus.push_event("jalapeno_bomb_item_lane", [wave.lane])
	_show_cross(row, column, origin.row_col.y if origin != null else 0)

## 原生辣椒也会命中 [param lane] 中尚未踏入地块的已登记敌人。
func _append_row_targets(lane: int) -> void:
	var rows: Array[Array] = _battle.game.zombie_manager.all_zombies_2d # 只补本行，不重新扫描整个战场。
	if lane < 0 or lane >= rows.size():
		return
	var included: Dictionary[int, bool] = {} # 横臂和纵臂交叉点保留一次命中。
	for target: Character000Base in _targets: # 初始候选可能已在物理查询中出现。
		included[target.get_instance_id()] = true
	for zombie: Zombie000Base in rows[lane]: # 行内原生范围也包含离格敌人。
		if CombatExplosion.can_hit_plant_blast(zombie, lane, 0, _statuses) and not included.has(zombie.get_instance_id()):
			_targets.append(zombie)

## 在 [param row] 和 [param column] 播放原辣椒火浪。[param origin_column] 为表现起点。
func _show_cross(row: Array[PlantCell], column: Array[PlantCell], origin_column: int) -> void:
	var cells: Array[PlantCell] = row.duplicate() # 交点也通过同格现存火焰去重。
	cells.append_array(column)
	var started: bool = false # 有实际新火焰才播放原生辣椒音效。
	for cell: PlantCell in cells: # 表现密度与每次攻击伤害完全独立。
		if not is_instance_valid(cell) or cell.is_queued_for_deletion() or cell.has_node(NodePath(CROSS_FLAME_NAME)):
			continue
		JalapenoFireVisual.spawn_cell(cell, origin_column).name = CROSS_FLAME_NAME
		started = true
	if started:
		SoundManager.play_character_SFX(&"Jalapeno")

## [param wave] 从 [param origin] 的实际邻接取九宫格。缺格时按 [param pitch] 测量周围三格。
func _begin_burst(wave: Wave, origin: PlantCell, pitch: Vector2) -> void:
	var bounds: Rect2 = Rect2(wave.origin - Vector2(1.5 * pitch.x, 2.0 * pitch.y), pitch * 3.0) # 不把盘外爆心吸附到内场。
	var cells: Array[PlantCell] = [] # 逻辑九宫格只包含同平台的实际邻格。
	if origin != null:
		for cell: PlantCell in _battle.board.neighbors(origin, 1): # 显式拓扑可能连接不相邻的格子。
			if cell.board_definition.surface_id == origin.board_definition.surface_id \
					and absi(cell.row_col.x - origin.row_col.x) <= 1 and absi(cell.row_col.y - origin.row_col.y) <= 1:
				cells.append(cell)
		bounds = BoardQueries.bounds(cells)
	_begin_wave(Kind.BURST, _rect_areas(bounds), wave.lane, 1 if wave.lane >= 0 else -1)
	if origin != null:
		_retain_grid_targets(cells)
	_show_burst(wave.origin + Vector2(0, -30))

## 普通僵尸按真实脚点属于 [param cells] 才命中，横臂额外保留 [param whole_lane]。
## 僵王可跨行，仍按原生世界受击框识别；防止普通僵尸的受击框探入相邻格而串波。
func _retain_grid_targets(cells: Array[PlantCell], whole_lane: int = -1) -> void:
	var accepted: Array[Character000Base] = [] # 顺序沿用首次碰撞，不影响同波保护者选择。
	for target: Character000Base in _targets: # 只进一步收紧普通僵尸的实际行列。
		if not is_instance_valid(target):
			continue
		if not target is Zombie000Base or (whole_lane >= 0 and target.lane == whole_lane) \
				or BoardQueries.ground_cell_from(_battle.board, target.global_position, target.lane, cells) != null:
			accepted.append(target)
	_targets = accepted

## 查询 [param bounds] 内开放的受击区，连锁入口复用本轮矩形形状。
func _rect_areas(bounds: Rect2) -> Array[Area2D]:
	if not bounds.has_area():
		return []
	_rect.size = bounds.size
	return CombatExplosion.query_shape(_battle.game.get_world_2d().direct_space_state, _rect,
		Transform2D(0.0, bounds.get_center()), _mask, true)

## 在 [param point] 播放现有爆炸效果，表现走全场统一额度。
func _show_burst(point: Vector2) -> void:
	var game: MainGameManager = _battle.game # 与其他炸弹共享表现额度和挂载层。
	if not game.blast_fx_budget.can_start(StringName(BURST_SCENE_PATH), point):
		return
	if _burst_scene == null:
		_burst_scene = load(BURST_SCENE_PATH) as PackedScene
	var blast := _burst_scene.instantiate() as BombEffectCherryBomb # 复用小型弹爆表现模式。
	blast.small_burst = true
	game.bombs.add_child(blast)
	blast.global_position = point
	blast.activate_bomb_effect()
