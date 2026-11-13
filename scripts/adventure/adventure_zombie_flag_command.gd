## Flag aura: additive fixed block plus periodic global bite pulses and entry burst.
extends AdventureZombieTierAbility
class_name AdventureZombieFlagCommand

var _flag: Zombie000Base
var _manager: ZombieManager
var _aura: ZombieBlockAura
var _pulse_interval := 0.0
var _bite_multiplier := 1.0
var _bite_duration := 0.0
var _timer := 0.0
## 保存光环的原始格挡值，沉默期间暂时写零而保留来源登记。
var _block: int = 0

func setup(flag: Zombie000Base, manager: ZombieManager, rule: Dictionary) -> void:
    bind_tier(flag)
    _flag = flag
    _manager = manager
    _aura = ZombieBlockAura.new()
    add_child(_aura)
    _block = int(rule.get("block", 0))
    _aura.setup(manager, _block if tier_enabled() else 0, true)
    _pulse_interval = float(rule.get("interval", 0.0))
    _bite_multiplier = float(rule.get("bite_multiplier", 1.0))
    _bite_duration = float(rule.get("bite_duration", 0.0))
    set_process(_pulse_interval > 0.0)
    _flag.signal_character_death.connect(clear)
    _flag.signal_character_be_hypno.connect(clear)
    var spawn_speed: float = float(rule.get("spawn_speed", 1.0))
    var spawn_immunity: float = float(rule.get("spawn_immunity", 0.0))
    if tier_can_grant_entry() and (spawn_speed > 1.0 or spawn_immunity > 0.0):
        _for_all(func(z: Character000Base) -> void:
            if spawn_speed > 1.0:
                AdventureZombieTimedSpeedBoost.apply_to(z, spawn_speed, spawn_immunity, z == _flag)
            AdventureZombieTimedCombatBuff.grant_immunity(z, spawn_immunity, false, z == _flag)
        )

## [param delta] 为本帧游戏秒数，行动受控时暂停主动发出的号令。
func _process(delta: float) -> void:
    if not is_instance_valid(_flag) or _flag.is_death or _flag.is_hypno:
        clear()
        return
    if _flag.is_action_suspended():
        return
    _timer += delta
    while _timer >= _pulse_interval:
        _timer -= _pulse_interval
        pulse()

func pulse() -> void:
    if not tier_can_trigger():
        return
    if _bite_multiplier <= 1.0:
        return
    _for_all(func(z: Character000Base) -> void:
        AdventureZombieTimedCombatBuff.grant_bite(z, _bite_multiplier, _bite_duration, z == _flag)
    )

func _for_all(callback: Callable) -> void:
    if not is_instance_valid(_manager):
        return
    for z: Zombie000Base in _manager.all_zombies_1d:
        if is_instance_valid(z) and not z.is_death and not z.is_hypno:
            callback.call(z)
    for boss: ZB000Base in _manager.get_living_bosses():
        if is_instance_valid(boss) and not boss.is_death and not boss.is_hypno:
            callback.call(boss)

## [param active] 撤销或恢复格挡，保留号令计时且不再次授予入场奖励。
func _tier_state_changed(active: bool) -> void:
    if is_instance_valid(_aura):
        _aura.set_amount(_block if active and is_instance_valid(_flag) and not _flag.is_death and not _flag.is_hypno else 0)

func clear() -> void:
    set_process(false)
    if is_instance_valid(_aura):
        _aura.clear()

func _exit_tree() -> void:
    if is_instance_valid(_flag) and _flag.is_changing_lane:
        return
    clear()
