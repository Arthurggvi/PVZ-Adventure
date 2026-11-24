## 设置雪橇车离冰耐久倍率，并在升阶时启用碾压。
extends AdventureZombieTierAbility
class_name AdventureZombieBobsledUpgrade

var _sled: Zombie014Bobsled
var _crush := false
var _last_front := 0.0
var _hit: Dictionary[int, bool] = {}

func setup(sled: Zombie014Bobsled, rule: Dictionary) -> void:
    bind_tier(sled)
    _sled = sled
    _crush = bool(rule.get("crush", false))
    set_tier_property(sled, &"ice_absence_lifespan_multiplier", float(rule.get("degrade_time_scale", 1.0)))
    set_tier_speed(float(rule.get("speed", 1.0)))
    _last_front = sled.global_position.x - 50.0
    set_physics_process(_crush)

func _physics_process(_delta: float) -> void:
    if not is_instance_valid(_sled) or _sled.is_death:
        set_physics_process(false)
        return
    var front: float = _sled.global_position.x - 50.0
    if not _sled.is_hypno and not _sled.is_action_suspended() and not is_equal_approx(front, _last_front) \
            and _sled.lane >= 0:
        AdventureZombieLaneImpact.hit_plants(_sled.lane,
                _last_front, front, 0, true, _hit, _sled)
    _last_front = front

## [param _active] 变化时重置扫掠起点，恢复能力不会碾压沉默期间已经经过的路径。
func _tier_state_changed(_active: bool) -> void:
    if is_instance_valid(_sled):
        _last_front = _sled.global_position.x - 50.0
