## 三叶草吹动普通僵尸。只有飞行僵尸越过视野右边界时被清除。
extends RefCounted
class_name AdventureZombieWindGust

static func displacement_cells(flying: bool) -> int:
    return 4 if flying else 2

static func is_wind_elimination(flying: bool, dest_x: float, right_x: float) -> bool:
    return flying and dest_x > right_x

static func blow_all(manager: ZombieManager) -> void:
    var seen: Dictionary[int, bool] = {}
    var zombies: Array[Zombie000Base] = []
    for zombie: Zombie000Base in manager.all_zombies_1d:
        if is_instance_valid(zombie):
            zombies.append(zombie)
    for zombie: Zombie000Base in manager.all_zombies_be_hypno:
        if is_instance_valid(zombie):
            zombies.append(zombie)
    for zombie: Zombie000Base in zombies:
        if zombie.is_death or zombie.is_queued_for_deletion():
            continue
        var id: int = zombie.get_instance_id()
        if seen.has(id):
            continue
        seen[id] = true
        var flying: bool = zombie.curr_be_attack_status == Zombie000Base.E_BeAttackStatusZombie.IsSky
        blow_target(zombie, displacement_cells(flying), flying)

static func _cell_width(target: Character000Base) -> float:
    var game: MainGameManager = Global.main_game # 当前战场空间。
    if not is_instance_valid(game) or game.board == null:
        return 0.0
    return game.board.cell_width_at(target.global_position, target.lane)


static func _visible_right(target: Character000Base) -> float:
    var viewport: Viewport = target.get_viewport()
    var edge: Vector2 = Vector2(viewport.get_visible_rect().size.x, 0.0)
    return (viewport.get_canvas_transform().affine_inverse() * edge).x

## [param target] 被吹动的普通僵尸；[param cells] 击退格数；[param flying] 为 true 时可被吹出场。
static func blow_target(target: Zombie000Base, cells: int, flying: bool) -> void:
    if not is_instance_valid(target) or target.is_death or target.is_queued_for_deletion():
        return
    var width: float = _cell_width(target)
    if width <= 0.0 or cells <= 0:
        return
    # 吹动期间暂停目标自身的移动，结束后恢复。
    var move: MoveComponent = target.move_component
    if is_instance_valid(move):
        move.update_move_factor(true, MoveComponent.E_MoveFactor.IsBlover)
    var previous: Variant = target.get_meta(&"blover_tween", null)
    if previous is Tween and previous.is_running():
        (previous as Tween).kill()
    var dest: float = target.global_position.x + width * float(cells)
    var visible_right: float = _visible_right(target)
    if not flying and is_instance_valid(Global.main_game):
        var manager: ZombieManager = Global.main_game.zombie_manager as ZombieManager
        if is_instance_valid(manager):
            target.nonlethal_displacement_exile = (
                    dest > manager.zombie_range_pos_x.y)
    var tween: Tween = target.create_tween()
    target.set_meta(&"blover_tween", tween)
    tween.tween_property(target, ^"global_position:x", dest, 0.35)
    tween.finished.connect(func() -> void:
        if not is_instance_valid(target) or target.is_death:
            return
        target.remove_meta(&"blover_tween")
        if is_instance_valid(move):
            move.update_move_factor(false, MoveComponent.E_MoveFactor.IsBlover)
        if is_wind_elimination(flying, dest, visible_right):
            target.character_death_disappear())
