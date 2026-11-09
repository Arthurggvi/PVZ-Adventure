extends Node
class_name AdventureZombieYetiTier

var _yeti: Zombie020Yeti
var _per_hit := 0.0
var _bonus := 0.0
var _heal := 0
var _seconds := 0.0

func setup(zombie: Zombie020Yeti, rule: Dictionary) -> void:
    _yeti = zombie
    _per_hit = float(rule.get("hit_speed", 0.0))
    _heal = int(rule.get("heal", 0))
    (zombie.hp_component as HpComponentZombie).grant_bonus_armor(
            int(rule.get("spawn_armor", 0)))
    var bite: AttackComponentZombieNorm = zombie.attack_component as AttackComponentZombieNorm
    if bite != null:
        bite.update_attack_value(float(rule.get("bite_factor", 1.0)),
                AttackComponentZombieNorm.E_AttackValueFactor.AdventureSpeciesBite)
    zombie.hp_component.received_attack.connect(_on_hit)
    set_process(_heal > 0)

func _on_hit(_amount: int) -> void:
    if not is_instance_valid(_yeti) or _yeti.is_death:
        return
    _bonus += _per_hit
    _yeti.update_speed_factor(1.0 + _bonus,
            Character000Base.E_Influence_Speed_Factor.AdventureTierStance)

func _process(delta: float) -> void:
    if not is_instance_valid(_yeti) or _yeti.is_death:
        set_process(false)
        return
    _seconds += delta
    while _seconds >= 1.0:
        _seconds -= 1.0
        _yeti.hp_component.heal(_heal)
