## Jackson-specific lifecycle. Existing JacksonManager remains the only summon loop.
extends Node
class_name AdventureZombieJacksonCommand

var _leader: Zombie009Jackson
var _rule: Dictionary
var _manager: JacksonManager
var _heal_clock := 0.0
var _summoned := false

func setup(leader: Zombie009Jackson, rule: Dictionary) -> void:
    _leader = leader
    _rule = rule
    leader.dance_manager_replaced.connect(_on_manager_replaced)
    _on_manager_replaced(leader.jackson_manager)
    if _manager == null:
        return
    var hp: HpComponentZombie = leader.hp_component as HpComponentZombie
    hp.grant_bonus_armor(int(rule.get("spawn_armor", 0)))
    hp.damage_reduction.set_source(get_instance_id(),
            float(rule.get("pre_summon_dr", 0.0)))
    leader.signal_character_death.connect(_on_death)
    set_process(int(rule.get("heal_per_second", 0)) > 0)

func _on_manager_replaced(manager: JacksonManager) -> void:
    if is_instance_valid(_manager) and _manager.reinforcements_called.is_connected(_on_reinforcements):
        _manager.reinforcements_called.disconnect(_on_reinforcements)
    _manager = manager
    if is_instance_valid(_manager):
        _manager.configure_summon_policy(_rule)
        _manager.reinforcements_called.connect(_on_reinforcements)

func _on_reinforcements() -> void:
    if _summoned:
        return
    _summoned = true
    if is_instance_valid(_leader):
        _leader.hp_component.damage_reduction.set_source(get_instance_id(), 0.0)

func _process(delta: float) -> void:
    if not is_instance_valid(_leader) or _leader.is_death:
        set_process(false)
        return
    _heal_clock += delta
    while _heal_clock >= 1.0:
        _heal_clock -= 1.0
        var hp: HpComponentZombie = _leader.hp_component as HpComponentZombie
        hp.heal(int(_rule.get("heal_per_second", 0)))

func _on_death() -> void:
    set_process(false)
    if not bool(_rule.get("death_dancer", false)):
        return
    var game: MainGameManager = Global.main_game
    if not is_instance_valid(game) or not is_instance_valid(_leader):
        return
    var manager: ZombieManager = game.zombie_manager
    var lane: int = _leader.lane
    if lane < 0 or lane >= manager.all_zombie_rows.size():
        return
    var attrs: Dictionary = {
        Zombie000Base.E_ZInitAttr.CharacterInitType: Character000Base.E_CharacterInitType.IsNorm,
        Zombie000Base.E_ZInitAttr.Lane: lane,
        Zombie000Base.E_ZInitAttr.ParticipatesNaturalRefresh: false,
    }
    var child: Zombie000Base = manager.create_norm_zombie(
        CharacterRegistry.ZombieType.Z010Dancer, manager.all_zombie_rows[lane],
        attrs, _leader.global_position, Callable(self, "_mark_death_summon"),
        _leader.inherited_child_modifier())
    if is_instance_valid(child) and _leader.is_hypno:
        child.be_hypno()

func _mark_death_summon(zombie: Zombie010Dancer) -> void:
    zombie.init_independent_reinforcement()

func _exit_tree() -> void:
    if is_instance_valid(_leader) and is_instance_valid(_leader.hp_component):
        _leader.hp_component.damage_reduction.set_source(get_instance_id(), 0.0)
