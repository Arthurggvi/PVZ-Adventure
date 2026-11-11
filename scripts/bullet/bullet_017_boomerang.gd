## 回旋镖花瓣。首次命中后检查前方剩余目标，按原版减速距离折返。
extends Bullet000NormBase
class_name Bullet017Boomerang

## 正常接回时通知植株播放接镖动作；植株消失时飞至左边界后释放。
signal returned

## 去程可命中的目标上限，返程通过排除去程超额的目标保留穿透范围。
const HIT_LIMIT := 3
## 原版初速范围，单位为像素每秒。
const FLIGHT_SPEED := Vector2(400.0, 450.0)
## 距离折返点 75 像素内减速或加速，最低维持初速的 10%。
const TURN_RADIUS := 75.0
## 折返阶段的最低速度倍率。
const MIN_SPEED_FACTOR := 0.1
## 同一行前方查询最多接收的受击形状数，覆盖密集出怪时的多个受击框。
const LOOKAHEAD_RESULT_LIMIT := 256

## 翻转飞行方向后为 true，直至接回或离场。
var _returning := false
## 本段飞行已命中的敌人实例 ID，避免跨帧重叠重复扣血。
var _hit_ids: Dictionary[int, bool] = {}
## 去程耗尽命中额度时已在前方的超额目标，返程也跳过这些实例。
var _excluded_ids: Dictionary[int, bool] = {}
## 发射植株；移除后回旋镖仍沿原行飞行。
var _thrower: Plant000Base
## 战斗视口左右边缘，使用全局 X 坐标。
var _field_edges: Vector2
## 已决定的折返位置，使用全局 X；INF 表示还在向前飞行并继续判定目标。
var _turn_x := INF
## 飞行逻辑使用 64 位全局 X；节点坐标会舍入，只用于显示和碰撞。
var _flight_x: float
## 屋顶关卡的坡面，平地为空。
var _slope: MainGameSlope
## 扣除屋顶坡面高度后的发射 Y，保持相对地面的飞行高度。
var _level_y: float
## 发射点的全局 X，植株存活时在此接回花瓣。
var _launch_x: float
## 去程前方的扫描区域，宽度和位置随当前进度更新。
var _lookahead_shape := RectangleShape2D.new()
## 复用实际受击层，只在达到首次命中且还未进入折返时查询。
var _lookahead_query := PhysicsShapeQueryParameters2D.new()


## 入树前记录 [param thrower]、世界坐标下的 [param field_edges] 与可空的 [param slope]。
func configure_flight(thrower: Plant000Base, field_edges: Vector2, slope: MainGameSlope) -> void:
	_thrower = thrower
	_field_edges = field_edges
	_slope = slope


## 初始化飞行起点与随机初速，命中由物理帧统一处理以保证同帧排序。
func _ready() -> void:
	super()
	area_2d_attack.area_entered.disconnect(_on_area_2d_attack_area_entered)
	speed = randf_range(FLIGHT_SPEED.x, FLIGHT_SPEED.y)
	_flight_x = global_position.x
	_launch_x = _flight_x
	_level_y = global_position.y - _slope_height(_launch_x)
	_lookahead_query.shape = _lookahead_shape
	_lookahead_query.collision_mask = area_2d_attack.collision_mask
	_lookahead_query.collide_with_areas = true
	_lookahead_query.collide_with_bodies = false


## [param delta] 为当前物理帧的游戏秒数，推进去程、减速掉头和返程。
func _physics_process(delta: float) -> void:
	_hit_overlaps()
	if not _returning:
		_choose_turn_point()
		if _flight_x >= _turn_x:
			_returning = true
			_hit_ids.clear()
			_hit_boss_ids.clear()
			curr_attack_num = 0
	# 原版在折返半径内从 10% 至 100% 线性变化，折返点直接翻转速度。
	var turn_distance_ratio: float = minf(absf(_flight_x - _turn_x) / TURN_RADIUS, 1.0)
	var speed_factor: float = lerpf(MIN_SPEED_FACTOR, 1.0, turn_distance_ratio)
	# 返程中若原植株已离场，飞过原发射点直到视野左缘。
	var can_catch: bool = is_instance_valid(_thrower) and not _thrower.is_death \
		and not _thrower.is_queued_for_deletion()
	var return_end: float = _launch_x if can_catch else _field_edges.x # 本次返程的终点。
	if _returning and _flight_x <= return_end:
		queue_free()
		if can_catch:
			returned.emit()
		return
	# 步长在转向点和接回点截断，避免越过端点。
	var travel: float = speed * speed_factor * delta
	_flight_x = maxf(return_end, _flight_x - travel) if _returning \
		else minf(_turn_x, _flight_x + travel)
	global_position = Vector2(_flight_x, _level_y + _slope_height(_flight_x))


