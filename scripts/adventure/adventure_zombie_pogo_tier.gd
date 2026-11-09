extends Node
class_name AdventureZombiePogoTier

var _pogo: Zombie019Pogo
var _damage := 0

func setup(zombie: Zombie019Pogo, rule: Dictionary) -> void:
    _pogo = zombie
    _damage = int(rule.get("jump_damage", 0))
    zombie.big_jump_cells = int(rule.get("jump_cells", 0))
    zombie.signal_big_jump_landed.connect(_on_jump_landed)
    (zombie.hp_component as HpComponentZombie).grant_bonus_armor(
            int(rule.get("spawn_armor", 0)))
    zombie.update_speed_factor(float(rule.get("speed", 1.0)),
            Character000Base.E_Influence_Speed_Factor.AdventureTierStance)

func _on_jump_landed(before_x: float, after_x: float) -> void:
    if not is_instance_valid(_pogo) or _pogo.is_death or _pogo.is_hypno:
        return
    AdventureZombieLaneImpact.hit_plants(
            _pogo.lane, before_x, after_x, _damage, false, {})
