## Armor and movement remain separate from the native Zamboni HP-stage slowdown.
extends AdventureZombieTierAbility
class_name AdventureZombieZamboniPressure

const ZAMBONI_PROFILE := preload("res://resources/combat/zamboni_death_explosion_profile.tres")

var _zombie: Zombie013Zamboni
var _bonus := 0.0
var _decay := 0.0

func setup(zombie: Zombie013Zamboni, rule: Dictionary) -> void:
    bind_tier(zombie)
    _zombie = zombie
    _bonus = maxf(0.0, float(rule.get("speed_bonus", 0.0)))
    _decay = maxf(0.0, float(rule.get("hit_decay", 0.0)))
    var hp: HpComponentZombie = zombie.hp_component as HpComponentZombie
    set_tier_defense(&"damage_reduction", float(rule.get("reduction", 0.0)))
    hp.received_attack.connect(_on_hit)
    _sync_speed()
    var death_blast: int = int(rule.get("death_blast", 0))
    if death_blast > 0:
        var burst := AdventureZombieDeathBurst.new()
        zombie.add_child(burst)
        burst.setup(zombie, death_blast, ZAMBONI_PROFILE)

func _on_hit(_actual_damage: int) -> void:
    if not tier_can_trigger():
        return
    # Each received attack counts, including an otherwise fully blocked hit.
    if not is_instance_valid(_zombie) or _zombie.is_death:
        return
    _bonus = maxf(0.0, _bonus - _decay)
    _sync_speed()

func _sync_speed() -> void:
    if is_instance_valid(_zombie):
        set_tier_speed(1.0 + _bonus)
