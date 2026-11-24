## 回旋镖的唯一飞行状态机；去返独立穿透，补投与分裂均由新弹体承担。
extends Bullet000NormBase
class_name Bullet017Boomerang

## 只在原株当前接镖点真实接触时通知一次；先终止自身，再允许植株补投。
signal returned(projectile_id: int, shot: BloomerangShotContext)

## 有限状态；弱镖没有折返或回收奖励的出口。
enum FlightState { OUTBOUND, RETURNING, WEAK, FINISHED }
## 原版初速区间，单位为世界像素每秒。
const FLIGHT_SPEED := Vector2(400.0, 450.0)
## 折返点两侧的加减速距离，单位为世界像素。
const TURN_RADIUS: float = 75.0
## 折返点最低仍有正速度，避免渐近停滞。
const MIN_SPEED_FACTOR: float = 0.1
## 世界坐标舍入允许的端点误差，不扩大受击形状。
const END_EPSILON: float = 0.01

## 发射器注入的唯一新弹工厂；静态 Callable 避免弹体与发射器形成脚本循环依赖。
var projectile_factory: Callable
## 发射时冻结的音色，弱镖沿用同一音色且不依赖母株存活。
var impact_sound_tier: int = 0
## 当前唯一飞行状态，终态不可退出。
var _state: FlightState = FlightState.OUTBOUND
## 单枚弹体的冻结规则，不共享成长计数。
var _shot: BloomerangShotContext
## 原发射实例；失效后仍允许弹体在原战局内完成攻击。
var _thrower: Plant000Base
## 原株的实时枪口；平台移动后不再按旧发射横坐标伪造回收。
var _launch: Marker2D
## 原战场的屋顶高度来源。
var _slope: MainGameSlope
## 扣除屋顶高度后的飞行高度，不跟随已离开的母株跳跃。
var _level_y: float = 0.0
## 逻辑横坐标，避免依赖显示坐标反复累积位移。
var _flight_x: float = 0.0
## 首次命中后确定的折返位置；无限表示继续找前方目标或到屏幕边缘。
var _turn_x: float = INF
## 当前这一程已经命中的角色；折返时清空，成长不清空。
var _hit_ids: Dictionary[int, bool] = {}
## 前方已验证且可命中的受击区弱引用；每帧复核其真实路径，失效才做全量扫描。
var _ahead_area: WeakRef
## 每枚弹独享的连续碰撞查询器。
var _query := BloomerangFlightQuery.new()
## 单枚弹体独享的伤害成长与追猎规则。
var _damage := BloomerangDamage.new()
## 当前帧的可见世界范围，镜头变化时重新读取。
var _screen: Rect2
## 已消耗的有效物理秒数，暂停不计时。
var _elapsed: float = 0.0
## 发射时确定的寿命上界，避免镜头永久同向追随弹体造成泄漏。
var _lifetime: float = 0.0
## 出生的物理帧号，弱镖不会继承母镖该帧尚未走完的路径。
var _birth_frame: int = -1
## 弱镖的出生重叠只检查一次。
var _birth_checked: bool = false

## [param displacement] 同步移动逻辑飞行基线，下个物理步仍沿同一条坡面路径。
func translate_with_board(displacement: Vector2) -> void:
	super(displacement)
	_flight_x += displacement.x
	_level_y += displacement.y
	_turn_x += displacement.x

## 入树前注入 [param shot]、可失效的原实例 [param thrower] 与实时枪口 [param launch]。
func configure_flight(shot: BloomerangShotContext, thrower: Plant000Base, launch: Marker2D) -> void:
	_shot = shot
	_thrower = thrower
	_launch = launch
	_damage.configure(shot)
	attack_validity = shot.is_active
	_slope = shot.game.main_game_slope if is_instance_valid(shot.game.main_game_slope) else null

## 关闭旧信号式命中，所有碰撞只由当前物理路径结算。
func _ready() -> void:
	super()
	if area_2d_attack.area_entered.is_connected(_on_area_2d_attack_area_entered):
		area_2d_attack.area_entered.disconnect(_on_area_2d_attack_area_entered)
	if _shot == null or not is_attack_active():
		_finish(false)
		return
	max_attack_num = -1
	_state = FlightState.WEAK if _shot.is_split else FlightState.OUTBOUND
	impact_resolved.connect(_on_impact_resolved)
	speed = randf_range(FLIGHT_SPEED.x, FLIGHT_SPEED.y) * _shot.flight_multiplier
	_flight_x = global_position.x
	_level_y = global_position.y - BloomerangFlightQuery.height_at(_slope, _flight_x)
	_screen = BloomerangFlightQuery.screen_rect(self)
	_lifetime = maxf(8.0, _screen.size.x * 4.0 / speed + 4.0 * TURN_RADIUS / (speed * MIN_SPEED_FACTOR))
	_birth_frame = Engine.get_physics_frames()

