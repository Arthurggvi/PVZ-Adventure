## 单个持续场的时间与几何；伤害统一由场时钟推进，视觉只采样同一条解析曲线。
extends RefCounted
class_name RepeaterFieldState

## 地狱或辉夜，不在持续场中重新抽取弹种。
var kind: StringName
## 原发射来源；母株消失不取消已生成场，但不会继续治疗替代植物。
var shot: RepeaterShotContext
## 命中时的攻击行。
var lane: int = -1
## 原始命中世界坐标。
var origin: Vector2
## 生成时的当地格距，决定该场既定尺寸和漂移长度。
var pitch: Vector2
## 已消耗的战斗秒数，由唯一60Hz时钟写入。
var age: float = 0.0
## 地狱五秒、辉夜三秒，结束后不再结算。
var lifetime: float = 0.0
## 地狱下一次吸取的绝对场年龄，避免刷新或帧率改变节拍。
var next_drain: float = 1.0
## 纯视觉节点，保存辉夜碎片的唯一随机种子与轨迹。
var visual: RepeaterFieldVisual

## 在 [param parent] 上构造 [param field_kind]，由 [param source] 冻结来源。
## [param position]、[param target_lane] 是命中世界坐标及行；调用者在物理回调外执行。
static func create(parent: Node2D, field_kind: StringName, position: Vector2,
		target_lane: int, source: RepeaterShotContext) -> RepeaterFieldState:
	var field := RepeaterFieldState.new() # 每个场独享年龄与下一跳，不创建独立Timer。
	field.kind = field_kind
	field.shot = source
	field.lane = target_lane
	field.origin = position
	field.pitch = source.pitch_at(position, target_lane)
	field.lifetime = 5.0 if field_kind == &"hell" else 3.0
	field.visual = RepeaterFieldVisual.new()
	parent.add_child(field.visual)
	field.visual.z_index = target_lane * 50 + 45
	field.visual.global_position = position
	field.visual.configure(field_kind, randi(), field.pitch, field.lifetime)
	field.visual.set_age(0.0)
	return field

## 在 [param seconds] 采样真实场中心；漂移使用首尾速度连续归零的余弦积分曲线。
func center_at(seconds: float) -> Vector2:
	if kind != &"hell":
		return origin
	var progress: float = clampf(seconds / lifetime, 0.0, 1.0) # 归一化年龄限定总位移，避免积分误差。
	var drift: float = progress - sin(TAU * progress) / TAU # 连续加速、匀滑过渡、减速收束。
	return origin + Vector2(-pitch.x * 0.45 * drift, -pitch.y * 0.045 * sin(PI * progress))

## 用 [param seconds] 同步可见位置与材质时钟；不写回战斗年龄。
func render_at(seconds: float) -> void:
	if is_instance_valid(visual):
		visual.global_position = center_at(seconds)
		visual.set_age(minf(seconds, lifetime))

## 即时撤销视觉，不留下跨轮的尾迹或无伤害场。
func dispose() -> void:
	if is_instance_valid(visual):
		visual.queue_free()
