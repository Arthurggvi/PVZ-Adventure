## 猎人专用短弧适配器；保留直线弹根类的碰撞协议，只复用现成抛物线组件计算运动。
extends BulletMovementLinear
class_name HunterSnowballMovement

## 落点前的控制点向上偏移，单位为世界像素；保持低弧投掷而非高抛物线。
const ARRIVAL_LIFT: float = 24.0
## 极短轨迹也保留正飞行时间，防止现成运动组件除以零。
const MIN_FLIGHT_SECONDS: float = 0.05
## 实到终点后保留两个物理步，确保末段碰撞先于落空回收结算。
const ARRIVAL_PHYSICS_STEPS: int = 2
## 原线性弹体负责伤害、坡面和生命周期，不持有猎人或目标植物。
var _projectile: BulletLinear000Base
## -1 表示飞行中；非负值记录到达实际终点后的物理步数。
var _arrival_steps: int = -1
## 只复用现成贝塞尔构建和推进，不启用其抛物线根类的保护伞或同格优先规则。
@onready var _arc: BulletMovementParabola = $Parabola

## [param displacement] 叠加到绝对坐标弧线，保留其飞行进度。
func translate_world_path(displacement: Vector2) -> void:
	_arc.translate_world_path(displacement)

## 场景内的两个运动节点都归弹体所有；本适配器是唯一由根类逐帧调用的驱动者。
func _ready() -> void:
	super()
	_projectile = owner as BulletLinear000Base

## 从当前世界出手点飞向 [param target_world]；只保存坐标快照，不跟踪已经离场的目标对象。
func start_flight(target_world: Vector2) -> void:
	_arc.parabola_movement_ready(target_world)
	_arc.second_control_point = target_world + Vector2(0.0, -ARRIVAL_LIFT)
	_arc.all_time = maxf(_arc.all_time, MIN_FLIGHT_SECONDS)
	_arrival_steps = -1
	_projectile.direction = (_arc.start_control_point - _projectile.global_position).normalized()

## [param delta] 为有效战斗秒；返回是否仍在飞行，终点碰撞等待不创建额外计时器。
func physics_process_bullet_move(delta: float) -> bool:
	if _arrival_steps >= 0:
		_arrival_steps += 1
		if _arrival_steps >= ARRIVAL_PHYSICS_STEPS:
			_projectile.attack_once(null)
		return false
	var previous: Vector2 = _projectile.global_position # 实际世界位移决定碰撞时的坡面入射方向。
	if not _arc.physics_process_bullet_move(delta):
		_projectile.global_position = _arc.end_global_pos # 原组件在终点前返回 false，必须先走完剩余路径。
		_arrival_steps = 0
	var displacement: Vector2 = _projectile.global_position - previous # 不以固定左向替代短弧实际切线。
	if not displacement.is_zero_approx():
		_projectile.direction = displacement.normalized()
	return _arrival_steps < 0