## [param delta] 是游戏物理秒数；无等待、无递归飞行，单帧最多执行一次折返。
func _physics_process(delta: float) -> void:
	if _state == FlightState.FINISHED or is_queued_for_deletion():
		return
	if not is_attack_active():
		_finish(false)
		return
	if get_tree().paused:
		return
	_elapsed += maxf(0.0, delta)
	if _elapsed >= _lifetime:
		_finish(false)
		return
	_screen = BloomerangFlightQuery.screen_rect(self)
	if not is_instance_valid(_slope):
		_slope = null
	direction = Vector2(_travel_sign(), 0.0)
	if _state == FlightState.WEAK and not _birth_checked:
		_birth_checked = true
		_move_segment(global_position)
		if _state == FlightState.FINISHED or Engine.get_physics_frames() == _birth_frame:
			return
	if _state == FlightState.OUTBOUND:
		_choose_turn_point()
		if (_outbound_end() - _flight_x) * _shot.launch_direction <= END_EPSILON:
			_begin_return()
	var factor: float = 1.0 # 弱镖不减速折返；普通镖只在转弯附近加减速。
	if _state != FlightState.WEAK:
		var apex: float = _outbound_end() if _state == FlightState.OUTBOUND else _turn_x # 当前折返点。
		factor = lerpf(MIN_SPEED_FACTOR, 1.0, minf(absf(_flight_x - apex) / TURN_RADIUS, 1.0))
	var next_x: float = _flight_x + _travel_sign() * speed * factor * maxf(0.0, delta) # 本帧目标横坐标。
	if _state == FlightState.OUTBOUND:
		next_x = _clamp_outbound(next_x)
	else:
		var exit_x: float = _screen.end.x + 2.0 * BloomerangFlightQuery.HALF_SIZE \
			if _travel_sign() > 0 else _screen.position.x - 2.0 * BloomerangFlightQuery.HALF_SIZE # 出屏终点。
		next_x = minf(next_x, exit_x) if _travel_sign() > 0 else maxf(next_x, exit_x)
	_advance_to(Vector2(next_x, _level_y + BloomerangFlightQuery.height_at(_slope, next_x)))
	if _state == FlightState.FINISHED:
		return
	if _state == FlightState.OUTBOUND and (_outbound_end() - _flight_x) * _shot.launch_direction <= END_EPSILON:
		_begin_return()
	elif _state != FlightState.OUTBOUND and not _screen.grow(BloomerangFlightQuery.HALF_SIZE).has_point(global_position):
		_finish(false)

## 首次命中后确认前方是否仍有合法目标；同一有效目标只重验形状，不重复扫描整行。
func _choose_turn_point() -> void:
	if is_finite(_turn_x) or _hit_ids.is_empty():
		return
	if _hit_ids.size() < _shot.hit_limit:
		var edge: Vector2 = Vector2(_edge_x(), _level_y + BloomerangFlightQuery.height_at(_slope, _edge_x())) # 屏幕侧缘。
		var points: Array[Vector2] = BloomerangFlightQuery.path_points(global_position, edge, _slope, _level_y) # 与广查一致的坡面折线路径。
		var cached: Area2D = _ahead_area.get_ref() as Area2D if _ahead_area != null else null # 不延长僵尸生命周期。
		if is_instance_valid(cached) and cached.is_inside_tree() and not cached.is_queued_for_deletion() \
				and is_instance_valid(cached.owner) and (cached.collision_layer & area_2d_attack.collision_mask) != 0:
			var cached_target: Character000Base = cached.owner as Character000Base # 同一真实受击角色。
			if cached_target != null and _can_attack_character(cached_target) \
					and not _hit_ids.has(cached_target.get_instance_id()) \
					and _query.area_intersects_path(cached, points):
				return
		_ahead_area = null # 死亡、换行、变阵营或脱离实际弹道，立即回退完整扫描。
		for index: int in range(points.size() - 1): # 每条坡面折线完整检测，顺序不变。
			for area: Area2D in _query.areas(self, points[index], points[index + 1], area_2d_attack.collision_mask):
				if not is_instance_valid(area) or area.is_queued_for_deletion() or not is_instance_valid(area.owner):
					continue
				var target: Character000Base = area.owner as Character000Base # 同行实际受击框对应的角色。
				if _can_attack_character(target) and not _hit_ids.has(target.get_instance_id()):
					_ahead_area = weakref(area)
					return
	_plan_turn()

