## Flag aura: additive fixed block plus periodic global bite pulses and entry burst.
extends Node
class_name AdventureZombieFlagCommand

var _flag: Zombie000Base
var _manager: ZombieManager
var _aura: ZombieBlockAura
var _pulse_interval := 0.0
var _bite_multiplier := 1.0
var _bite_duration := 0.0
var _timer := 0.0

func setup(flag: Zombie000Base, manager: ZombieManager, rule: Dictionary) -> void:
    _flag = flag
    _manager = manager
    _aura = ZombieBlockAura.new()
    add_child(_aura)
    _aura.setup(manager, int(rule.get("block", 0)), true)
    _pulse_interval = float(rule.get("interval", 0.0))
    _bite_multiplier = float(rule.get("bite_multiplier", 1.0))
    _bite_duration = float(rule.get("bite_duration", 0.0))
    set_process(_pulse_interval > 0.0)
    _flag.signal_character_death.connect(clear)
    _flag.signal_character_be_hypno.connect(clear)
    var spawn_speed: float = float(rule.get("spawn_speed", 1.0))
    var spawn_immunity: float = float(rule.get("spawn_immunity", 0.0))
    if spawn_speed > 1.0 or spawn_immunity > 0.0:
        _for_all(func(z: Character000Base) -> void:
            if spawn_speed > 1.0:
                AdventureZombieTimedSpeedBoost.apply_to(z, spawn_speed, spawn_immunity)
            AdventureZombieTimedCombatBuff.grant_immunity(z, spawn_immunity)
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
    if _bite_multiplier <= 1.0:
        return
    _for_all(func(z: Character000Base) -> void:
        AdventureZombieTimedCombatBuff.grant_bite(z, _bite_multiplier, _bite_duration)
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

func clear() -> void:
    set_process(false)
    if is_instance_valid(_aura):
        _aura.clear()

func _exit_tree() -> void:
    clear()
