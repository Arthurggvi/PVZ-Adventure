## 晨星分裂弹使用原生阳桃弹体；实际移动按连续速度曲线，最多二代。
extends Bullet008Star
class_name RepeaterStarProjectile

## 平滑加速段长度，单位战斗秒。
const RISE_SECONDS: float = 0.18
## 有限寿命兜底；正常情况下先由原生射程或命中回收。
const MAX_SECONDS: float = 8.0
## 派生时继承的同一次战斗来源。
var shot: RepeaterShotContext
## 一级深色星或二级浅色星，仅影响视觉与后续分裂资格。
var variant_kind: StringName = &"star_dark"
## 一级为一，二级为二，二级命中后绝不继续分裂。
var generation: int = 1
## 同次扇出中的不同配色编号。
var color_index: int = 0
## 产生本颗星的直击对象，避免在出生重叠框内立即把全部分裂耗尽。
var birth_target_id: int = 0
## 自出生起的战斗秒，不按渲染帧累计。
var _age: float = 0.0
## 原生匀速段速度；每帧只临时投影积分后的平均速度，不逐帧相乘。
var _cruise_speed: float = 300.0

## 物理回调中分裂的星在安全时机入树；原场景或阶段失效则在帧末释放未挂载弹体。
func attach_to_battle() -> void:
	if get_parent() != null:
		return
	if shot == null or not shot.is_active() or not is_instance_valid(shot.game.bullets) \
			or shot.game.bullets.is_queued_for_deletion():
		queue_free()
		return
	shot.game.bullets.add_child(self)

## 原生阳桃旋转仍有效；私有命中表阻止出生源目标的重叠重入。
func _ready() -> void:
	super()
	if shot == null or not shot.is_active():
		queue_free()
		return
	_cruise_speed = speed
	is_can_up = false
	is_activate_lane = false
	unique_target_hits = true
	if birth_target_id > 0:
		_promotion_hit_ids[birth_target_id] = true
	bullet_effect.is_bullet_effect = false
	impact_resolved.connect(_on_impact)
	RepeaterProjectileVisual.attach(self, variant_kind, generation, color_index)

## [param delta] 为原生物理战斗时间；用曲线积分差移动，跨帧步长不会改变路程。
func _physics_process(delta: float) -> void:
	if delta <= 0.0:
		return
	var previous: float = _age # 积分区间起点。
	_age += delta
	if _age >= MAX_SECONDS:
		queue_free()
		return
	speed = _cruise_speed * (_distance_units(_age) - _distance_units(previous)) / delta
	super(delta)
	speed = _cruise_speed

## 返回 [param age] 下归一化速度曲线的积分；起速为七成，平滑到原生速度且首尾导数连续。
func _distance_units(age: float) -> float:
	var unit: float = clampf(age / RISE_SECONDS, 0.0, 1.0) # 有限加速段的归一化时刻。
	var integral: float = unit * unit * unit - 0.5 * unit * unit * unit * unit # smoothstep 的解析积分。
	return 0.7 * minf(age, RISE_SECONDS) + 0.3 * RISE_SECONDS * integral \
		+ maxf(0.0, age - RISE_SECONDS)

## [param target] 为原生实际命中者；[param position] 为世界命中点，空目标只播放消散。
func _on_impact(target: Character000Base, position: Vector2) -> void:
	if shot == null or not shot.is_same_battle():
		return
	RepeaterImpactVisual.spawn(shot.game.bullets, variant_kind, position, direction, z_index) # 分裂星跨行飞行时仍沿用当前弹体绘制深度。
	if not shot.is_active():
		return
	if generation == 1 and is_instance_valid(target):
		RepeaterStarFork.split(self, target, shot, generation)