## 从当前实际位置计算折返上界，绝不越过当帧屏幕边缘。
func _plan_turn() -> void:
	_ahead_area = null
	_turn_x = _flight_x + _shot.launch_direction * TURN_RADIUS
	_turn_x = minf(_turn_x, _edge_x()) if _shot.launch_direction > 0 else maxf(_turn_x, _edge_x())

## 沿 [param finish] 所在的屋顶折线移动；达到本帧新确定的折返点后立即截断剩余路径。
func _advance_to(finish: Vector2) -> void:
	var points: Array[Vector2] = BloomerangFlightQuery.path_points(global_position, finish, _slope, _level_y) # 有限直线段。
	for index: int in range(1, points.size()): # 顺序保持真实行进方向。
		var endpoint: Vector2 = points[index] # 当前坡面线段的结束点。
		if _state == FlightState.OUTBOUND:
			endpoint.x = _clamp_outbound(endpoint.x)
			endpoint.y = _level_y + BloomerangFlightQuery.height_at(_slope, endpoint.x)
		_move_segment(endpoint)
		if _state == FlightState.FINISHED:
			return
		if _state == FlightState.OUTBOUND and (_outbound_end() - _flight_x) * _shot.launch_direction <= END_EPSILON:
			return

## 按 [param finish] 这一真实直线段先后处理接触，分裂位置就是当次实际命中位置。
func _move_segment(finish: Vector2) -> void:
	var start: Vector2 = global_position # 查询起点固定，不受命中回调临时设置的显示位置污染。
	var catch_at: float = _source_contact(start, finish) # 真实母株接触优先截断后面的碰撞。
	var endpoint: Vector2 = start.lerp(finish, catch_at) if is_finite(catch_at) else finish # 本段最多走到接触点。
	if catch_at == 0.0:
		_finish(_state == FlightState.RETURNING)
		return
	if _hit_ids.size() < _shot.hit_limit:
		for contact: Dictionary in _query.contacts(self, start, endpoint, area_2d_attack.collision_mask, _hit_ids): # 已命中者无需重复窄相检测。
			if not is_attack_active():
				_finish(false)
				return
			var reference: Variant = contact.get("area") # 前一个命中可能同步销毁后续受击框。
			if not is_instance_valid(reference):
				continue
			var area: Area2D = reference # 重新确认实际阵营层，拒绝上一命中后已魅惑的目标。
			if area.is_queued_for_deletion() or not is_instance_valid(area.owner) \
					or (area.collision_layer & area_2d_attack.collision_mask) == 0:
				continue
			var target: Character000Base = area.owner as Character000Base # 多形状共享角色实例身份。
			if not _can_attack_character(target) or _hit_ids.has(target.get_instance_id()):
				continue
			var position_at_hit: Vector2 = start.lerp(endpoint, float(contact.fraction)) # 本次真实接触位置。
			if _state == FlightState.OUTBOUND and (_outbound_end() - position_at_hit.x) * _shot.launch_direction < -END_EPSILON:
				break
			_set_position(position_at_hit)
			_hit_ids[target.get_instance_id()] = true
			attack_once(target)
			if _hit_ids.size() >= _shot.hit_limit:
				if _state == FlightState.OUTBOUND:
					_plan_turn()
				break
	if not is_attack_active():
		_finish(false)
		return
	if _state == FlightState.OUTBOUND:
		endpoint.x = _clamp_outbound(endpoint.x)
		endpoint.y = _level_y + BloomerangFlightQuery.height_at(_slope, endpoint.x)
	_set_position(endpoint)
	if is_finite(catch_at) and _source_present():
		_finish(_state == FlightState.RETURNING)

## 先验证弱引用再传入有类型的接口，避免已释放母株在参数转换阶段报错。
func _source_present() -> bool:
	return _shot != null and is_instance_valid(_thrower) and _shot.source_present(_thrower)

