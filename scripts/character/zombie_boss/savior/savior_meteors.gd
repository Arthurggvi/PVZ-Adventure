## 绝望的四个血色落点。棋盘邻格给出着地散晕和伤害的共同范围。
extends RefCounted

## 只消费本脚本提交的真实坐标、战斗时间和结算快照。
const Presentation = preload("res://scripts/fx/savior_despair_effects.gd")
## 与真实暖光使用同一处灯罩玻璃标定。
const LightSources = preload("res://scripts/adventure/zombie_church_light_sources.gd")
## 合演的所有流光共用同一声下坠和落地。
const ActionTree = preload("res://scripts/character/zombie_boss/savior/savior_action_tree.gd")
## 没有植物吸收本束时的空快照。
const NO_ABSORBER := Vector4(INF, INF, INF, INF)
## 四束光均从原画出手开始降低，单位战斗秒。
const FALL_SECONDS := 0.85
## 每次祈祷抽取至多四个互异种植位置。
const IMPACTS := 4

## 当前棋盘拓扑。
var _board: BoardRuntime
## 与碰撞使用相同落点的演出。
var _effects: Presentation
## 祈祷时抽定的落点，冲击时读取地块上的真实活体。
var _targets: Array[PlantCell] = []
## 当前落点的世界格心，按出手顺序排列。
var _points := PackedVector2Array()
## 用于确定流光和反光幅度的平均落点格距。
var _span := 1.0
## 负值表示没有正在下坠的流光。
var _elapsed := -1.0
## 返回本物理步的指定声音是否已经由其他演员提交。
var _claim_cue: Callable
## 此次绝望落点的爆炸归属。
var _plant_hit: CombatHitScope

## [param board] 提供格子邻接，[param effects] 绘制对应范围，[param claim_cue] 协调多处共同触地的音效。
## [param caster] 是陨星原始施法者；落点独立于施法者退场。
func _init(board: BoardRuntime, effects: Presentation, claim_cue: Callable, caster: ZB000Base = null) -> void:
	_plant_hit = CombatHitScope.for_plant_attack(caster, CombatHitScope.PlantImpact.EXPLOSION)
	_board = board
	_effects = effects
	_claim_cue = claim_cue

## 用 [param rng] 选择四个落点，返回共用祈祷接口的落点格矩形。
func prepare(rng: RandomNumberGenerator) -> Array[Rect2]:
	_targets.clear()
	var candidates: Array[PlantCell] = _board.cells() # 全场实际登记的种植位置。
	var areas: Array[Rect2] = [] # 只把单格交给祈祷原画。
	for index: int in range(mini(IMPACTS, candidates.size())): # 随机无放回，场地很小时用实际格数。
		var selected: int = rng.randi_range(index, candidates.size() - 1) # 已选位置逐次移动到前缀。
		var cell: PlantCell = candidates[selected] # 实际中心位置。
		candidates[selected] = candidates[index]
		candidates[index] = cell
		_targets.append(cell)
		areas.append(cell.get_global_rect())
	return areas

## 由抬掌帧开始下坠并记下每束的世界格心。
func start() -> void:
	if _targets.is_empty():
		return
	_points.clear()
	var span: float = 0.0 # 各落点当前的平均格子尺寸。
	var valid_targets: Array[PlantCell] = [] # 祷告中撤掉的格子不重新抽签。
	for cell: PlantCell in _targets: # 每束从自己的真实世界格心确定方向。
		if not _valid_target(cell):
			continue
		valid_targets.append(cell)
		_points.append(cell.get_global_rect().get_center())
		span += (cell.size.x + cell.size.y) * 0.5
	_targets = valid_targets
	if _targets.is_empty():
		return
	_span = span / _targets.size()
	_elapsed = 0.0
	_effects.begin(_points, _span, FALL_SECONDS, _claim_cue.call(ActionTree.Cue.DESPAIR_DESCENT))

