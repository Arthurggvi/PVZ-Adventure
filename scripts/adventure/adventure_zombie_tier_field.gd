## Local bucket aura; reconcile movement and fresh spawns while maintaining source IDs.
extends AdventureZombieTierAbility
class_name AdventureZombieTierField

const INTERVAL := 0.12
var _source: Zombie000Base
var _manager: ZombieManager
var _neighbor_dr := 0.0
var _self_dr := 0.0
var _redirect := false
var _elapsed := 0.0
var _tracked: Dictionary[int, WeakRef] = {}

func setup(source: Zombie000Base, manager: ZombieManager, rule: Dictionary) -> void:
    bind_tier(source)
    _source = source
    _manager = manager
    _neighbor_dr = float(rule.get("reduction", 0.0))
    _self_dr = float(rule.get("self_reduction", _neighbor_dr))
    _redirect = bool(rule.get("redirect", false))
    _manager.signal_zombie_created.connect(_on_spawned)
    _source.signal_character_death.connect(clear)
    _source.signal_character_be_hypno.connect(clear)
    _refresh()
    set_process(true)

func _process(delta: float) -> void:
    _elapsed += delta
    if _elapsed >= INTERVAL:
        _elapsed = 0.0
        _refresh()

func _on_spawned(_zombie: Zombie000Base) -> void:
    _refresh.call_deferred()

func _width() -> float:
    if not is_instance_valid(_source) or not is_instance_valid(_manager) \
            or not is_instance_valid(_manager.main_game) or _manager.main_game.board == null:
        return 0.0
    return _manager.main_game.board.cell_width_at(_source.global_position, _source.lane)


func _refresh() -> void:
    if not tier_enabled():
        _remove_all_sources()
        return
    if not is_instance_valid(_source) or not is_instance_valid(_manager) \
            or not _source.is_inside_tree() or _source.is_queued_for_deletion() \
            or not is_instance_valid(_manager.main_game) or _manager.main_game != Global.main_game \
            or not _manager.main_game.is_inside_tree() or _manager.main_game.is_queued_for_deletion() \
            or not _manager.main_game.is_ancestor_of(_source) or _source.is_death or _source.is_hypno:
        clear()
        return
    var width := _width()
    if width <= 0.0:
        return
    var eligible: Dictionary[int, bool] = {}
    var allies: Array[Zombie000Base] = AdventureZombieTierNeighbors.allied_in_range(
            _source, _manager.all_zombies_1d, width, 1)
    allies.append(_source)
    for ally: Zombie000Base in allies:
        if not is_instance_valid(ally) or ally.is_death or ally.is_hypno:
            continue
        var id := ally.get_instance_id()
        eligible[id] = true
        if not _tracked.has(id):
            _tracked[id] = weakref(ally)
        var reduction: float = _self_dr if ally == _source else _neighbor_dr
        ally.hp_component.damage_reduction.set_source(get_instance_id(), reduction)
        ally.hp_component.damage_transfer.set_source(get_instance_id(),
                _source if _redirect and ally != _source else null, width)
    for id: int in _tracked.keys():
        if not eligible.has(id):
            _remove(id)

func _remove(id: int) -> void:
    if not _tracked.has(id):
        return
    var zombie: Zombie000Base = _tracked[id].get_ref() as Zombie000Base
    if is_instance_valid(zombie) and is_instance_valid(zombie.hp_component):
        zombie.hp_component.damage_reduction.set_source(get_instance_id(), 0.0)
        zombie.hp_component.damage_transfer.set_source(get_instance_id(), null)
    _tracked.erase(id)

func clear() -> void:
    set_process(false)
    if is_instance_valid(_manager) and _manager.signal_zombie_created.is_connected(_on_spawned):
        _manager.signal_zombie_created.disconnect(_on_spawned)
    _remove_all_sources()

## 只撤销输出，不断开出生监听或重置刷新计时，供沉默临时使用。
func _remove_all_sources() -> void:
    for id: int in _tracked.keys(): # 来源键快照允许边遍历边撤销。
        _remove(id)

## [param active] 恢复时立即按当前邻居重算，不沿用沉默前的过期范围快照。
func _tier_state_changed(active: bool) -> void:
    if active:
        _refresh()
    else:
        _remove_all_sources()

func _exit_tree() -> void:
    if is_instance_valid(_source) and _source.is_changing_lane:
        return
    clear()
