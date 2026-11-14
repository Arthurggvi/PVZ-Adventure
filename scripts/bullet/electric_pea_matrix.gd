## 战场唯一的超导电弧画布与固定帧结算器，按实际出手植株组织有界连线。
extends Node2D
class_name ElectricPeaMatrix

## 同一战场的子节点名；仅首枚选中矩阵的电球离手时建立。
const NODE_NAME: StringName = &"ElectricPeaMatrix"
## 每六十分之一游戏秒独立扣一次伤。
const STEP: float = 1.0 / 60.0
## 电弧的真实世界宽度与绘制宽度共用同一参数，单位为像素。
const WIDTH: float = 2.0
## 单画布绘制的电弧颜色。
const COLOR := Color(0.44, 0.85, 1.0, 0.82)

## 源植株实例 ID 到个体电球列表；换场或空组时回收。
var _groups: Dictionary[int, Array] = {}
## 当前展示帧的线段端点，每对端点为一条独立线。
var _lines := PackedVector2Array()
## 固定结算帧尚未消费的游戏秒数。
var _elapsed: float = 0.0
## 整个战场共用一份几何探针，每段调整长度。
var _probe := RectangleShape2D.new()


## 将 [param ball] 登记到其原战场，扩散和分裂后代沿用相同来源ID。
static func register_ball(ball: ElectricPeaProjectile) -> void:
	var container: Node2D = ball.get_parent() # 与所有电球共用战场容器的生命周期。
	var matrix: ElectricPeaMatrix = container.get_node_or_null(NodePath(NODE_NAME)) as ElectricPeaMatrix # 同一个容器仅建立一次。
	if matrix == null:
		matrix = ElectricPeaMatrix.new()
		matrix.name = NODE_NAME
		matrix.z_index = 349
		# 电球在默认优先级移动；矩阵观察本物理帧移动后的世界端点。
		matrix.process_physics_priority = 10
		matrix.process_mode = Node.PROCESS_MODE_ALWAYS
		container.add_child(matrix)
	var id: int = ball.shot.source_id # 本株死亡后不重新绑定来源。
	if not matrix._groups.has(id):
		matrix._groups[id] = []
	matrix._groups[id].append(ball)


## 在 [param delta] 游戏物理秒内消费所有应到的固定帧；暂停时只清理失效节点并更新画布。
func _physics_process(delta: float) -> void:
	_lines.clear()
	var networks: Array[Array] = [] # 只有至少两枚有效球的植株有可计算线段。
	var game: MainGameManager = null # 每个画布仅服务自己的唯一战场。
	for id: int in _groups.keys(): # 已离场的电球不占据活跃列表。
		var balls: Array = _groups[id] # 按引用更新后续帧使用的列表。
		for index: int in range(balls.size() - 1, -1, -1): # 倒序清理失效的战局、轮次或阶段。
			var ball: Variant = balls[index] # 节点可能已经被释放。
			if not is_instance_valid(ball) or ball.is_queued_for_deletion() or not ball.shot.is_active():
				balls.remove_at(index)
		if balls.is_empty():
			_groups.erase(id)
			continue
		if balls.size() < 2:
			continue
		balls.sort_custom(_position_less)
		networks.append(balls)
		game = balls[0].shot.game
		for index: int in range(1, balls.size()): # 每个球只连接排序中的前一个球，总共 N-1 条。
			_lines.append(to_local(balls[index - 1].global_position))
			_lines.append(to_local(balls[index].global_position))
	queue_redraw()
	if _groups.is_empty():
		queue_free()
		return
	if networks.is_empty():
		_elapsed = 0.0
		return
	if get_tree().paused:
		return
	_elapsed += delta
	if _elapsed + 0.000001 < STEP:
		return
	var enemies := ElectricPeaFlightQuery.all_targets(game) # 同一物理帧所有源共用一次全局候选读取。
	while _elapsed + 0.000001 >= STEP: # 时间倍率改变时执行全部应结算帧，没有视觉降级伤害。
		_elapsed = maxf(0.0, _elapsed - STEP)
		for balls: Array in networks: # 每株在此固定帧使用各自的去重账本。
			_strike(balls, enemies)


