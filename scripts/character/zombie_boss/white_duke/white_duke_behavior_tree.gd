extends RefCounted
class_name WhiteDukeBehaviorTree
## Pure priority selection, no direct summon, timer, node or corpse mutation.
enum Action { NONE, RESURRECT, COMMAND, FRENZY, BREACH, CHANGE_LANE }
const SKILLS: Array[Action] = [
	Action.RESURRECT, Action.COMMAND, Action.FRENZY, Action.BREACH
]
var _scheduler := BossAlternatingActionScheduler.new(Action.CHANGE_LANE)
var _next_skill := 0

func tick(delta: float) -> Action:
	if not _scheduler.ready(delta,false):
		return Action.NONE
	if _scheduler.must_change_lane():
		return Action.CHANGE_LANE
	var result: Action = SKILLS[_next_skill]
	_next_skill = (_next_skill+1)%SKILLS.size()
	return result

func complete(action: Action, seconds: float) -> void:
	_scheduler.complete(action,seconds)

func reset(seconds: float) -> void:
	_scheduler.reset(seconds)
