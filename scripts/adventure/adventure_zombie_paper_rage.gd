## Newspaper-loss modifiers are independent of vanilla paper rage and global speed.
extends AdventureZombieTierAbility
class_name AdventureZombiePaperRage

var _zombie: Zombie006Paper
var _rule: Dictionary
var _used := false

func setup(zombie: Zombie006Paper, rule: Dictionary) -> void:
    bind_tier(zombie)
    _zombie = zombie
    _rule = rule
    set_tier_bite(float(rule.get("normal_bite", 1.0)), AttackComponentZombieNorm.E_AttackValueFactor.AdventureSpeciesBite)
    var hp: HpComponentZombie = zombie.get_node("HpComponent") as HpComponentZombie
    hp.signal_armor2_death.connect(_on_paper_lost)

func _on_paper_lost() -> void:
    if _used:
        return
    _used = true
    # The break itself is an event boundary: immunity and armor must be
    # effective before this same hit continues into the unprotected body.
    if tier_can_trigger():
        _settle_loss()

func _settle_loss() -> void:
    if not tier_can_trigger():
        return
    if not is_instance_valid(_zombie) or _zombie.is_death \
            or _zombie.is_queued_for_deletion():
        return
    var immunity: float = float(_rule.get("immunity", 0.0))
    if immunity > 0.0:
        AdventureZombieTimedCombatBuff.grant_immunity(_zombie, immunity, true, true)
    set_tier_speed(float(_rule.get("speed", 1.0)))
    set_tier_bite(float(_rule.get("bite", 1.0)), AttackComponentZombieNorm.E_AttackValueFactor.AdventureSpeciesRage)
    (_zombie.hp_component as HpComponentZombie).grant_bonus_armor(
            int(_rule.get("armor", 0)))
