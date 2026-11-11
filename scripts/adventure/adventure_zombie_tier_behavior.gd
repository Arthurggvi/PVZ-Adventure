## Per-spawn trait dispatcher: events and lifecycle only, no duplicated hit logic.
extends Node
class_name AdventureZombieTierBehavior

var _zombie: Zombie000Base
var _rules: Array[Dictionary] = []
var _armor1_consumed := false
var _pole_rule: Dictionary = {}

func configure(rules: Array[Dictionary]) -> void:
    _rules = rules

func _ready() -> void:
    _zombie = get_parent() as Zombie000Base
    if _zombie == null or _rules.is_empty() or _zombie.adventure_tier_id == &"":
        return
    var watch_armor := false
    for rule: Dictionary in _rules:
        if rule.get("trigger", &"") == &"armor1_lost":
            watch_armor = true
        match StringName(rule.get("effect", &"")):
            &"flag_command":
                _start_flag_command.call_deferred(rule)
            &"pole_stance":
                _configure_pole(rule)
            &"self_reduction":
                (_zombie.get_node("HpComponent") as HpComponentZombie).damage_reduction.set_source(
                        get_instance_id(), float(rule.get("reduction", 0.0)))
            &"local_protection":
                _start_local_field.call_deferred(rule)
            &"timed_speed_boost", &"grant_armor_on_drop":
                pass
            _:
                var effect: StringName = StringName(rule.get("effect", &""))
                if AdventureZombieTierSpeciesInstaller.handles(effect):
                    AdventureZombieTierSpeciesInstaller.install.call_deferred(_zombie, rule)
                else:
                    push_error("Unknown zombie trait effect: %s" % effect)
    if watch_armor:
        var hp: HpComponentZombie = _zombie.get_node_or_null("HpComponent") as HpComponentZombie
        if hp == null or hp.max_hp_armor1 <= 0:
            push_error("Tier armor-loss effect requires armor1")
        else:
            hp.signal_armor1_death.connect(_on_armor1_lost)
    _zombie.signal_character_death.connect(_on_source_unavailable)
    _zombie.signal_character_be_hypno.connect(_on_source_unavailable)

func _manager() -> ZombieManager:
    var game = Global.main_game
    return game.zombie_manager as ZombieManager if is_instance_valid(game) else null

func _start_flag_command(rule: Dictionary) -> void:
    if not _can_act():
        return
    var manager := _manager()
    if manager == null:
        return
    var command := AdventureZombieFlagCommand.new()
    add_child(command)
    command.setup(_zombie, manager, rule)

func _start_local_field(rule: Dictionary) -> void:
    if not _can_act():
        return
    var manager := _manager()
    if manager == null:
        return
    var field := AdventureZombieTierField.new()
    add_child(field)
    field.setup(_zombie, manager, rule)

func _configure_pole(rule: Dictionary) -> void:
    var pole: Zombie004PoleVaulter = _zombie as Zombie004PoleVaulter
    if pole == null:
        push_error("Pole stance trait attached to wrong species")
        return
    _pole_rule = rule
    (pole.get_node("JumpComponent") as JumpComponent).max_jumps = maxi(1, int(rule.get("jumps", 1)))
    (pole.get_node("JumpComponent") as JumpComponent).jump_distance_cells = int(rule.get("jump_distance_cells", 0))
    var stance: float = float(rule.get("pole_speed", 1.0))
    _zombie.update_speed_factor(stance,
            Character000Base.E_Influence_Speed_Factor.AdventureTierStance)
    (_zombie.get_node("HpComponent") as HpComponentZombie).damage_reduction.set_source(
            get_instance_id(), float(rule.get("pole_dr", 0.0)))
    (pole.get_node("JumpComponent") as JumpComponent).signal_jump_end_end.connect(_on_pole_jump_finished)

func _on_pole_jump_finished() -> void:
    var pole: Zombie004PoleVaulter = _zombie as Zombie004PoleVaulter
    if pole == null or pole.jump_component.has_remaining_jumps():
        return
    _zombie.hp_component.damage_reduction.set_source(get_instance_id(), 0.0)
    _zombie.update_speed_factor(float(_pole_rule.get("after_speed", 1.0)),
            Character000Base.E_Influence_Speed_Factor.AdventureTierStance)

## Fire gear-loss effects synchronously: a lethal overflow may queue_free the
## source before a deferred callback, skipping one-shot neighboring benefits.
func _on_armor1_lost() -> void:
    if _armor1_consumed:
        return
    _armor1_consumed = true
    for rule: Dictionary in _rules:
        if rule.get("trigger", &"") != &"armor1_lost":
            continue
        match StringName(rule.get("effect", &"")):
            &"timed_speed_boost":
                if _can_act():
                    _apply_speed_boost(rule)
            &"grant_armor_on_drop":
                if _can_act():
                    _grant_nearby_armor(int(rule.get("amount", 0)))

func _apply_speed_boost(rule: Dictionary) -> void:
    var multiplier: float = float(rule.get("multiplier", 1.0))
    var duration: float = float(rule.get("duration", 0.0))
    AdventureZombieTimedSpeedBoost.apply_to(_zombie, multiplier, duration)
    var radius: int = int(rule.get("radius_cells", 0))
    if radius <= 0:
        return
    for ally: Zombie000Base in _nearby(radius):
        AdventureZombieTimedSpeedBoost.apply_to(ally, multiplier, duration)

func _grant_nearby_armor(amount: int) -> void:
    if amount <= 0:
        return
    if not _zombie.is_death:
        (_zombie.hp_component as HpComponentZombie).grant_bonus_armor(amount)
    for ally: Zombie000Base in _nearby(1):
        (ally.hp_component as HpComponentZombie).grant_bonus_armor(amount)

func _nearby(radius: int) -> Array[Zombie000Base]:
    var manager := _manager()
    if manager == null or _zombie.lane < 0:
        return []
    var width: float = manager.main_game.board.cell_width_at(_zombie.global_position, _zombie.lane) # 当前地点格宽。
    if width <= 0.0:
        return []
    return AdventureZombieTierNeighbors.allied_in_range(
            _zombie, manager.all_zombies_1d, width, radius)

func _can_act() -> bool:
    return is_instance_valid(_zombie) and not _zombie.is_death \
            and not _zombie.is_hypno and not _zombie.is_queued_for_deletion()

func _on_source_unavailable() -> void:
    if is_instance_valid(_zombie) and is_instance_valid(_zombie.hp_component):
        _zombie.hp_component.damage_reduction.set_source(get_instance_id(), 0.0)

func _exit_tree() -> void:
    _on_source_unavailable()
