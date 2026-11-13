## 回旋镖的有限自然攻击事务；动画和在场弹数均不参与发射解锁。
extends RefCounted
class_name BloomerangAttackCycle

## 种下后的首轮等待，单位为正常攻速下的游戏秒。
const INITIAL_DELAY: float = 1.5
## 原版两次自然起手之间的随机周期。
const ATTACK_INTERVAL: Vector2 = Vector2(2.85, 3.0)
## 没有合法目标时的重查间隔。
const TARGET_RECHECK_DELAY: float = 0.1
## 原版投掷音效在攻击动作中的时间点。
const SOUND_TIME: float = 0.4
## 原版回旋镖离手时间，由本时钟唯一触发。
const RELEASE_TIME: float = 0.666667
## 三连发相邻两轮离手间隔，随同一攻速时钟缩放。
const BURST_INTERVAL: float = 0.16
## 原版攻击表现的完整时长；到期后机械状态必定归位。
const ACTION_DURATION: float = 1.333333
## 单次自然事务最多三轮，不因卡顿或回收生成无界循环。
const MAX_SHOTS: int = 3
## 每个状态只描述本次自然攻击，不记录其他在途投射物。
enum Phase { READY, WINDUP, BURST, RECOVERY }
## 当前有限动作阶段。
var phase: Phase = Phase.READY
## 下一次自然起手前的剩余正常攻速秒数。
var _cooldown: float = INITIAL_DELAY
## 本次动作已经推进的正常攻速秒数。
var _elapsed: float = 0.0
## 本次事务尚未离手的轮数。
var _remaining: int = 0
## 下一轮离手的动作时间点。
var _next_release: float = RELEASE_TIME
## 本次预投掷声音是否尚未消费。
var _sound_pending: bool = false

## 返回是否仍有自然攻击动作；接镖和补投不改变此结果。
func is_busy() -> bool:
	return phase != Phase.READY

## 返回是否到达下一次自然攻击起手时机。
func can_begin() -> bool:
	return not is_busy() and _cooldown <= 0.0

## [param shots] 为本次自然事务的离手轮数，限制在一至三轮。
## 起手时一次性消费风切概率，后续回收不能扩展本事务。
func begin(shots: int) -> void:
	if not can_begin():
		return
	phase = Phase.WINDUP
	_elapsed = 0.0
	_remaining = clampi(shots, 1, MAX_SHOTS)
	_next_release = RELEASE_TIME
	_sound_pending = true
	_cooldown = randf_range(ATTACK_INTERVAL.x, ATTACK_INTERVAL.y)

## 无目标只延后索敌，不建立尚未发射的事务。
func retry_target() -> void:
	if not is_busy():
		_cooldown = TARGET_RECHECK_DELAY

## [param elapsed_seconds] 是已乘角色速度及本株攻速的游戏秒数。
## 返回本帧声音、离手轮数和结束标记；循环上限固定，不能追赶无限历史攻击。
func advance(elapsed_seconds: float) -> Dictionary:
	var result: Dictionary = {"sound": false, "waves": 0, "finished": false} # 仅描述本次推进的有限事件。
	if not is_finite(elapsed_seconds) or elapsed_seconds <= 0.0:
		return result
	_cooldown = maxf(0.0, _cooldown - elapsed_seconds)
	if not is_busy():
		return result
	_elapsed += elapsed_seconds
	if _sound_pending and _elapsed >= SOUND_TIME:
		_sound_pending = false
		result.sound = true
	for _index: int in range(MAX_SHOTS): # 最多消费当前事务的三次离手，绝不从此处开启下一事务。
		if _remaining <= 0 or _elapsed < _next_release:
			break
		_remaining -= 1
		_next_release += BURST_INTERVAL
		result.waves += 1
		phase = Phase.BURST if _remaining > 0 else Phase.RECOVERY
	if _elapsed >= ACTION_DURATION:
		cancel()
		result.finished = true
	return result

## 取消未离手轮次并立即释放机械状态；保留自然冷却，不补发旧动作。
func cancel() -> void:
	phase = Phase.READY
	_elapsed = 0.0
	_remaining = 0
	_next_release = RELEASE_TIME
	_sound_pending = false
