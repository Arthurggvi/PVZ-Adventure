## Independent bite and invulnerability timers; no global singleton or shared cooldown.
extends Node
class_name AdventureZombieTimedCombatBuff

const NODE_NAME := "AdventureTimedCombatBuff"
var _zombie: Character000Base
var _bite: Array[Dictionary] = []
var _immunity: Array[Dictionary] = []
var _last_bite := 1.0
var _last_immunity := false

static func _for(target: Character000Base) -> AdventureZombieTimedCombatBuff:
    var current: AdventureZombieTimedCombatBuff = target.get_node_or_null(NODE_NAME) as AdventureZombieTimedCombatBuff
    if current == null:
        current = AdventureZombieTimedCombatBuff.new()
        current.name = NODE_NAME
        target.add_child(current)
    return current

static func grant_bite(target: Character000Base, multiplier: float, duration: float) -> void:
    if not is_instance_valid(target) or target.is_death or target.is_hypno \
            or multiplier <= 1.0 or duration <= 0.0:
        return
    _for(target)._add_bite(multiplier, duration)

## Source buffs end on allegiance change; innate species immunity can persist.
static func grant_immunity(target: Character000Base, duration: float,
        retain_on_hypno: bool = false) -> void:
    if not is_instance_valid(target) or target.is_death or duration <= 0.0 \
            or (target.is_hypno and not retain_on_hypno):
        return
    _for(target)._add_immunity(duration, retain_on_hypno)

func _ready() -> void:
    _zombie = get_parent() as Character000Base
    set_process(false)
    if _zombie != null:
        _zombie.signal_character_death.connect(clear)
        _zombie.signal_character_be_hypno.connect(_on_hypno)

func _add_bite(multiplier: float, duration: float) -> void:
    _bite.append({"value": multiplier, "time": duration})
    _sync()
    set_process(true)

func _add_immunity(duration: float, retain_on_hypno: bool) -> void:
    _immunity.append({"time": duration, "retain": retain_on_hypno})
    _sync()
    set_process(true)

func _process(delta: float) -> void:
    if not is_instance_valid(_zombie) or _zombie.is_death:
        clear()
        return
    for i in range(_bite.size() - 1, -1, -1):
        _bite[i]["time"] = float(_bite[i]["time"]) - delta
        if float(_bite[i]["time"]) <= 0:
            _bite.remove_at(i)
    for i in range(_immunity.size() - 1, -1, -1):
        var effect: Dictionary = _immunity[i]
        effect["time"] = float(effect["time"]) - delta
        if float(effect["time"]) <= 0.0:
            _immunity.remove_at(i)
        else:
            _immunity[i] = effect
    _sync()
    set_process(not _bite.is_empty() or not _immunity.is_empty())

func _sync() -> void:
    if not is_instance_valid(_zombie):
        return
    var bite := 1.0
    for effect: Dictionary in _bite:
        bite = maxf(bite, float(effect["value"]))
    if not is_equal_approx(bite, _last_bite):
        _last_bite = bite
        var attack: AttackComponentZombieNorm = _zombie.get_node_or_null("AttackComponent") as AttackComponentZombieNorm
        if attack != null:
            attack.update_attack_value(bite, AttackComponentZombieNorm.E_AttackValueFactor.AdventureBiteBoost)
    var immune := not _immunity.is_empty()
    if immune != _last_immunity:
        _last_immunity = immune
        _zombie.hp_component.set_immunity_source(get_instance_id(), immune)

func _on_hypno() -> void:
    _bite.clear()
    for i in range(_immunity.size() - 1, -1, -1):
        if not bool(_immunity[i].get("retain", false)):
            _immunity.remove_at(i)
    _sync()
    set_process(not _immunity.is_empty())

func clear() -> void:
    _bite.clear()
    _immunity.clear()
    _sync()
    set_process(false)

func _exit_tree() -> void:
    clear()
