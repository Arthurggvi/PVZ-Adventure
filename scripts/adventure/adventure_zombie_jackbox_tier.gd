## Jackbox uses its native pop animation; only trigger policy is tier-specific.
extends Node
class_name AdventureZombieJackboxTier

const PROFILE := preload("res://resources/combat/jackbox_explosion_profile.tres")

var _jackbox: Zombie016Jackbox
var _bite_time := 0.0
var _fuse := 0.0
var _contact := false

func setup(jackbox: Zombie016Jackbox, rule: Dictionary) -> void:
    _jackbox = jackbox
    _fuse = float(rule.get("bite_fuse", 0.0))
    _contact = bool(rule.get("on_plant_contact", false))
    var blast: int = int(rule.get("blast", 8000))
    jackbox.bomb_component_jackbox.use_numeric_blast = true
    jackbox.bomb_component_jackbox.bomb_value = blast
    jackbox.bomb_component_jackbox.jack_bomb_timer.stop()
    jackbox.survive_first_explosion = bool(rule.get("survive_first", false))
    jackbox.update_speed_factor(float(rule.get("speed", 1.0)),
            Character000Base.E_Influence_Speed_Factor.AdventureTierStance)
    if jackbox.survive_first_explosion:
        var afterlife := AdventureZombieDeathBurst.new()
        jackbox.add_child(afterlife)
        afterlife.setup(jackbox, blast, PROFILE, true, true)
        afterlife.disarm()
        jackbox.signal_first_jackbox_blast_survived.connect(afterlife.arm)

func _process(delta: float) -> void:
    if not is_instance_valid(_jackbox) or _jackbox.is_death or _jackbox.is_pop \
            or _jackbox.first_explosion_survived:
        set_process(false)
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
