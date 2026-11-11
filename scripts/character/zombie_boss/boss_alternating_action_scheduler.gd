extends RefCounted
class_name BossAlternatingActionScheduler
## One canonical action/cooldown gate for bosses whose attacks alternate with lane changes.
var _lane_action: int
var _must_change_lane := false
var _cooldown := 0.0

func _init(lane_action: int) -> void:
	_lane_action = lane_action

func ready(delta: float, busy: bool) -> bool:
	if busy:
		return false
	_cooldown = maxf(0.0, _cooldown-delta)
	return _cooldown <= 0.0

func must_change_lane() -> bool:
	return _must_change_lane

func complete(action: int, interval: float) -> void:
	_must_change_lane = action != _lane_action
	_cooldown = maxf(interval,0.0)

func reset(interval: float) -> void:
	_must_change_lane = false
	_cooldown = maxf(interval,0.0)
