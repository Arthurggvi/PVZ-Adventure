## 大喷菇全行范围的单株投影；检测、弹体射程与原生喷雾共用当前棋盘右界。
extends RefCounted
class_name AdventureFumeRange

## 所属植株与场景均不由本辅助对象延长生命周期。
var _plant: WeakRef
## 来源的实际检测碰撞形状，按单株复制，不能改写场景共享资源。
var _collision: WeakRef
## 原生检测区域，用于世界范围到局部形状的转换。
var _area: WeakRef
## 本株独占的矩形资源。
var _shape: RectangleShape2D
## 未转职时的形状与偏移，撤销时精确恢复。
var _native_size: Vector2
## 原生碰撞中心，保留垂直检测位置和左边缘。
var _native_position: Vector2
## 当前同排最右攻击边界，单位为世界像素。
var _right_limit: float = 0.0
## 每个原生粒子节点的弱引用与未修改参数。
var _particles: Array[Dictionary] = []

## 为 [param plant] 复制检测形状并记录粒子基线，调用时植物已完成ready。
func configure(plant: Plant011FumeShroom) -> void:
	_plant = weakref(plant)
	var collision: CollisionShape2D = plant.attack_component.detect_component.get_node_or_null(^"Area2D/CollisionShape2D") as CollisionShape2D # 原生前向检测矩形。
	if collision == null or not collision.shape is RectangleShape2D:
		push_error("大喷菇全行范围需要原生矩形检测区")
		return
	_collision = weakref(collision)
	_area = weakref(collision.get_parent())
	_shape = collision.shape.duplicate() as RectangleShape2D
	_native_size = _shape.size
	_native_position = collision.position
	collision.shape = _shape
	for particles: GPUParticles2D in plant.all_bullet_fx: # 保存粒子自身参数，不缩放纹理或植物身体。
		_particles.append({"node": weakref(particles), "lifetime": particles.lifetime,
			"amount": particles.amount, "visibility": particles.visibility_rect})
	refresh()

## 即时重读同行几何；平台移动时允许范围增长或收缩，不累计上次长度。
func refresh() -> void:
	var plant: Plant011FumeShroom = _plant.get_ref() as Plant011FumeShroom if _plant != null else null # 当前来源可已离场。
	var game: MainGameManager = Global.main_game # 仅处理当前实际战场。
	var collision: CollisionShape2D = _collision.get_ref() as CollisionShape2D if _collision != null else null # 私有形状所在节点。
	var area: Node2D = _area.get_ref() as Node2D if _area != null else null # 局部几何基准。
	if not is_instance_valid(plant) or not is_instance_valid(game) or game.board == null \
			or not is_instance_valid(collision) or not is_instance_valid(area) or _shape == null \
			or not is_instance_valid(plant.plant_cell) or plant.plant_cell.board != game.board:
		return
	var bounds: Rect2 = BoardQueries.bounds(game.board.row_cells(plant.lane)) # 当前有效同行地块的世界范围。
	_right_limit = bounds.end.x
	if plant.lane >= 0 and plant.lane < game.board.lanes.size():
		_right_limit = maxf(_right_limit, game.to_global(game.board.lanes[plant.lane].spawn_position).x)
	_right_limit += maxf(1.0, game.board.local_pitch(plant.plant_cell).x)
	var left: float = _native_position.x - _native_size.x * 0.5 # 保留场景定义的前向起点。
	var reach: float = maxf(_native_size.x, area.to_local(Vector2(_right_limit, area.global_position.y)).x - left) # 检测局部长度。
	_shape.set_deferred("size", Vector2(reach, _native_size.y))
	collision.set_deferred("position", Vector2(left + reach * 0.5, _native_position.y))
	plant.attack_component.detect_component.need_judge = true
	for profile: Dictionary in _particles: # 延长粒子行程和数量，保持原纹理比例与每秒发射密度。
		var particles: GPUParticles2D = profile.node.get_ref() as GPUParticles2D # 已销毁节点自然跳过。
		if not is_instance_valid(particles):
			continue
		var distance: float = maxf(_native_size.x, _right_limit - particles.global_position.x) # 从真实喷雾起点到全行边缘。
		var ratio: float = distance / maxf(1.0, _native_size.x) # 每轮从原值投影，不重复乘算。
		var lifetime: float = float(profile.lifetime) * ratio # 原速度曲线随生命周期延长到同一长度。
		var amount: int = maxi(1, ceili(float(profile.amount) * ratio)) # 保持单位时间的原生烟雾密度。
		if not is_equal_approx(particles.lifetime, lifetime):
			particles.lifetime = lifetime
		if particles.amount != amount:
			particles.amount = amount
		particles.visibility_rect = (profile.visibility as Rect2).merge(Rect2(-80.0, -100.0, distance + 160.0, 200.0))

## 从弹口世界坐标 [param origin] 得到本次射程；[param original] 保留原场景射程下限。
func projectile_reach(origin: Vector2, original: float) -> float:
	return maxf(original, _right_limit - origin.x)

## 控制器被单独移除时恢复原生参数；植物整株释放时弱引用会自动失效。
func restore() -> void:
	var collision: CollisionShape2D = _collision.get_ref() as CollisionShape2D if _collision != null else null # 可能已随植物销毁。
	if is_instance_valid(collision) and _shape != null:
		_shape.set_deferred("size", _native_size)
		collision.set_deferred("position", _native_position)
	for profile: Dictionary in _particles: # 仅还原本辅助对象曾修改的原生粒子参数。
		var particles: GPUParticles2D = profile.node.get_ref() as GPUParticles2D # 不持有已释放节点。
		if is_instance_valid(particles):
			particles.lifetime = float(profile.lifetime)
			particles.amount = int(profile.amount)
			particles.visibility_rect = profile.visibility