## 对当前段 [param start]、[param finish] 查询原株；去程不能接住自己。
func _source_contact(start: Vector2, finish: Vector2) -> float:
	if _state == FlightState.OUTBOUND or not _source_present():
		return INF
	if _state == FlightState.RETURNING:
		return _query.marker_fraction(_launch.global_position, start, finish) \
			if is_instance_valid(_launch) and _launch.is_inside_tree() and not _launch.is_queued_for_deletion() else INF
	if is_instance_valid(_thrower.hurt_box_component):
		return _query.area_fraction(_thrower.hurt_box_component.hurt_box_real, start, finish)
	return INF

## 开始唯一一次返程；本程穿透与僵王去重清空，单弹伤害成长保留。
func _begin_return() -> void:
	_ahead_area = null
	_turn_x = _flight_x
	_state = FlightState.RETURNING
	_hit_ids.clear()
	_hit_boss_ids.clear()
	curr_attack_num = 0
	direction = Vector2(_travel_sign(), 0.0)

## 返回当前实际行进符号，供命中、分裂和防具方向共用。
func _travel_sign() -> int:
	return -_shot.launch_direction if _state == FlightState.RETURNING else _shot.launch_direction

## 返回原抛出方向上的当帧可见边缘。
func _edge_x() -> float:
	return _screen.end.x if _shot.launch_direction > 0 else _screen.position.x

## 返回不会越过当前屏幕边缘的去程终点。
func _outbound_end() -> float:
	if not is_finite(_turn_x):
		return _edge_x()
	return minf(_turn_x, _edge_x()) if _shot.launch_direction > 0 else maxf(_turn_x, _edge_x())

## 将 [param world_x] 截断到本次去程终点；左右抛射使用同一规则。
func _clamp_outbound(world_x: float) -> float:
	return minf(world_x, _outbound_end()) if _shot.launch_direction > 0 else maxf(world_x, _outbound_end())

## 同步 [param point] 的逻辑坐标与显示坐标，命中特效和弱镖从此处生成。
func _set_position(point: Vector2) -> void:
	_flight_x = point.x
	global_position = point

## [param damage] 是出战修正后的主伤害；[param _enemy] 由基类保留统一接口。
func _modify_impact_damage(damage: int, _enemy: Character000Base) -> int:
	return _damage.primary_damage(damage)

## 对 [param enemy] 生成独立的追猎附伤与僵王上限，不混入主伤害倍率。
func _impact_bonus(enemy: Character000Base) -> Vector2i:
	return _damage.bonus_for(enemy)

## 对 [param zombie] 按实际弹道相对其朝向选择后击，恐惧翻面与左向初发同样适用。
func _attack_zombie(zombie: Zombie000Base) -> void:
	var mode: BulletRegistry.AttackMode = bullet_mode # 保留显式特殊伤害模式，只修正普通弹的背击。
	if mode == BulletRegistry.AttackMode.Norm and direction.x * zombie.direction_x_root < 0.0:
		mode = BulletRegistry.AttackMode.Real
	_hit_zombie(zombie, mode)

## [param _target] 已被统一管线接纳；[param impact_position] 是该次实际接触的世界坐标。
func _on_impact_resolved(_target: Character000Base, impact_position: Vector2) -> void:
	_damage.register_impact()
	if not _shot.split_enabled or not is_attack_active() or not projectile_factory.is_valid() \
			or _state == FlightState.FINISHED or _state == FlightState.WEAK:
		return
	var child_shot: BloomerangShotContext = _shot.for_split(-_travel_sign()) # 弱镖新身份、新成长，永久关闭再分裂。
	var source: Plant000Base = _thrower if is_instance_valid(_thrower) else null # 母株离场不取消已经发出的暴雨。
	var marker: Marker2D = _launch if is_instance_valid(_launch) else null # 无实时枪口时继续飞到屏幕外。
	var child: Bullet017Boomerang = projectile_factory.call(source, marker, child_shot, impact_position,
		lane, can_attack_zombie_status, can_attack_plant_status, impact_sound_tier) as Bullet017Boomerang # 唯一工厂。
	if child != null:
		_shot.game.bullets.add_child(child)

## 将弹体永久置为终态；[param caught] 仅代表真实返程接触，失效或超时不会伪造回收。
func _finish(caught: bool) -> void:
	if _state == FlightState.FINISHED:
		return
	var notify: bool = caught and _state == FlightState.RETURNING and _shot != null \
		and _source_present() # 回调前冻结真实回收资格。
	_state = FlightState.FINISHED
	set_physics_process(false)
	queue_free()
	if notify:
		returned.emit(get_instance_id(), _shot)