## 首次命中后找同行前方还可命中的目标。达到上限时记住超额目标，再推进一个减速半径。
func _choose_turn_point() -> void:
	if _turn_x != INF:
		return
	# 已接近战场右缘时直接使用右缘作为折返点，不再向场外查询目标。
	var ahead_distance: float = _field_edges.y - _flight_x
	if ahead_distance <= TURN_RADIUS:
		_turn_x = maxf(_flight_x, _field_edges.y)
		return
	if _hit_ids.is_empty():
		return
	# 扫描沿用原版 10 像素的弹道带；屋顶加入同一行斜坡的高度差。
	var edge_y: float = _level_y + _slope_height(_field_edges.y)
	_lookahead_shape.size = Vector2(ahead_distance, 10.0 + absf(edge_y - global_position.y))
	_lookahead_query.transform = Transform2D(0.0,
		Vector2(_flight_x + ahead_distance * 0.5, (global_position.y + edge_y) * 0.5))
	# 去程满额时仍扫描一次，记录折返时需要跳过的现存目标。
	var has_reached_limit: bool = _hit_ids.size() >= HIT_LIMIT
	for hit: Dictionary in get_world_2d().direct_space_state.intersect_shape(
			_lookahead_query, LOOKAHEAD_RESULT_LIMIT): # 与前方弹道相交的受击形状。
		# 查询命中的是受击区域，沿用实际碰撞的角色资格和同行判定。
		var area: Area2D = hit["collider"] as Area2D
		var target: Character000Base = area.owner as Character000Base
		if not _can_attack_character(target):
			continue
		# 跳过已经结算过的目标，多个形状共用同一角色 ID。
		var target_id: int = target.get_instance_id()
		if _hit_ids.has(target_id):
			continue
		if not has_reached_limit:
			return
		_excluded_ids[target_id] = true
	_turn_x = _flight_x + TURN_RADIUS


## 按行进方向处理当前重叠的敌人；返程重置去程命中记录并跳过超额目标。
func _hit_overlaps() -> void:
	if not _returning and _hit_ids.size() >= HIT_LIMIT:
		return
	# 同帧重叠的受击框按行进方向排序，优先结算先接触的目标。
	var targets: Array[Area2D] = area_2d_attack.get_overlapping_areas()
	# a、b 为待比较的两个受击框。
	targets.sort_custom(func(a: Area2D, b: Area2D) -> bool:
		return a.global_position.x > b.global_position.x if _returning \
			else a.global_position.x < b.global_position.x)
	for area: Area2D in targets: # 投射物当前接触的受击框。
		# 跳过己方、其他行和已关闭受击的角色。
		var target: Character000Base = area.owner as Character000Base
		if not _can_attack_character(target):
			continue
		# 对同一角色的多个受击框共享一次结算。
		var target_id: int = target.get_instance_id()
		if _hit_ids.has(target_id) or _excluded_ids.has(target_id):
			continue
		_hit_ids[target_id] = true
		attack_once(target)
		if not _returning and _hit_ids.size() >= HIT_LIMIT:
			return


## 对 [param zombie] 按飞行方向结算伤害。去程先打二类防具，返程从背后打到一类防具或本体。
func _attack_zombie(zombie: Zombie000Base) -> void:
	# 复用通用扣血入口；伤害类型只由实际命中的飞行阶段决定。
	var hit_mode: BulletRegistry.AttackMode = BulletRegistry.AttackMode.Real if _returning \
		else BulletRegistry.AttackMode.Norm
	zombie.be_attacked_bullet(attack_value, hit_mode, true, trigger_be_attack_sfx)


## 返回 [param world_x] 对应的屋顶相对高度，平地返回 0。
func _slope_height(world_x: float) -> float:
	return _slope.get_all_slope_y(world_x) if is_instance_valid(_slope) else 0.0
