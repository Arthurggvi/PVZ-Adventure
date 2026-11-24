## 六束疯狂光柱共用位移和连续命中判定；每轮同一单位只吃一次效果。
extends RefCounted

## 提交到教堂同一光场的发光柱体和触地音效。
const MadnessEffects = preload("res://scripts/fx/savior_madness_effects.gd")
## 在光柱实际分开后接回收手动画。
const SaviorVisual = preload("res://scripts/character/zombie_boss/savior/savior_visual.gd")
## 柱数与移动秒数。
const PILLARS := 6
## 抬掌后从高处落至地面的战斗秒数。
const DESCENT_SECONDS := 0.36
## 接近原先两倍的移动时长，给玩家时间看清扫过的格子。
const SWEEP_SECONDS := 5.20
## 相邻柱底拉开这段接触半径后才收手，从实际扩散距离判断。
const HAND_RELEASE_SEPARATION := 0.55
## 二阶段在相同的扩散进度开始收手，避免不同位置的轨迹尺度令分身动作错拍。
const SHARED_HAND_RELEASE_PROGRESS := 0.19
## 单轮的初始方向令首束扫向战场左侧。
const START_ANGLE := PI

## 使用真实棋盘及敌人列表。
var _game: MainGameManager
## 柱身、地面光和接触都使用同一组世界中心。
var _effects: MadnessEffects
## 本轮扫过的目标 ID。
var _touched: Dictionary[int, bool] = {}
## 本轮六束共同出发的世界脚点。
var _origin: Vector2
## 柱底的接触半径，按平均格距缩放。
var _radius: float
## 六束飞出整片棋盘后自然消失。
var _travel: float
## 负值时没有活动光柱。
var _elapsed := -1.0
## 上一帧的连续扫掠起点。
var _previous := PackedVector2Array()
## 等待柱底分开的抬掌原画，衔接后立即清空。
var _held_pose: SaviorVisual
## 当前光柱是否属于同一轮分身合演。
var _synchronized := false
## 当前物理帧只允许一次全场震动与地鸣。
var _claim_impact: Callable

## [param game] 提供真实脚点，[param effects] 绘制接触范围，[param claim_impact] 为同帧全场音震。
func _init(game: MainGameManager, effects: MadnessEffects, claim_impact: Callable) -> void:
	_game = game
	_effects = effects
	_claim_impact = claim_impact

## 六束从 [param foot] 出发。[param visual] 持续抬掌，[param synchronized] 时随全组收手。
func start(foot: Node2D, visual: SaviorVisual, synchronized: bool) -> void:
	var origin: Vector2 = foot.global_position # 落地、扫掠和真实光都从同一脚点开始。
	var cells: Array[PlantCell] = _game.board.cells() # 各关卡自行提供格子尺寸。
	var nearest: PlantCell = BoardQueries.nearest(_game.board, origin) # 标定真实地面接触区域。
	if nearest == null:
		visual.resume_prayer()
		return
	var bounds: Rect2 = BoardQueries.bounds(cells) # 确保光柱能扫到实际边缘。
	_origin = origin
	_radius = minf(nearest.size.x, nearest.size.y) * 0.43
	var farthest: Vector2 = (origin - bounds.get_center()).abs() + bounds.size * 0.5 # 每轴取远端，合为最远角。
	_travel = farthest.length() + _radius
	_touched.clear()
	_synchronized = synchronized
	_elapsed = 0.0
	_previous = _positions(0.0)
	_effects.begin(_previous, _radius, bounds, foot, visual)
	_held_pose = visual

