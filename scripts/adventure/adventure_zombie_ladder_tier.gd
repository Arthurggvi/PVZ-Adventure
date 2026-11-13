extends AdventureZombieTierAbility
class_name AdventureZombieLadderTier

var _zombie: Zombie022Ladder
var _aura := 1.0
var _duration := 0.0

func setup(zombie: Zombie022Ladder, rule: Dictionary) -> void:
    bind_tier(zombie)
    _zombie = zombie
    _aura = float(rule.get("aura_speed", 1.0))
    _duration = float(rule.get("aura_seconds", 0.0))
    set_tier_property(zombie, &"allow_any_ladder_target", bool(rule.get("all_plants", false)))
    set_tier_defense(&"armor2_reduction", float(rule.get("gear_reduction", 0.0)))
    zombie.ladder_placed.connect(_on_ladder_placed)

func _on_ladder_placed(_plant: Plant000Base, _ladder: Ladder) -> void:
    if not tier_can_trigger():
        return
    if _aura <= 1.0 or _duration <= 0.0 or not is_instance_valid(Global.main_game):
        return
    var cell_width: float = Global.main_game.board.cell_width_at(_zombie.global_position, _zombie.lane) # 当前地点格宽。
    if cell_width <= 0.0:
        return
    for ally: Zombie000Base in AdventureZombieTierNeighbors.allied_in_range(
            _zombie, Global.main_game.zombie_manager.all_zombies_1d, cell_width, 1):
        AdventureZombieTimedSpeedBoost.apply_to(ally, _aura, _duration)
