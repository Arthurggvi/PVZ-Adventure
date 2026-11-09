## Underwater-only movement and one-second shield accrual.
extends Node
class_name AdventureZombieSnorkelDive

var _zombie: Zombie012Snorkle
var _speed := 1.0
var _armor := 0
var _diving := false
var _seconds := 0.0

func setup(zombie: Zombie012Snorkle, rule: Dictionary) -> void:
    _zombie = zombie
    _speed = float(rule.get("dive_speed", 1.0))
    _armor = int(rule.get("armor_per_second", 0))
    set_process(true)

func _process(delta: float) -> void:
    if not is_instance_valid(_zombie) or _zombie.is_death:
        set_process(false)
        return
    var underwater: bool = _zombie.is_swimming and (
            _zombie.curr_be_attack_status == Zombie000Base.E_BeAttackStatusZombie.IsDownPool)
    if underwater != _diving:
        _diving = underwater
        _seconds = 0.0
        _zombie.update_speed_factor(
                _speed if underwater else 1.0,
                Character000Base.E_Influence_Speed_Factor.AdventureTierStance)
    if not underwater or _armor <= 0:
        return
    _seconds += delta
    while _seconds >= 1.0:
        _seconds -= 1.0
        (_zombie.hp_component as HpComponentZombie).grant_bonus_armor(_armor)
