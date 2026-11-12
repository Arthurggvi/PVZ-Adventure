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
    var width: float = _cell_width(target) # 当前行附近一格的像素宽度。
    if width <= 0.0 or cells <= 0 or not is_instance_valid(target.move_component):
        return
    var visible_right: float = _visible_right(target) # 本次吹飞允许清除气球的屏幕边界。
    target.move_component.apply_forced_displacement(Vector2(width * float(cells), 0.0), 0.35, 0.0,
        func() -> void:
            if is_wind_elimination(flying, target.global_position.x, visible_right):
                target.character_death_disappear())
