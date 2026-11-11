## 黑将军优先选择树：运行中保持，冷却后强制换行；无旗且插旗就绪时优先插旗。
## 不持有场景节点，动作结束只反馈一次，转阶段可安全中断并重置。
extends RefCounted
class_name BlackGeneralBehaviorTree

## 动作叶节点；NONE 表示当前没有可启动动作。
enum Action { NONE, PLANT_FLAG, COMMAND, CHARGE, LEAD, CHANGE_LANE }
## 插旗外的技能轮转顺序，保证不会随机连续遗漏某个技能。
const SKILLS: Array[Action] = [Action.COMMAND, Action.CHARGE, Action.LEAD]
## 下次必须执行换行的序列约束。
var _scheduler := BossAlternatingActionScheduler.new(Action.CHANGE_LANE)
## 普通技能轮转游标。
var _cursor: int = 0
## 动作结束后的剩余等待秒数。
## 插旗后的独立冷却；转阶段重置行动间隔时仍保留。
var _flag_cooldown: float = 0.0

## [param delta] 本帧战斗秒数；普通动作、换行和转阶段期间均继续计时。
func advance_flag_cooldown(delta: float) -> void:
	_flag_cooldown = maxf(0.0, _flag_cooldown - delta)

## [param seconds] 成功插旗后开始计算的冷却秒数。
func mark_flag_planted(seconds: float) -> void:
	_flag_cooldown = seconds

## [param delta] 已乘角色速度的秒数；[param busy] 执行器是否占用；[param has_flag] 场上是否有令旗。
## 按优先级返回一个叶节点，技能执行由调用者负责。
func tick(delta: float, busy: bool, has_flag: bool) -> Action:
	if busy:
		return Action.NONE
	if not _scheduler.ready(delta,false):
		return Action.NONE
	if _scheduler.must_change_lane():
		return Action.CHANGE_LANE
	if not has_flag and _flag_cooldown <= 0.0:
		return Action.PLANT_FLAG
	var action: Action = SKILLS[_cursor] # 本次普通技能叶节点。
	_cursor = (_cursor + 1) % SKILLS.size()
	return action

## [param action] 刚完成的动作；[param interval] 下一动作等待秒数。
func complete(action: Action, interval: float) -> void:
	_scheduler.complete(action,interval)

## [param interval] 入场或转阶段结束后的首次等待；转阶段已回到右侧，重新选择技能。
func reset(interval: float) -> void:
	_scheduler.reset(interval)
