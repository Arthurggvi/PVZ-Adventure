extends AdventureZombieTierAbility
class_name AdventureZombieYetiTier

var _yeti: Zombie020Yeti
var _per_hit := 0.0
var _bonus := 0.0
var _heal := 0
var _seconds := 0.0

func setup(zombie: Zombie020Yeti, rule: Dictionary) -> void:
    bind_tier(zombie)
    _yeti = zombie
    _per_hit = float(rule.get("hit_speed", 0.0))
    _heal = int(rule.get("heal", 0))
    if tier_can_grant_entry():
        (zombie.hp_component as HpComponentZombie).grant_bonus_armor(
                int(rule.get("spawn_armor", 0)))
    var bite: AttackComponentZombieNorm = zombie.attack_component as AttackComponentZombieNorm
    if bite != null:
        set_tier_bite(float(rule.get("bite_factor", 1.0)), AttackComponentZombieNorm.E_AttackValueFactor.AdventureSpeciesBite)
    zombie.hp_component.received_attack.connect(_on_hit)
    set_process(_heal > 0)

func _on_hit(_amount: int) -> void:
    if not tier_can_trigger():
        return
    if not is_instance_valid(_yeti) or _yeti.is_death:
        return
    _bonus += _per_hit
    set_tier_speed(1.0 + _bonus)

func _process(delta: float) -> void:
    if not is_instance_valid(_yeti) or _yeti.is_death:
        set_process(false)
        return
    _seconds += delta
    while _seconds >= 1.0:
        _seconds -= 1.0
        _yeti.hp_component.heal(_heal)
