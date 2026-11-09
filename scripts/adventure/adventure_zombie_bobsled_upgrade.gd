## The sledgeboard's decay is owned by the original ice-road check; this
## component supplies a typed lifespan policy and reusable rolling crush.
extends Node
class_name AdventureZombieBobsledUpgrade

var _sled: Zombie014Bobsled
var _crush := false
var _last_front := 0.0
var _hit: Dictionary[int, bool] = {}

func setup(sled: Zombie014Bobsled, rule: Dictionary) -> void:
    _sled = sled
    _crush = bool(rule.get("crush", false))
    sled.ice_absence_lifespan_multiplier = float(rule.get("degrade_time_scale", 1.0))
    sled.update_speed_factor(float(rule.get("speed", 1.0)),
            Character000Base.E_Influence_Speed_Factor.AdventureTierStance)
    _last_front = sled.global_position.x - 50.0
    set_physics_process(_crush)

func _physics_process(_delta: float) -> void:
    if not is_instance_valid(_sled) or _sled.is_death:
        set_physics_process(false)
        return
    var front: float = _sled.global_position.x - 50.0
    if not _sled.is_hypno and not is_equal_approx(front, _last_front) \
            and _sled.lane >= 0:
        AdventureZombieLaneImpact.hit_plants(_sled.lane,
                _last_front, front, 0, true, _hit)
    _last_front = front