## 对 [param balls] 的排序邻接线用真实几何求交 [param enemies]；每个实体每源每帧只结算一次。
func _strike(balls: Array, enemies: Array[Character000Base]) -> void:
	var contacted: Dictionary[int, bool] = {} # 接触去重，保护者转移另由实际承伤资格去重。
	var scope := CombatHitScope.new() # 本株此固定帧内共享的实际承伤资格。
	for index: int in range(1, balls.size()): # 顺序传递连线，不构造两两组合。
		var left: Variant = balls[index - 1] # 命中同步触发离场时原端点可能失效。
		var right: Variant = balls[index] # 右端的快照用于本线，保留自身出手伤害。
		if not is_instance_valid(left) or not is_instance_valid(right) or left.is_queued_for_deletion() \
				or right.is_queued_for_deletion() or not right.shot.is_active() or get_tree().paused:
			continue
		var shot: ElectricPeaShotContext = right.shot # 同组必须仍属于同一原战局。
		var start: Vector2 = left.global_position # 左端的实际世界位置。
		var finish: Vector2 = right.global_position # 右端的实际世界位置。
		var direction: Vector2 = finish - start # 根据实际世界段设置探针尺寸与角度。
		if direction.length_squared() <= 0.000001:
			continue
		_probe.size = Vector2(direction.length(), WIDTH)
		var transform := Transform2D(direction.angle(), start.lerp(finish, 0.5)) # 矩形探针覆盖实际电弧。
		var bounds: Rect2 = transform * _probe.get_rect() # 粗筛跳过明显在弧线以外的形状。
		for reference: Variant in enemies: # 设施不会受到矩阵持续场伤害。
			if not is_instance_valid(reference) or (not reference is Zombie000Base and not reference is ZB000Base) \
					or not ElectricPeaFlightQuery.can_hit(reference):
				continue
			var target: Character000Base = reference # 候选经前一道弧结算后可能已变更状态。
			var id: int = target.get_instance_id() # 同一角色的多个形状共用身份。
			if contacted.has(id) or not _intersects(target.hurt_box_component.hurt_box_real, transform, bounds):
				continue
			contacted[id] = true
			shot.hit(target, shot.matrix_damage, ElectricPeaShotContext.HitKind.FIELD, scope)


## 确认 [param area] 的某个启用受击形状与 [param transform]、[param bounds] 定位的弧线探针相交。
func _intersects(area: Area2D, transform: Transform2D, bounds: Rect2) -> bool:
	for owner_id: int in area.get_shape_owners(): # 兼容具有多个真实受击盒的僵王。
		if area.is_shape_owner_disabled(owner_id):
			continue
		var target_transform: Transform2D = area.global_transform * area.shape_owner_get_transform(owner_id) # 形状所在的真实世界变换。
		for index: int in range(area.shape_owner_get_shape_count(owner_id)): # 同一受击区内逐形状确认。
			var shape: Shape2D = area.shape_owner_get_shape(owner_id, index) # 受击盒资源，可能为非矩形。
			if shape != null and bounds.intersects(target_transform * shape.get_rect(), true) \
					and _probe.collide(transform, shape, target_transform):
				return true
	return false


## 按 [param a] 与 [param b] 的世界横坐标、纵坐标及实例ID依次排序。
static func _position_less(a: ElectricPeaProjectile, b: ElectricPeaProjectile) -> bool:
	if a.global_position.x != b.global_position.x:
		return a.global_position.x < b.global_position.x
	if a.global_position.y == b.global_position.y:
		return a.get_instance_id() < b.get_instance_id()
	return a.global_position.y < b.global_position.y


## 同一画布一次绘制所有简单连线。
func _draw() -> void:
	if not _lines.is_empty():
		draw_multiline(_lines, COLOR, WIDTH, true)
