## Reusable swept-lane plant impact: vehicles flatten; riders deal numeric damage.
## Traverse grid cells by actual terrain width rather than fixed sprite pixel sizes.
extends RefCounted
class_name AdventureZombieLaneImpact

static func hit_plants(lane: int, before_x: float, after_x: float,
        damage: int, flatten: bool, impacted: Dictionary[int, bool]) -> int:
    if not flatten and damage <= 0:
        return 0
    var game: MainGameManager = Global.main_game
    if not is_instance_valid(game) or not is_instance_valid(game.plant_cell_manager):
        return 0
    var rows: Array[Array] = game.plant_cell_manager.all_plant_cells
    if lane < 0 or lane >= rows.size():
        return 0
    var count := 0
    for entry: Variant in rows[lane]:
        var cell: PlantCell = entry as PlantCell
        if not is_instance_valid(cell):
            continue
        var center: float = cell.global_position.x + cell.size.x * 0.5
        if center < minf(before_x, after_x) - cell.size.x * 0.5 \
                or center > maxf(before_x, after_x) + cell.size.x * 0.5:
            continue
        for plant: Plant000Base in cell.plant_in_cell.values():
            if not is_instance_valid(plant) or plant.is_death or plant.is_queued_for_deletion():
                continue
            var id: int = plant.get_instance_id()
            if impacted.has(id):
                continue
            impacted[id] = true
            if flatten:
                plant.be_flattened()
            else:
                plant.be_attacked_bullet(
                        damage, BulletRegistry.AttackMode.Penetration, true, false)
            count += 1
    return count
