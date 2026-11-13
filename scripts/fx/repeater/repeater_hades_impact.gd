## 冥弹命中的幽冥斩痕：暗裂口、银白边焰和灵魂残痕共享一个局部画布。
extends Node2D
class_name RepeaterHadesImpact

## 非处决半秒归零，处决六成秒覆盖原身体渐白过程。
const HIT_LIFETIME: float = 0.52
## 处决的命中冲击更长，但依然先于九百毫秒人体剪影结束。
const EXEC_LIFETIME: float = 0.66
## 解析斩痕在明亮草地上保留黑白对比，不依赖全屏泛光。
const RIFT_SHADER: Shader = preload("res://shaders/repeater/repeater_hades_rift.gdshader")

## 可暂停的当前动画秒数。
var _age: float = 0.0
## 是否本发真实触发处决，改变初始冲击规模而不触发死亡。
var _execution: bool = false
## 子弹实际来向决定裂缝的方向。
var _direction: Vector2 = Vector2.RIGHT
## 此次命中所属战斗宿主的视觉对象池。
var _pool: RepeaterVisualPool
## 私有材质由节点缓存，同一场景对象池复用时只重置参数。
var _ink: ShaderMaterial
## 上次提交着色时刻，用于在密集命中时降低纯视觉刷新频率。
var _last_draw_age: float = -1.0

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
	effect._last_draw_age = -1.0
	if effect._ink == null:
		effect._ink = ShaderMaterial.new()
		effect._ink.shader = RIFT_SHADER
		effect.material = effect._ink
	effect._ink.set_shader_parameter(&"age", 0.0)
	effect._ink.set_shader_parameter(&"lifetime", EXEC_LIFETIME if execution else HIT_LIFETIME)
	effect._ink.set_shader_parameter(&"execution", execution)
	effect._ink.set_shader_parameter(&"heading", effect._direction.angle())
	effect._ink.set_shader_parameter(&"quality", RepeaterVisualBudget.quality())
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

## [param delta] 是可暂停秒数；缓存材质只在预算允许时更新，生命周期始终完整推进。
func _process(delta: float) -> void:
	_age += delta
	if _age >= (EXEC_LIFETIME if _execution else HIT_LIFETIME):
		if is_instance_valid(_pool):
			_pool.release(&"hades", self)
		else:
			queue_free()
		return
	if _last_draw_age < 0.0 or _age - _last_draw_age >= RepeaterVisualBudget.interval():
		_last_draw_age = _age
		_ink.set_shader_parameter(&"age", _age)
		_ink.set_shader_parameter(&"quality", RepeaterVisualBudget.quality())
		queue_redraw()

## 唯一画布承载完整斩痕；处决有更长的刀锋，但不会改变伤害或触碰范围。
func _draw() -> void:
	var radius: float = 94.0 if _execution else 68.0 # 仅控制绘制面积，正常命中保持紧凑。
	draw_texture_rect(RepeaterVisualPalette.halo_texture(), Rect2(Vector2.ONE * -radius, Vector2.ONE * radius * 2.0), false)
