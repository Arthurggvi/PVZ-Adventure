## One transient boost channel per zombie. Multiple applications retain their own
## duration; the strongest active multiplier wins (never exponential stacking).
extends Node
class_name AdventureZombieTimedSpeedBoost

const NODE_NAME: StringName = &"AdventureTimedSpeedBoost"
var _zombie: Zombie000Base
var _active: Array[Dictionary] = []
var _applied_multiplier := 1.0

static func apply_to(target: Zombie000Base, multiplier: float, duration: float) -> void:
	if not is_instance_valid(target) or target.is_death 			or target.is_queued_for_deletion() or multiplier <= 1.0 or duration <= 0.0:
		return
	var boost: AdventureZombieTimedSpeedBoost = target.get_node_or_null(
			NodePath(NODE_NAME)) as AdventureZombieTimedSpeedBoost
	if boost == null:
		boost = AdventureZombieTimedSpeedBoost.new()
		boost.name = NODE_NAME
		target.add_child(boost)
	boost.grant(multiplier, duration)

func _ready() -> void:
	_zombie = get_parent() as Zombie000Base
	set_process(false)
	if _zombie != null:
		_zombie.signal_character_death.connect(_on_character_death)

func grant(multiplier: float, duration: float) -> void:
	if _zombie == null or _zombie.is_death or multiplier <= 1.0 or duration <= 0.0:
		return
	_active.append({"multiplier": multiplier, "remaining": duration})
	_sync_speed()
	set_process(true)

func _process(delta: float) -> void:
	if not is_instance_valid(_zombie) or _zombie.is_death:
		_on_character_death()
		return
	for index: int in range(_active.size() - 1, -1, -1):
		var effect: Dictionary = _active[index]
		effect["remaining"] = float(effect["remaining"]) - delta
		if float(effect["remaining"]) <= 0.0:
			_active.remove_at(index)
		else:
			_active[index] = effect
	_sync_speed()
	if _active.is_empty():
		set_process(false)

func _sync_speed() -> void:
	var multiplier := 1.0
	for effect: Dictionary in _active:
		multiplier = maxf(multiplier, float(effect["multiplier"]))
	if not is_equal_approx(multiplier, _applied_multiplier):
		_applied_multiplier = multiplier
		_zombie.update_speed_factor(multiplier,
				Character000Base.E_Influence_Speed_Factor.AdventureTierBoost)

func _on_character_death() -> void:
	_active.clear()
	set_process(false)