## [param delta] 推进一轮共同的血色流光，着地后只结算一次。
func advance(delta: float) -> void:
	if _elapsed < 0.0:
		_effects.advance_impact(delta)
		return
	_elapsed += delta
	if _elapsed < FALL_SECONDS and not is_equal_approx(_elapsed, FALL_SECONDS):
		_effects.advance_fall(_elapsed)
		return
	var remainder: float = maxf(0.0, _elapsed - FALL_SECONDS) # 忽略浮点舍入，再把跨步的余量交给战斗时钟。
	_elapsed = -1.0
	var targets: Array[PlantCell] = _targets.duplicate() # 植物亡语可以在第一束命中时杀死救主并清空待命落点。
	var lamps := PackedVector2Array() # 保留实际承伤路灯花的地面脚点，供收束光的投影使用。
	var glass := PackedVector2Array() # 与灯脚同帧捕获灯罩位置，死亡仍可完成收束。
	var hits := PackedInt32Array() # 保留成功触地的原光源编号，撤掉中间格时后续灯也不会串号。
	var areas: Array[Rect2] = [] # 当前作用范围仍由真实邻格决定。
	for index: int in range(targets.size()): # 已着地的各束仍按顺序结算，重叠区域可以承受多束。
		var cell: PlantCell = targets[index] # 上次有效不代表仍留在棋盘。
		if not _valid_target(cell):
			continue
		var neighbors: Array[PlantCell] = BoardQueries.neighbors(_board, cell, 1) # 散晕与威力共用触地时的实际邻格。
		areas.append(BoardQueries.bounds(neighbors))
		var absorbed: Vector4 = _impact(cell, neighbors) # 同一次实际伤害结算只产生一份保护快照。
		lamps.append(Vector2(absorbed.x, absorbed.y))
		glass.append(Vector2(absorbed.z, absorbed.w))
		hits.append(index)
	if is_instance_valid(_effects):
		_effects.impact(hits, areas, lamps, glass, remainder,
			not hits.is_empty() and _claim_cue.call(ActionTree.Cue.DESPAIR_LANDING))

## 中断待命中或刚命中的表现。死亡与关卡退出均走本入口。
func stop() -> void:
	_elapsed = -1.0
	_targets.clear()
	if is_instance_valid(_effects):
		_effects.clear()

## [param cell] 仍是实际登记的种植位时才可以提交视觉和伤害。
func _valid_target(cell: PlantCell) -> bool:
	return is_instance_valid(cell) and not cell.is_queued_for_deletion() and cell.board == _board \
		and _board.cell_by_id(cell.cell_id) == cell

## [param origin] 周围 [param neighbors] 内由最近的路灯花独自吸收；否则所有活体植物承伤。
## 返回路灯花脚点和灯罩世界坐标。没有吸收时各自为 Vector2.INF。
func _impact(origin: PlantCell, neighbors: Array[PlantCell]) -> Vector4:
	var plants: Dictionary[Plant000Base, bool] = {} # 一束流光不会对同一棵多格植物重复扣血。
	var protector: Plant026Plantern # 当前范围内最靠近格心的灯。
	var nearest: float = INF # 到落点的平方距离。
	var center: Vector2 = origin.get_global_rect().get_center() # 与触地红晕的中心相同。
	for cell: PlantCell in neighbors: # 棋盘拓扑自动裁剪边缘。
		for plant: Plant000Base in cell.living_plants(): # 包括同格各层。
			plants[plant] = true
			if plant is Plant026Plantern:
				var distance: float = center.distance_squared_to(cell.get_global_rect().get_center()) # 最近者承担本次坠落。
				if distance < nearest:
					nearest = distance
					protector = plant
	if protector != null:
		var foot: Vector2 = protector.shadow.global_position # 承伤死亡也保留这一帧的世界垂足。
		var glass: Vector2 = protector.lantern_face.to_global(LightSources.LANTERN_GLASS_CENTER) # 复用暖灯的玻璃接缝。
		protector.be_attacked_bullet(100, BulletRegistry.AttackMode.Real, false, false, 0, -1, null, _plant_hit)
		return Vector4(foot.x, foot.y, glass.x, glass.y)
	for plant: Plant000Base in plants: # 某个植株的死亡可能同步移除同格支撑层。
		if is_instance_valid(plant) and not plant.is_death:
			plant.be_attacked_bullet(200, BulletRegistry.AttackMode.Real, false, false, 0, -1, null, _plant_hit)
	return NO_ABSORBER
