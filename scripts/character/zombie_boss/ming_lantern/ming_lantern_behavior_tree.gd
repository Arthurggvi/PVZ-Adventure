## 明灯的行动树。先检查行动间隔与滔天优先级，再从四个普通技能中抽取本轮效果。
extends RefCounted
class_name MingLanternBehaviorTree

## 两轮普通行动启动之间的战斗秒数。入场和滔天回场后重新起计。
const TURN_INTERVAL := 8.0
## 完成五轮非滔天行动后，下次以滔天取代普通抽签。
const TIDAL_AFTER := 5
## 普通随机池。滔天由优先级条件触发，不参与抽签。
const REGULAR_SKILLS: Array[StringName] = [&"guide", &"anchor", &"tide", &"shock"]

## 行动抽签独立于场地落点，避免效果数量改变下轮技能概率。
var _rng := RandomNumberGenerator.new()
## 从最近一次启动或回场开始剩余的战斗秒数。
var _wait: float = TURN_INTERVAL
## 自上次滔天以来已启动的普通行动轮数，两技能连放也只算一轮。
var _turns := 0

## 给每个实战实例初始化独立的抽签序列。
func _init() -> void:
	_rng.randomize()

## [param delta] 推进动作秒数。[param busy] 为当前演出仍占用本体，[param powered] 决定是否取两个不同技能。
## 返回本轮有序技能；尚未到行动时刻或本体忙碌时返回空数组。
func tick(delta: float, busy: bool, powered: bool) -> Array[StringName]:
	_wait = maxf(0.0, _wait - delta)
	if busy or not is_zero_approx(_wait):
		return []
	if _turns >= TIDAL_AFTER:
		return [&"tidal"]
	var pool: Array[StringName] = REGULAR_SKILLS.duplicate() # 本轮的可选技能，首选抽出后不重复。
	var selected: Array[StringName] = [pool.pop_at(_rng.randi_range(0, pool.size() - 1))] # 一阶段只释放这一次。
	if powered:
		selected.append(pool[_rng.randi_range(0, pool.size() - 1)])
	return selected

## [param action] 为刚启动的一轮首个技能。任何滔天都清空普通轮数，包括过半触发的强化滔天。
func start_turn(action: StringName) -> void:
	restart_wait()
	_turns = 0 if action == &"tidal" else _turns + 1

## 入场或滔天结束后重新给出完整的下一轮等待时间。
func restart_wait() -> void:
	_wait = TURN_INTERVAL
