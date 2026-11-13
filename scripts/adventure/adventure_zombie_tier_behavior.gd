## Per-spawn trait dispatcher: events and lifecycle only, no duplicated hit logic.
extends AdventureZombieTierAbility
class_name AdventureZombieTierBehavior

var _zombie: Zombie000Base
var _rules: Array[Dictionary] = []
var _armor1_consumed := false
var _pole_rule: Dictionary = {}
## 出生事件的战场身份，仅用于一次性入场奖励，永久能力不按旧阶段锁死。
var _entry_game: MainGameManager
## 出生事件所在轮次。
var _entry_round: int = -1
## 出生事件所在冒险阶段，防止 deferred 在续战后补发旧奖励。
var _entry_phase: StagePhaseDefinition

func configure(rules: Array[Dictionary]) -> void:
    _rules = rules

func _ready() -> void:
    _zombie = get_parent() as Zombie000Base
    if _zombie == null or _rules.is_empty() or _zombie.adventure_tier_id == &"":
        return
    bind_tier(_zombie)
    _entry_game = Global.main_game
    if is_instance_valid(_entry_game):
        _entry_round = _entry_game.curr_game_round
        _entry_phase = AdventureSession.get_active_phase(_entry_game.game_para)
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
                set_tier_defense(&"damage_reduction", float(rule.get("reduction", 0.0)))
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
    if not _can_initialize():
        return
    var manager := _manager()
    if manager == null:
        return
    var command := AdventureZombieFlagCommand.new()
    add_child(command)
    command.setup(_zombie, manager, rule)

func _start_local_field(rule: Dictionary) -> void:
    if not _can_initialize():
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
    set_tier_property(pole.get_node("JumpComponent"), &"jump_distance_cells", int(rule.get("jump_distance_cells", 0)))
    _sync_pole_outputs()
    (pole.get_node("JumpComponent") as JumpComponent).signal_jump_end_end.connect(_on_pole_jump_finished)

## 原生跳跃完成仍更新阶段；沉默期间只保存期望输出而不生效。
func _on_pole_jump_finished() -> void:
    _sync_pole_outputs()

## 按未消费的真实跳跃次数和当前装备阶段更新撑杆持续输出。
func _sync_pole_outputs() -> void:
    var pole: Zombie004PoleVaulter = _zombie as Zombie004PoleVaulter # 其他物种不使用撑杆分支。
    if pole == null:
        return
    var jump: JumpComponent = pole.get_node("JumpComponent") as JumpComponent # 可在角色 ready 前配置。
    var has_pole: bool = not jump.is_jump_stop and jump.completed_jumps < jump.max_jumps # 不借沉默恢复已经被高坚果消费的跳跃。
    set_tier_defense(&"damage_reduction", float(_pole_rule.get("pole_dr", 0.0)) if has_pole and not pole.is_hypno else 0.0)
    set_tier_speed(float(_pole_rule.get("pole_speed" if has_pole else "after_speed", 1.0)))

## [param _active] 变化时重算原生检测器与跑步状态，不重新装备撑杆或重置跳跃计数。
func _tier_state_changed(_active: bool) -> void:
    if _pole_rule.is_empty() or not _can_initialize():
        return
    _sync_pole_outputs()
    var pole: Zombie004PoleVaulter = _zombie as Zombie004PoleVaulter # 已由规则类型验证的撑杆僵尸。
    var jump: JumpComponent = pole.jump_component # 正在空中时让原生落地回调完成状态切换。
    if jump.is_jumping or jump.is_landing:
        return
    if jump.has_remaining_jumps():
        pole.detect_component.disable_component(ComponentNormBase.E_IsEnableFactor.Jump)
        pole.is_trigger_squash_pos_judge = true
        pole.is_trigger_tall_nut_stop_jump = true
        pole._resume_pole_run.call_deferred()
    else:
        jump.disable_component(ComponentNormBase.E_IsEnableFactor.Jump)
        pole.detect_component.enable_component(ComponentNormBase.E_IsEnableFactor.Jump)

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
    AdventureZombieTimedSpeedBoost.apply_to(_zombie, multiplier, duration, true)
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

## 初始化即使遇到沉默也登记能力，防止 deferred 安装永久丢失。
func _can_initialize() -> bool:
    var game: MainGameManager = Global.main_game # 状态绑定可跨本场景阶段，不能跨到另一战场。
    return is_instance_valid(_zombie) and _zombie.is_inside_tree() and not _zombie.is_death \
            and not _zombie.is_hypno and not _zombie.is_queued_for_deletion() \
            and is_instance_valid(game) and game.is_inside_tree() and not game.is_queued_for_deletion() \
            and game.is_ancestor_of(_zombie)

## 只允许原出生场景、轮次和阶段的一次性奖励，永久配置与光环仍可正常绑定。
func allows_entry_reward() -> bool:
    return _can_initialize() and _entry_game == Global.main_game \
            and _entry_game.curr_game_round == _entry_round \
            and AdventureSession.get_active_phase(_entry_game.game_para) == _entry_phase

## 离散技能触发还需要等阶资格，沉默结束后不补发过去事件。
func _can_act() -> bool:
    return _can_initialize() and tier_enabled()

func _on_source_unavailable() -> void:
    if is_instance_valid(_zombie) and is_instance_valid(_zombie.hp_component):
        set_tier_defense(&"damage_reduction", 0.0)

func _exit_tree() -> void:
    if is_instance_valid(_zombie) and _zombie.is_changing_lane:
        return
    _on_source_unavailable()
