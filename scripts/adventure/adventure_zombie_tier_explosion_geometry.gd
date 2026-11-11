## Scene-independent geometry factory: a radius of 1 spans 3 x 3 grid cells.
extends RefCounted
class_name AdventureZombieTierExplosionGeometry

const TEMPLATE := preload("res://resources/combat/jackbox_explosion_profile.tres")

static func small_radius(source: Zombie000Base, radius: int) -> CombatExplosionProfile:
    var profile: CombatExplosionProfile = TEMPLATE.duplicate(true) as CombatExplosionProfile
    var game: MainGameManager = Global.main_game
    if is_instance_valid(game) and is_instance_valid(game.plant_cell_manager):
        var cell: PlantCell = game.board.nearest_cell(source.global_position, source.lane) # 当前爆心附近种植点。
        if cell != null:
            var shape := RectangleShape2D.new() # 当前局部尺度决定的像素范围。
            var pitch: Vector2 = game.board.local_pitch(cell) # 不缓存旧地块位置。
            shape.size = pitch * float(radius * 2) + cell.size
            profile.shape = shape
            profile.hit_offset = Vector2(0.0, -cell.size.y * 0.5)
    profile.lane_radius = radius
    profile.visuals_scale = 0.6
    return profile
