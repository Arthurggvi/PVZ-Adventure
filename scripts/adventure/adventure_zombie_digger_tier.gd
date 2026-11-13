## Mining and surface walking use one owned speed channel, never multiply
## two stage bonuses at once. Surface immediate-walk uses native signal.
extends AdventureZombieTierAbility
class_name AdventureZombieDiggerTier

var _miner: Zombie018Digger
var _dig_speed := 1.0
var _walk_speed := 1.0
var _last_speed := -1.0
var _instant := false

func setup(miner: Zombie018Digger, rule: Dictionary) -> void:
    bind_tier(miner)
    _miner = miner
    _dig_speed = float(rule.get("dig_speed", 1.0))
    _walk_speed = float(rule.get("walk_speed", 1.0))
    _instant = bool(rule.get("instant_walk", false))
    if _instant:
        miner.signal_digger_surfaced.connect(_on_surfaced)
    var death_damage: int = int(rule.get("death_blast", 0))
    if death_damage > 0:
        var blast := AdventureZombieDeathBurst.new()
        miner.add_child(blast)
        blast.setup(miner, death_damage, AdventureZombieTierExplosionGeometry.small_radius(miner, 1))
    _sync_speed()

func _process(_delta: float) -> void:
    if not is_instance_valid(_miner) or _miner.is_death:
        set_process(false)
        return
    _sync_speed()

func _sync_speed() -> void:
    if not is_instance_valid(_miner):
        return
    var factor: float = _dig_speed if _miner.is_dig else _walk_speed
    if not is_equal_approx(_last_speed, factor):
        _last_speed = factor
        set_tier_speed(factor)

## [param active] 恢复时按当前地下或地面阶段重算动作倍率。
func _tier_state_changed(active: bool) -> void:
    if active:
        _last_speed = -1.0
        _sync_speed()

func _on_surfaced() -> void:
    if not tier_can_trigger():
        return
    if not is_instance_valid(_miner) or _miner.is_death:
        return
    _miner.update_direction_x_root(-1) # Existing miner rightward walking.
    _miner.move_component.update_move_mode(MoveComponent.E_MoveMode.Speed)
    _miner.move_component.update_move_factor(false, MoveComponent.E_MoveFactor.IsAnimGap)
    _miner.attack_component.enable_component(ComponentNormBase.E_IsEnableFactor.DownGround)
    _sync_speed()
