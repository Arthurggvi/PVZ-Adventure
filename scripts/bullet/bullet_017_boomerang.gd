## 回旋镖花瓣。去程命中三个目标或抵达视野边缘后折返，每段独立记录命中。
extends Bullet000NormBase
class_name Bullet017Boomerang

## 正常接回时通知植株播放接镖动作；植株消失时飞至左边界后释放。
signal returned

## 花瓣的三个飞行阶段；折返停顿期间不结算命中。
enum Flight { OUTBOUND, TURNING, RETURNING }

## 每个方向可命中的目标上限；同一方向对一个实例至多结算一次。
const HIT_LIMIT := 3
## 原版初速范围，单位为像素每秒。
const FLIGHT_SPEED := Vector2(400.0, 450.0)
## 距离折返点 75 像素内减速或加速，最低维持初速的 10%。
const TURN_RADIUS := 75.0
## 折返阶段的最低速度倍率。
const MIN_SPEED_FACTOR := 0.1
## 开始返程前停顿的游戏秒数。
const TURN_PAUSE := 0.25

## 当前飞行阶段。
var _flight := Flight.OUTBOUND
## 本段飞行已命中的敌人实例 ID，避免跨帧重叠重复扣血。
var _hit_ids: Dictionary[int, bool] = {}
## 发射植株；移除后回旋镖仍沿原行飞行。
var _thrower: Plant000Base
## 战斗视口左右边缘，使用全局 X 坐标。
var _field_edges: Vector2
## 出程目标的全局 X，折返后记录实际掉头点。
var _turn_x: float
## 还需停顿的游戏秒数。
var _turn_remaining := 0.0
## 屋顶关卡的坡面，平地为空。
var _slope: MainGameSlope
## 扣除屋顶坡面高度后的发射 Y，保持相对地面的飞行高度。
var _level_y: float
## 发射点的全局 X，植株存活时在此接回花瓣。
var _launch_x: float


## 记录 [param thrower]、世界坐标下的 [param field_edges] 与可空的 [param slope]，入树前调用。
func configure_flight(thrower: Plant000Base, field_edges: Vector2, slope: MainGameSlope) -> void:
	_thrower = thrower
	_field_edges = field_edges
	_slope = slope


## 初始化飞行起点与随机初速，命中由物理帧统一处理以保证同帧排序。
func _ready() -> void:
	super()
	area_2d_attack.area_entered.disconnect(_on_area_2d_attack_area_entered)
	speed = randf_range(FLIGHT_SPEED.x, FLIGHT_SPEED.y)
	_launch_x = global_position.x
	_turn_x = maxf(_launch_x, _field_edges.y)
	_level_y = global_position.y - _slope_height(_launch_x)


## [param delta] 为当前物理帧的游戏秒数，推进去程、掉头停顿和返程。
func _physics_process(delta: float) -> void:
	if _flight == Flight.TURNING:
		_turn_remaining -= delta
		if _turn_remaining > 0.0:
			return
		_flight = Flight.RETURNING
		_hit_ids.clear()
		_hit_boss_ids.clear()
		curr_attack_num = 0
		# 掉头后重新处理重叠区，确保第三个目标在同一受击框内仍能吃到返程伤害。
	_hit_overlaps()
	if _flight == Flight.OUTBOUND and (_hit_ids.size() >= HIT_LIMIT or global_position.x >= _turn_x):
		_turn_x = global_position.x
		_flight = Flight.TURNING
		_turn_remaining = TURN_PAUSE
		return
	# 出程临近边界减速，返程从实际折返点逐渐恢复速度。
	var speed_factor: float = clampf(absf(global_position.x - _turn_x) / TURN_RADIUS,
		MIN_SPEED_FACTOR, 1.0)
	# 返程中若原植株已离场，飞过原发射点直到视野左缘。
	var can_catch: bool = is_instance_valid(_thrower) and not _thrower.is_death \
		and not _thrower.is_queued_for_deletion()
	var return_end: float = _launch_x if can_catch else _field_edges.x # 本次返程的终点。
	if _flight == Flight.RETURNING and global_position.x <= return_end:
		queue_free()
		if can_catch:
			returned.emit()
		return
	# 步长在转向点和接回点截断，避免越过端点。
	var travel: float = speed * speed_factor * delta
	# 本帧移动后的世界 X。
	var next_x: float = minf(_turn_x, global_position.x + travel) if _flight == Flight.OUTBOUND \
		else maxf(return_end, global_position.x - travel)
	global_position = Vector2(next_x, _level_y + _slope_height(next_x))


## 按行进方向处理当前重叠的敌人，每段最多伤害三个不同实例。
func _hit_overlaps() -> void:
	if _hit_ids.size() >= HIT_LIMIT:
		return
	# 同帧重叠的受击框按行进方向排序，优先结算先接触的目标。
	var targets: Array[Area2D] = area_2d_attack.get_overlapping_areas()
	# a、b 为待比较的两个受击框。
	targets.sort_custom(func(a: Area2D, b: Area2D) -> bool:
		return a.global_position.x < b.global_position.x if _flight == Flight.OUTBOUND \
			else a.global_position.x > b.global_position.x)
	for area: Area2D in targets: # 投射物当前接触的受击框。
		# 跳过己方、其他行和已关闭受击的角色。
		var target: Character000Base = area.owner as Character000Base
		if not _can_attack_character(target):
			continue
		# 对同一角色的多个受击框共享一次结算。
		var target_id: int = target.get_instance_id()
		if _hit_ids.has(target_id):
			continue
		_hit_ids[target_id] = true
		attack_once(target)
		if _hit_ids.size() >= HIT_LIMIT:
			return


## 返回 [param world_x] 对应的屋顶相对高度，平地返回 0。
func _slope_height(world_x: float) -> float:
	return _slope.get_all_slope_y(world_x) if is_instance_valid(_slope) else 0.0
