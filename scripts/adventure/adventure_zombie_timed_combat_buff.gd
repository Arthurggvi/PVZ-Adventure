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

## [param target] 获得 [param multiplier] 倍、持续 [param duration] 秒的啃咬增益；[param tier_owned] 显式标记自身等阶来源。
static func grant_bite(target: Character000Base, multiplier: float, duration: float, tier_owned: bool = false) -> void:
    if not is_instance_valid(target) or target.is_death or target.is_hypno \
            or multiplier <= 1.0 or duration <= 0.0:
        return
    _for(target)._add_bite(multiplier, duration, tier_owned)

## 为 [param target] 授予 [param duration] 秒免疫；[param retain_on_hypno] 独立控制换阵营后的保留。
## [param tier_owned] 明确标记目标自身的等阶能力，沉默时遮蔽免疫并暂停剩余时间。
static func grant_immunity(target: Character000Base, duration: float,
        retain_on_hypno: bool = false, tier_owned: bool = false) -> void:
    if not is_instance_valid(target) or target.is_death or duration <= 0.0 \
            or (target.is_hypno and not retain_on_hypno):
        return
    _for(target)._add_immunity(duration, retain_on_hypno, tier_owned)

func _ready() -> void:
    _zombie = get_parent() as Character000Base
    set_process(false)
    if _zombie != null:
        _zombie.signal_character_death.connect(clear)
        _zombie.signal_character_be_hypno.connect(_on_hypno)
        if _zombie is Zombie000Base:
            (_zombie as Zombie000Base).signal_tier_skills_changed.connect(_on_tier_changed)

## 保存 [param multiplier]、[param duration] 和来源归属 [param tier_owned]，各记录独立计时。
func _add_bite(multiplier: float, duration: float, tier_owned: bool) -> void:
    _bite.append({"value": multiplier, "time": duration, "tier_owned": tier_owned})
    _sync()
    set_process(true)

## 保存 [param duration]、[param retain_on_hypno] 和 [param tier_owned] 三种独立语义。
func _add_immunity(duration: float, retain_on_hypno: bool, tier_owned: bool) -> void:
    _immunity.append({"time": duration, "retain": retain_on_hypno, "tier_owned": tier_owned})
    _sync()
    set_process(true)

func _process(delta: float) -> void:
    if not is_instance_valid(_zombie) or _zombie.is_death:
        clear()
        return
    for i in range(_bite.size() - 1, -1, -1): # 倒序删除到期增益，自身被沉默的来源暂停计时。
        if _effect_suppressed(_bite[i]):
            continue
        _bite[i]["time"] = float(_bite[i]["time"]) - delta
        if float(_bite[i]["time"]) <= 0:
            _bite.remove_at(i)
    for i in range(_immunity.size() - 1, -1, -1):
        var effect: Dictionary = _immunity[i] # 独立免疫记录，沉默只暂停目标自身的等阶来源。
        if _effect_suppressed(effect):
            continue
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
    for effect: Dictionary in _bite: # 同一通道取当前有效记录的最大倍率。
        if not _effect_suppressed(effect):
            bite = maxf(bite, float(effect["value"]))
    if not is_equal_approx(bite, _last_bite):
        _last_bite = bite
        var attack: AttackComponentZombieNorm = _zombie.get_node_or_null("AttackComponent") as AttackComponentZombieNorm
        if attack != null:
            attack.update_attack_value(bite, AttackComponentZombieNorm.E_AttackValueFactor.AdventureBiteBoost)
    var immune := false # 外部已经授予的免疫仍生效，自身等阶免疫按当前资格组合。
    for effect: Dictionary in _immunity: # 任一未被沉默遮蔽的来源即可免疫。
        if not _effect_suppressed(effect):
            immune = true
            break
    if immune != _last_immunity:
        _last_immunity = immune
        _zombie.hp_component.set_immunity_source(get_instance_id(), immune)

## 返回 [param effect] 是否为当前被沉默遮蔽的自身等阶增益，和魅惑保留规则无关。
func _effect_suppressed(effect: Dictionary) -> bool:
    return bool(effect.get("tier_owned", false)) and _zombie is Zombie000Base \
            and not (_zombie as Zombie000Base).are_tier_skills_active()

## [param _active] 变化时即时撤销或恢复来源，剩余计时不会从头开始。
func _on_tier_changed(_active: bool) -> void:
    _sync()

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
    if _zombie is Zombie000Base and (_zombie as Zombie000Base).is_changing_lane:
        return
    clear()
