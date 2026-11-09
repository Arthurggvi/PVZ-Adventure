## Scene-independent geometry factory: a radius of 1 spans 3 x 3 grid cells.
extends RefCounted
class_name AdventureZombieTierExplosionGeometry

const TEMPLATE := preload("res://resources/combat/jackbox_explosion_profile.tres")

static func small_radius(source: Zombie000Base, radius: int) -> CombatExplosionProfile:
    var profile: CombatExplosionProfile = TEMPLATE.duplicate(true) as CombatExplosionProfile
    var game: MainGameManager = Global.main_game
    if is_instance_valid(game) and is_instance_valid(game.plant_cell_manager):
        var grid: Array[Array] = game.plant_cell_manager.all_plant_cells
        if source.lane >= 0 and source.lane < grid.size() and not grid[source.lane].is_empty():
            var cell: PlantCell = grid[source.lane][0] as PlantCell
            var shape := RectangleShape2D.new()
            var column_pitch: float = cell.size.x
            var lane_pitch: float = cell.size.y
            if grid[source.lane].size() > 1:
                column_pitch = absf(
                        (grid[source.lane][1] as PlantCell).global_position.x
                        - cell.global_position.x)
            var next_lane: int = source.lane + 1 if source.lane + 1 < grid.size() else source.lane - 1
            if next_lane >= 0 and not grid[next_lane].is_empty():
                lane_pitch = absf(
                        (grid[next_lane][0] as PlantCell).global_position.y
                        - cell.global_position.y)
            shape.size = Vector2(column_pitch * float(radius * 2) + cell.size.x,
                    lane_pitch * float(radius * 2) + cell.size.y)
            profile.shape = shape
            profile.hit_offset = Vector2(0.0, -cell.size.y * 0.5)
    profile.lane_radius = radius
    profile.visuals_scale = 0.6
    return profile
