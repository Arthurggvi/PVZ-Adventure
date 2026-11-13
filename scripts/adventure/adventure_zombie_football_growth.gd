## Football growth. One hit event counts once; bite counters advance in game seconds.
extends AdventureZombieTierAbility
class_name AdventureZombieFootballGrowth

var _zombie: Zombie000Base
var _rule: Dictionary = {}
var _attack: AttackComponentZombieNorm
var _elapsed_bite := 0.0
var _elapsed_armor := 0.0
var _bite_bonus := 0.0
var _degradation_bonus := 0.0
var _hit_bonus := 0.0
var _target: Plant000Base

func setup(zombie: Zombie000Base, rule: Dictionary) -> void:
    bind_tier(zombie)
    _zombie = zombie
    _rule = rule
    _attack = zombie.get_node("AttackComponent") as AttackComponentZombieNorm
    _degradation_bonus = float(rule.get("initial_degradation", 0.0))
    _attack.bite_landed.connect(_on_bite_landed)
    set_tier_speed(float(rule.get("base_speed", 1.0)))
    var hp: HpComponentZombie = zombie.get_node("HpComponent") as HpComponentZombie
    set_tier_defense(&"damage_reduction", float(rule.get("reduction", 0.0)))
    hp.signal_zombie_hp_loss.connect(_on_hit)
    set_process(float(rule.get("bite_interval", 0.0)) > 0.0 \
            or int(rule.get("armor_per_second", 0)) > 0)

func _on_hit(actual_damage: int) -> void:
    if not tier_can_trigger():
        return
    if actual_damage <= 0 or _zombie.is_death:
        return
    _hit_bonus += float(_rule.get("hit_speed_step", 0.0))
    set_tier_speed(float(_rule.get("base_speed", 1.0)) + _hit_bonus)

func _process(delta: float) -> void:
    if not is_instance_valid(_zombie) or _zombie.is_death:
        set_process(false)
        return
    _elapsed_armor += delta
    while _elapsed_armor >= 1.0:
        _elapsed_armor -= 1.0
        (_zombie.hp_component as HpComponentZombie).grant_bonus_armor(
                int(_rule.get("armor_per_second", 0)))
    var target: Plant000Base
    if _attack.is_enabling and _attack.is_attack_res:
        target = _attack.detect_component.enemy_can_be_attacked as Plant000Base
    if not is_instance_valid(target) or target.is_death:
        _lose_target()
        return
    if target != _target:
        _lose_target()
        _target = target
    var interval: float = float(_rule.get("bite_interval", 0.0))
    if interval <= 0.0:
        return
    _elapsed_bite += delta
    while _elapsed_bite >= interval:
        _elapsed_bite -= interval
        _bite_bonus += float(_rule.get("bite_step", 0.0))
        _degradation_bonus += float(_rule.get("degradation_step", 0.0))
        set_tier_bite(1.0 + _bite_bonus, AttackComponentZombieNorm.E_AttackValueFactor.AdventureSpeciesBite)

func _on_bite_landed(target: Node, _amount: int) -> void:
    if not tier_can_trigger():
        return
    if target is Plant000Base:
        _apply_degradation(target as Plant000Base)

func _apply_degradation(plant: Plant000Base) -> void:
    if is_instance_valid(plant):
        AdventurePlantNegativeEffects.apply(plant, AdventurePlantNegativeEffects.Kind.DEGRADATION, _zombie.get_instance_id(), _degradation_bonus)

func _lose_target() -> void:
    if _target == null:
        return
    _target = null
    _elapsed_bite = 0.0
    _bite_bonus = 0.0
    if not bool(_rule.get("keep_degradation_counter", false)):
        _degradation_bonus = float(_rule.get("initial_degradation", 0.0))
    set_tier_bite(1.0, AttackComponentZombieNorm.E_AttackValueFactor.AdventureSpeciesBite)
