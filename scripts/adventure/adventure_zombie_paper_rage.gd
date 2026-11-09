## Newspaper-loss modifiers are independent of vanilla paper rage and global speed.
extends Node
class_name AdventureZombiePaperRage

var _zombie: Zombie006Paper
var _rule: Dictionary
var _used := false

func setup(zombie: Zombie006Paper, rule: Dictionary) -> void:
    _zombie = zombie
    _rule = rule
    var attack: AttackComponentZombieNorm = zombie.get_node("AttackComponent") as AttackComponentZombieNorm
    attack.update_attack_value(float(rule.get("normal_bite", 1.0)),
            AttackComponentZombieNorm.E_AttackValueFactor.AdventureSpeciesBite)
    var hp: HpComponentZombie = zombie.get_node("HpComponent") as HpComponentZombie
    hp.signal_armor2_death.connect(_on_paper_lost)

func _on_paper_lost() -> void:
    if _used:
        return
    _used = true
    # The break itself is an event boundary: immunity and armor must be
    # effective before this same hit continues into the unprotected body.
    _settle_loss()

func _settle_loss() -> void:
    if not is_instance_valid(_zombie) or _zombie.is_death \
            or _zombie.is_queued_for_deletion():
        return
    var immunity: float = float(_rule.get("immunity", 0.0))
    if immunity > 0.0:
        AdventureZombieTimedCombatBuff.grant_immunity(_zombie, immunity, true)
    _zombie.update_speed_factor(float(_rule.get("speed", 1.0)),
            Character000Base.E_Influence_Speed_Factor.AdventureTierStance)
    var attack: AttackComponentZombieNorm = _zombie.attack_component as AttackComponentZombieNorm
    attack.update_attack_value(float(_rule.get("bite", 1.0)),
            AttackComponentZombieNorm.E_AttackValueFactor.AdventureSpeciesRage)
    (_zombie.hp_component as HpComponentZombie).grant_bonus_armor(
            int(_rule.get("armor", 0)))
