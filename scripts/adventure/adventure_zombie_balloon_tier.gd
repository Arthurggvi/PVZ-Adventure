## Balloon hit points are literal number of hits, not tier-scaled normal HP.
## Fall explosion is armed only by a popped balloon landing, not by ordinary
## death, Blover off-screen exit, or other forms of elimination.
extends Node
class_name AdventureZombieBalloonTier

const PROFILE := preload("res://resources/combat/jackbox_explosion_profile.tres")

var _balloon: Zombie017Balloon
var _landing_burst: AdventureZombieDeathBurst

func setup(balloon: Zombie017Balloon, rule: Dictionary) -> void:
    _balloon = balloon
    (balloon.hp_component as HpComponentZombie).configure_fragile_armor1(
            int(rule.get("balloon_hits", 1)))
    balloon.update_speed_factor(float(rule.get("fly_speed", 1.0)),
            Character000Base.E_Influence_Speed_Factor.AdventureTierStance)
    var damage: int = int(rule.get("landing_blast", 0))
    if damage > 0:
        _landing_burst = AdventureZombieDeathBurst.new()
        balloon.add_child(_landing_burst)
        _landing_burst.setup(balloon, damage, PROFILE, false)
        balloon.balloon_landed.connect(_on_landed)
    (balloon.hp_component as HpComponentZombie).signal_armor1_death.connect(_on_balloon_lost)

func _on_balloon_lost() -> void:
    if is_instance_valid(_balloon):
        _balloon.update_speed_factor(1.0,
                Character000Base.E_Influence_Speed_Factor.AdventureTierStance)

func _on_landed() -> void:
    if not is_instance_valid(_balloon) or _balloon.is_death or not _balloon.is_pop \
            or _landing_burst == null:
        return
    _landing_burst.trigger_once()
    _balloon.character_death_disappear()
