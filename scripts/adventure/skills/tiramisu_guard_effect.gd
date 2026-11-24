## 花冠守护的同步施放入口。实体、剩余时间与全场保护随本局战斗回收。
extends CharacterSkillEffect

## 仅在绑定该技能时加载守护屏障。
const BarrierScene: PackedScene = preload("res://scenes/adventure/skills/tiramisu_guard_barrier.tscn")
## 挡在目标脚点靠屋的一侧，给正在移动的僵尸留出首帧碰撞空间。
const LEAD_OFFSET: float = 49.0

## [param context] 的棋盘、临时容器及敌人均可用时允许施放。
func can_execute(context: CharacterSkillContext) -> bool:
	return _can_place(context) and is_finite(_front_x(context))

## 在 [param context] 最靠近屋子的敌人前立即立盾，成功才启动冷却。
func execute(context: CharacterSkillContext) -> bool:
	if not _can_place(context):
		return false
	var front: float = _front_x(context) # 施放瞬间的前线横坐标，盘外等待入场者已被过滤。
	if not is_finite(front):
		return false
	var bounds: Rect2 = BoardQueries.bounds(context.board.cells()) # 实际棋盘覆盖范围，包括地块间的高度差。
	if not bounds.has_area():
		return false
	var barrier: TiramisuGuardBarrier = BarrierScene.instantiate() # 全行共用一个实际受击实体。
	barrier.prepare(context.state_source(), front - LEAD_OFFSET, bounds)
	context.game.bombs.add_child(barrier)
	return true

## [param context] 必须处在可操作的战斗并且拥有世界层临时容器。
func _can_place(context: CharacterSkillContext) -> bool:
	if context == null or not context.is_active() or context.board.cells().is_empty():
		return false
	var host: Node2D = context.game.bombs # 临时战斗对象和演出共用的世界层。
	return is_instance_valid(host) and host.is_inside_tree() and not host.is_queued_for_deletion()

## 从 [param context] 读取所有已进入棋盘的存活敌人。空场返回 INF。
func _front_x(context: CharacterSkillContext) -> float:
	var first: float = INF # 最靠近屋子的有效敌人在最小世界 X。
	var bounds: Rect2 = BoardQueries.bounds(context.board.cells()) # 刚开始走进外侧地块的敌人也可作为锚点。
	for target: Character000Base in context.hostile_targets(true, false, false): # 不需要敌人当前可受击。
		var x: float = target.global_position.x # 普通僵尸的根节点即地面脚点。
		if target is ZB000Base:
			x = target.hurt_box_component.global_position.x
		if x <= bounds.end.x + 24.0:
			first = minf(first, x)
	return first