## 用 [param delta] 前进一段扫掠，跨帧的接触也由同样的六个中心决定。
func advance(delta: float) -> void:
	if _elapsed < 0.0:
		return
	var previous_time: float = _elapsed # 跨过触地帧时仍先提交落地的接触点。
	var end_time: float = DESCENT_SECONDS + SWEEP_SECONDS # 接触时长从实际落地开始累计。
	_elapsed = minf(end_time, _elapsed + delta)
	if previous_time < DESCENT_SECONDS and _elapsed >= DESCENT_SECONDS:
		_elapsed = DESCENT_SECONDS
		var quake: bool = _claim_impact.call() # 即使领头人离场，其余实际触地的光柱仍可震屏。
		_effects.play_impact(_elapsed, quake)
		if quake:
			_game.camera_2d.shake_once(Vector2(12.0, 21.0), 0.92, 10.8)
			_game.camera_2d.force_update_scroll()
	var descent: float = clampf(_elapsed / DESCENT_SECONDS, 0.0, 1.0) # 柱尖抵达地面前不命中。
	var time_fraction: float = maxf(0.0, _elapsed - DESCENT_SECONDS) / SWEEP_SECONDS # 横移从触地那一拍计时。
	var travel: float = time_fraction * (0.20 + time_fraction * (0.14 + 0.66 * time_fraction)) # 起步轻，后半程的加速度继续增长。
	var points: PackedVector2Array = _positions(travel) # 接触、柱体和真光沿同一条弧线。
	var reach: float = lerpf(0.055, 1.0, pow(descent, 2.85)) # 高处先聚一截细光，最后一段快速撞向脚点。
	var shaft: float = smoothstep(0.025, 0.135, _elapsed) # 下降前半段先聚亮，触地的瞬态由同一材质叠加。
	var ground_light: float = smoothstep(DESCENT_SECONDS - 0.025, DESCENT_SECONDS + 0.035, _elapsed) # 石砖只在柱尖临近时接到照明。
	_effects.set_frame(points, reach, shaft, ground_light, _elapsed)
	if _elapsed >= DESCENT_SECONDS:
		_check_contacts(points)
		if is_instance_valid(_held_pose):
			var separated: bool = time_fraction >= SHARED_HAND_RELEASE_PROGRESS if _synchronized \
				else points[0].distance_to(points[1]) >= _radius * HAND_RELEASE_SEPARATION
			if separated:
				_resume_pose()
	_previous = points
	if _elapsed >= end_time:
		stop()

## 停止本轮接触并启动退光，适用于正常结束或本体退场。
func stop() -> void:
	_elapsed = -1.0
	_resume_pose()
	if is_instance_valid(_effects):
		_effects.finish()

## 接回原画的收手帧，结算停止时也释放仍有效的停留。
func _resume_pose() -> void:
	if is_instance_valid(_held_pose):
		_held_pose.resume_prayer()
	_held_pose = null

## 按 [param points] 的连续运动结算植物和僵尸接触。
func _check_contacts(points: PackedVector2Array) -> void:
	for cell: PlantCell in _game.board.cells(): # 底层与叠种按各自脚点判定。
		for plant: Plant000Base in cell.living_plants(): # 同一个多格实例只被结算一次。
			if _hit(plant, points):
				AdventurePlantNegativeEffects.apply(plant, AdventurePlantNegativeEffects.Kind.STUN, 0, 2.0)
				AdventurePlantNegativeEffects.apply(plant, AdventurePlantNegativeEffects.Kind.DEGRADATION, 0, 0.30)
	for zombie: Zombie000Base in _game.zombie_manager.all_zombies_1d: # 共享已有无敌与速度计时器。
		if is_instance_valid(zombie) and not zombie.is_hypno and _hit(zombie, points):
			AdventureZombieTimedCombatBuff.grant_immunity(zombie, 4.0)
			AdventureZombieTimedSpeedBoost.apply_to(zombie, 2.0, 4.0)

## 返回 [param progress] 时六个等分角的世界点。半径与角度连续展开，进度为零时六束重合。
func _positions(progress: float) -> PackedVector2Array:
	var points := PackedVector2Array() # 固定六个接触中心。
	var reach: float = _travel * progress # 从脚下的同一个地面圆心向外扩散。
	var rotation: float = START_ANGLE - progress * TAU * 0.69 # 六道逐渐弯开的相邻轨道。
	for index: int in range(PILLARS): # 等间隔角度，各束保留各自的轨迹。
		points.append(_origin + Vector2.from_angle(rotation + TAU * index / PILLARS) * reach)
	return points

## 在从上一帧至 [param points] 的接触范围里检查 [param target]，命中时登记一次。
func _hit(target: Character000Base, points: PackedVector2Array) -> bool:
	if target.is_death or target.is_queued_for_deletion():
		return false
	var id: int = target.get_instance_id() # 跨格、跨柱共享去重。
	if _touched.has(id):
		return false
	var foot: Vector2 = target.shadow.global_position # 光柱的地面圆与角色脚点使用同一画布。
	for index: int in range(PILLARS): # 点到前后中心连线的距离防止高速掠过。
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(foot, _previous[index], points[index]) # 连续位移中的最近点。
		if foot.distance_squared_to(closest) <= _radius * _radius:
			_touched[id] = true
			return true
	return false
