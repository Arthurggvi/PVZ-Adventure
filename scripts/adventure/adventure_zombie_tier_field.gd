## Local bucket aura; reconcile movement and fresh spawns while maintaining source IDs.
extends Node
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
            or not is_instance_valid(_manager.main_game):
        return 0.0
    var grid: Array[Array] = _manager.main_game.plant_cell_manager.all_plant_cells
    if _source.lane < 0 or _source.lane >= grid.size():
        return 0.0
    var row: Array = grid[_source.lane]
    if row.is_empty() or not is_instance_valid(row[0]):
        return 0.0
    return (row[0] as PlantCell).size.x

func _refresh() -> void:
    if not is_instance_valid(_source) or not is_instance_valid(_manager) \
            or _source.is_death or _source.is_hypno:
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
    for id: int in _tracked.keys():
        _remove(id)

func _exit_tree() -> void:
    clear()
