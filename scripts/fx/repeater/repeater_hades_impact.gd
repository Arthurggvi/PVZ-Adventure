## 冥弹命中专属黑白冲击：冥界撕裂、魂波扩散和粒化，不使用原版普通豌豆碎屑。
extends Node2D
class_name RepeaterHadesImpact

## 非处决半秒归零，处决六成秒覆盖原身体渐白过程。
const HIT_LIFETIME: float = 0.52
## 处决的命中冲击更长，但依然先于九百毫秒人体剪影结束。
const EXEC_LIFETIME: float = 0.66

## 可暂停的当前动画秒数。
var _age: float = 0.0
## 是否本发真实触发处决，改变初始冲击规模而不触发死亡。
var _execution: bool = false
## 子弹实际来向决定裂缝的方向。
var _direction: Vector2 = Vector2.RIGHT
## 此次命中所属战斗宿主的视觉对象池。
var _pool: RepeaterVisualPool

## 在 [param parent] 中创建视觉，[param z] 优先于场景前后遮挡，永不发起伤害。
static func spawn(parent: Node, position: Vector2, direction: Vector2, execution: bool, z: int) -> Node2D:
	if not is_instance_valid(parent) or not RepeaterVisualBudget.may_add_impact(true):
		return null
	var pool: RepeaterVisualPool = RepeaterVisualPool.under(parent)
	if pool == null:
		return null
	var effect: RepeaterHadesImpact = pool.acquire(&"hades") as RepeaterHadesImpact
	if effect == null:
		effect = RepeaterHadesImpact.new() # 池空时才构建新视觉节点。
	effect._pool = pool
	effect._age = 0.0
	effect._execution = execution
	effect._direction = direction.normalized() if not direction.is_zero_approx() else Vector2.RIGHT
	effect.top_level = true
	effect.z_as_relative = false
	effect.z_index = mini(z + 2, RenderingServer.CANVAS_ITEM_Z_MAX)
	parent.add_child(effect)
	effect.global_position = position
	return effect

## 进入时登记，退出时注销；与场本体不会互相持有引用。
func _enter_tree() -> void:
	RepeaterVisualBudget.enter(&"impact")

## 场景死亡、过轮或正常结束都会可靠释放视觉计数。
func _exit_tree() -> void:
	RepeaterVisualBudget.leave(&"impact")

## 一个可暂停时钟推进全部阶段，零材质分配，无新节点。
func _process(delta: float) -> void:
	_age += delta
	if _age >= (EXEC_LIFETIME if _execution else HIT_LIFETIME):
		if is_instance_valid(_pool):
			_pool.release(&"hades", self)
		else:
			queue_free()
		return
	queue_redraw()

## 由一次突然失色的冲击切入黑裂隙，再以灰白魂波及冷光碎痕消散。
func _draw() -> void:
	var duration: float = EXEC_LIFETIME if _execution else HIT_LIFETIME
	var pressure: float = 1.0 - RepeaterVisualPalette.smooth(_age / 0.12)
	var opening: float = RepeaterVisualPalette.out_cubic(_age / 0.22)
	var fade: float = RepeaterVisualPalette.smooth((duration - _age) / 0.22)
	var intensity: float = 1.30 if _execution else 1.0
	var axis: Vector2 = _direction
	var normal: Vector2 = Vector2(-axis.y, axis.x)
	# 初瞬的失色闪电，不以一团普通白光代替命中。
	if pressure > 0.0:
		var tip: Vector2 = axis * (26.0 + 24.0 * opening)
		var vertices := PackedVector2Array([
			normal * -9.0, normal * 7.0, tip + normal * 3.0,
			axis * 18.0 - normal * 8.0, normal * -9.0
		])
		draw_colored_polygon(vertices, Color(0.86, 0.92, 1.0, pressure * intensity * 0.90))
		draw_line(-axis * 25.0, tip, Color(1.0, 1.0, 1.0, pressure), 2.4, true)
	# 裂隙先开再收，两层边缘包裹几乎无反射的黑芯。
	var rupture: float = sin(PI * RepeaterVisualPalette.smooth(_age / duration))
	var half: float = 9.0 + opening * (38.0 if _execution else 29.0)
	draw_line(-normal * half, normal * half, Color(0.50, 0.55, 0.78, rupture * fade * 0.80), 7.0, true)
	draw_line(-normal * half, normal * half, Color(0.035, 0.025, 0.09, rupture * fade), 4.0, true)
	# 两条不完整魂波，而非普通弹体的一圈彩色碰撞环。
	var ring: float = 7.0 + RepeaterVisualPalette.out_cubic(_age / 0.37) * (48.0 if _execution else 34.0)
	var ring_alpha: float = (1.0 - RepeaterVisualPalette.smooth(_age / 0.44)) * fade
	draw_arc(Vector2.ZERO, ring, -PI * 0.66, PI * 0.21, 18, Color(0.66, 0.78, 1.0, ring_alpha * 0.95), 1.4, true)
	draw_arc(Vector2.ZERO, ring * 0.83, PI * 0.44, PI * 1.30, 18, Color(0.24, 0.20, 0.43, ring_alpha * 0.85), 2.2, true)
	if RepeaterVisualBudget.quality() == RepeaterVisualBudget.CHEAP:
		return
	# 靠前方的冷白魂屑快速掠过、停顿、熄灭；不会额外判定攻击。
	var pieces: int = 10 if _execution else 7
	for i: int in range(pieces):
		var angle: float = float(i) * 2.399963 + 0.34
		var travel: float = RepeaterVisualPalette.out_cubic(_age / duration) * (20.0 + float(i % 4) * 8.0)
		var pos: Vector2 = Vector2.from_angle(angle) * travel + axis * (_age * 16.0)
		var size: float = 1.0 + float(i % 3) * 0.6
		draw_line(pos, pos - axis * (3.0 + size * 2.5), Color(0.82, 0.87, 1.0, fade * (1.0 - float(i % 3) * 0.14)), size, true)
