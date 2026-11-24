## Dolphin retains its native one-jump state machine. The authorized landing
## displacement controls how many grid cells can be crossed in that jump.
extends AdventureZombieTierAbility
class_name AdventureZombieDolphinLeap

var _rider: Zombie015Dolphinrider
var _damage := 0
var _start_x := 0.0
var _impact: Dictionary[int, bool] = {}
var _had_jump := false

func setup(zombie: Zombie015Dolphinrider, rule: Dictionary) -> void:
    bind_tier(zombie)
    _rider = zombie
    _damage = int(rule.get("crush_damage", 0))
    var jump: JumpComponent = zombie.jump_component
    set_tier_property(jump, &"jump_distance_cells", int(rule.get("jump_distance_cells", 0)))
    jump.signal_jump_start.connect(_on_jump_start)
    jump.signal_jump_end_end.connect(_on_landed)
    set_tier_defense(&"damage_reduction", float(rule.get("ride_reduction", 0.0)))
    set_tier_speed(float(rule.get("ride_speed", 1.0)))
    zombie.signal_character_death.connect(_remove_ride_protection)
    set_process(true)

func _process(_delta: float) -> void:
    if not is_instance_valid(_rider) or _rider.is_death:
        set_process(false)
        return
    if not _rider.is_ride:
        _remove_ride_protection()
        set_process(false)

func _remove_ride_protection() -> void:
    if is_instance_valid(_rider) and is_instance_valid(_rider.hp_component):
        set_tier_defense(&"damage_reduction", 0.0)

func _on_jump_start() -> void:
    _start_x = _rider.global_position.x
    _had_jump = tier_can_trigger() # 沉默中起跳不在稍后落地时补发技能。
    _remove_ride_protection()

func _on_landed() -> void:
    if not _had_jump:
        return
    _had_jump = false
    if not tier_can_trigger() or _rider.is_action_suspended() or _damage <= 0 or _rider.is_death or _rider.is_hypno:
        return
    if _rider.jump_component.is_jump_stop:
        return
    AdventureZombieLaneImpact.hit_plants(
            _rider.lane, _start_x, _rider.global_position.x,
            _damage, false, _impact, _rider)
