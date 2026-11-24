extends AdventureZombieTierAbility
class_name AdventureZombiePogoTier

var _pogo: Zombie019Pogo
var _damage := 0

func setup(zombie: Zombie019Pogo, rule: Dictionary) -> void:
    bind_tier(zombie)
    _pogo = zombie
    _damage = int(rule.get("jump_damage", 0))
    set_tier_property(zombie, &"big_jump_cells", int(rule.get("jump_cells", 0)))
    zombie.signal_big_jump_landed.connect(_on_jump_landed)
    if tier_can_grant_entry():
        (zombie.hp_component as HpComponentZombie).grant_bonus_armor(
                int(rule.get("spawn_armor", 0)))
    set_tier_speed(float(rule.get("speed", 1.0)))

func _on_jump_landed(before_x: float, after_x: float) -> void:
    if not tier_can_trigger():
        return
    if not is_instance_valid(_pogo) or _pogo.is_death or _pogo.is_hypno or _pogo.is_action_suspended():
        return
    AdventureZombieLaneImpact.hit_plants(
            _pogo.lane, before_x, after_x, _damage, false, {}, _pogo)
