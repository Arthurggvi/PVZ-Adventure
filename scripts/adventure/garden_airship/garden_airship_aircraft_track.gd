## 一架真实飞行单位的上次可听位置和近场经过门限，独立于战斗移动。
extends RefCounted

## 原单位在释放后不由声源延长寿命。
var actor: Zombie000Base
## 实际旋翼、尾喷或机体视觉挂点。
var anchor: Node2D
## 当前动力状态使用的声源资源。
var stream: AudioStream
## 播放增益 dB、基础音高、虚拟额外深度。
var mix: Vector3
## 对应局内移动声源的实体身份。
var key: int
## 上一有效世界位置用于测速，传送或掉帧时重置判断。
var _before := Vector2.INF
## 上一真实屏幕归一化位置。
var _before_screen := Vector2.INF
## 至少曾在近场外侧观察到源，才允许发出经过事件。
var _armed: bool = false
## 该次实体生命周期已完成一次近场反馈。
var _passed: bool = false
## 只有足够快的实际变化才是近场气流。触发时写入当前世界横速。
var pass_speed: float = 0.0

## [param source] 是真实战斗演员，[param emitter] 使用同一画布上的动力锚点。
## [param sound] 为循环声，[param tuning] 同时提供增益、音高、距离标定。
func _init(source: Zombie000Base, emitter: Node2D, sound: AudioStream, tuning: Vector3) -> void:
	actor = source
	anchor = emitter
	stream = sound
	mix = tuning
	key = actor.get_instance_id()

## 从 [param world]、[param normalized] 及实际 [param step] 判断是否经过近场，返回 0 到 1 的局部阵风。
## 使用跨帧的线段交点，初始出现和大幅位置跳变不当作经过。
func sample_pass(world: Vector2, normalized: Vector2, step: float) -> float:
	var displacement: Vector2 = world - _before # 起点尚未建立时保持无效值。
	var last_screen: Vector2 = _before_screen # 保存上一侧，允许快速单帧经过近场。
	_before = world
	_before_screen = normalized
	if _passed:
		return 0.0
	if absf(normalized.x) >= 0.28 and absf(normalized.y) < 1.16:
		_armed = true
	if not _armed or not last_screen.is_finite() or displacement.length_squared() > 132.0 * 132.0:
		return 0.0
	var speed: float = absf(displacement.x) / maxf(step, 0.001) # 世界像素每自然秒。
	var gate: float = signf(last_screen.x) * 0.13 # 左右来向各自进入监听近场。
	if speed < 18.0 or absf(last_screen.x) <= 0.13 or (last_screen.x - gate) * (normalized.x - gate) > 0.0:
		return 0.0
	var across: float = clampf(inverse_lerp(last_screen.x, normalized.x, gate), 0.0, 1.0) # 使用穿越同一横向位置的纵向距离。
	var height: float = absf(lerpf(last_screen.y, normalized.y, across)) # 与距离衰减保持一致。
	if height > 0.86:
		return 0.0
	_passed = true
	pass_speed = speed
	return (0.56 + 0.44 * smoothstep(18.0, 105.0, speed)) * (1.0 - 0.35 * height)

## 当发动机实际停止时清除上一个有效位置，恢复动力时不会产生虚假的速度尖峰。
func reset_motion() -> void:
	_before = Vector2.INF
	_before_screen = Vector2.INF
