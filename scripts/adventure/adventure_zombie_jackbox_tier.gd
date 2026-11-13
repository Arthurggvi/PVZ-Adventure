## Jackbox uses its native pop animation; only trigger policy is tier-specific.
extends AdventureZombieTierAbility
class_name AdventureZombieJackboxTier

const PROFILE := preload("res://resources/combat/jackbox_explosion_profile.tres")

var _jackbox: Zombie016Jackbox
var _bite_time := 0.0
var _fuse := 0.0
var _contact := false

func setup(jackbox: Zombie016Jackbox, rule: Dictionary) -> void:
    bind_tier(jackbox)
    _jackbox = jackbox
    _fuse = float(rule.get("bite_fuse", 0.0))
    _contact = bool(rule.get("on_plant_contact", false))
    var blast: int = int(rule.get("blast", 8000))
    set_tier_property(jackbox.bomb_component_jackbox, &"use_numeric_blast", true)
    set_tier_property(jackbox.bomb_component_jackbox, &"bomb_value", blast)
    # 原生随机引信保留进度：技能启用时暂停，沉默时恢复原生引信；不重抽或重启。
    set_tier_property(jackbox.bomb_component_jackbox.jack_bomb_timer, &"manual_paused", true)
    set_tier_property(jackbox, &"survive_first_explosion", bool(rule.get("survive_first", false)))
    set_tier_speed(float(rule.get("speed", 1.0)))
    if bool(rule.get("survive_first", false)):
        var afterlife := AdventureZombieDeathBurst.new()
        jackbox.add_child(afterlife)
        afterlife.setup(jackbox, blast, PROFILE, true, true)
        afterlife.disarm()
        jackbox.signal_first_jackbox_blast_survived.connect(afterlife.arm)

## [param delta] 为本帧游戏秒数，行动受控时暂停接触引爆和啃咬引信。
func _process(delta: float) -> void:
    if not is_instance_valid(_jackbox) or _jackbox.is_death or _jackbox.is_pop \
            or _jackbox.first_explosion_survived:
        set_process(false)
        return
    if _jackbox.is_action_suspended():
        return
    var attack: AttackComponentZombieNorm = _jackbox.attack_component as AttackComponentZombieNorm
    var target: Node = attack.detect_component.enemy_can_be_attacked
    var touching: bool = target is Plant000Base and is_instance_valid(target) \
            and not (target as Plant000Base).is_death
    if not touching:
        _bite_time = 0.0
        return
    if _contact:
        _jackbox._strigger_bomb()
        set_process(false)
    elif attack.is_attack_res and _fuse > 0.0:
        _bite_time += delta
        if _bite_time > _fuse:
            _jackbox._strigger_bomb()
            set_process(false)
    else:
        _bite_time = 0.0
