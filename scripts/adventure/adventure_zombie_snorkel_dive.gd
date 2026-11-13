## Underwater-only movement and one-second shield accrual.
extends AdventureZombieTierAbility
class_name AdventureZombieSnorkelDive

var _zombie: Zombie012Snorkle
var _speed := 1.0
var _armor := 0
var _diving := false
var _seconds := 0.0

func setup(zombie: Zombie012Snorkle, rule: Dictionary) -> void:
    bind_tier(zombie)
    _zombie = zombie
    _speed = float(rule.get("dive_speed", 1.0))
    _armor = int(rule.get("armor_per_second", 0))
    set_process(true)

## [param active] 恢复时先按当前游泳状态更新速度，不补发沉默期间的护甲生产。
func _tier_state_changed(active: bool) -> void:
    if active and is_instance_valid(_zombie):
        var underwater: bool = _zombie.is_swimming and _zombie.curr_be_attack_status == Zombie000Base.E_BeAttackStatusZombie.IsDownPool # 原生游泳仍可在沉默时变化。
        set_tier_speed(_speed if underwater else 1.0)

func _process(delta: float) -> void:
    if not is_instance_valid(_zombie) or _zombie.is_death:
        set_process(false)
        return
    var underwater: bool = _zombie.is_swimming and (
            _zombie.curr_be_attack_status == Zombie000Base.E_BeAttackStatusZombie.IsDownPool)
    if underwater != _diving:
        _diving = underwater
        _seconds = 0.0
        set_tier_speed(_speed if underwater else 1.0)
    if not underwater or _armor <= 0:
        return
    _seconds += delta
    while _seconds >= 1.0:
        _seconds -= 1.0
        (_zombie.hp_component as HpComponentZombie).grant_bonus_armor(_armor)
