## Dolphin retains its native one-jump state machine. The authorized landing
## displacement controls how many grid cells can be crossed in that jump.
extends Node
class_name AdventureZombieDolphinLeap

var _rider: Zombie015Dolphinrider
var _damage := 0
var _start_x := 0.0
var _impact: Dictionary[int, bool] = {}
var _had_jump := false

func setup(zombie: Zombie015Dolphinrider, rule: Dictionary) -> void:
    _rider = zombie
    _damage = int(rule.get("crush_damage", 0))
    var jump: JumpComponent = zombie.jump_component
    jump.jump_distance_cells = int(rule.get("jump_distance_cells", 0))
    jump.signal_jump_start.connect(_on_jump_start)
    jump.signal_jump_end_end.connect(_on_landed)
    zombie.hp_component.damage_reduction.set_source(
            get_instance_id(), float(rule.get("ride_reduction", 0.0)))
    zombie.update_speed_factor(float(rule.get("ride_speed", 1.0)),
            Character000Base.E_Influence_Speed_Factor.AdventureTierStance)
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
        _rider.hp_component.damage_reduction.set_source(get_instance_id(), 0.0)

func _on_jump_start() -> void:
    _start_x = _rider.global_position.x
    _had_jump = true
    _remove_ride_protection()

func _on_landed() -> void:
    if not _had_jump:
        return
    _had_jump = false
    if _damage <= 0 or _rider.is_death or _rider.is_hypno:
        return
    if _rider.jump_component.is_jump_stop:
        return
    AdventureZombieLaneImpact.hit_plants(
            _rider.lane, _start_x, _rider.global_position.x,
            _damage, false, _impact)
