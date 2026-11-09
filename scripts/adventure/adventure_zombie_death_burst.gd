## Reusable death explosion trigger; targeting and damage belong to CombatExplosion.
extends Node
class_name AdventureZombieDeathBurst

var _zombie: Zombie000Base
var _damage := 0
var _exploded := false
var _profile: CombatExplosionProfile

func setup(zombie: Zombie000Base, damage: int, profile: CombatExplosionProfile) -> void:
    _zombie = zombie
    _damage = damage
    _profile = profile
    zombie.signal_character_death.connect(_on_death)

func _on_death() -> void:
    if _exploded or _damage <= 0 or not is_instance_valid(_zombie):
        return
    _exploded = true
    var game: MainGameManager = Global.main_game
    if not is_instance_valid(game):
        return
    var origin := _zombie.global_position
    var lane: int = _zombie.lane
    var charmed: bool = _zombie.is_hypno
    var source_id: int = _zombie.get_instance_id()
    reparent(game.bombs if is_instance_valid(game.bombs) else game)
    _detonate.call_deferred(game, origin, lane, charmed, source_id)

func _detonate(game: MainGameManager, origin: Vector2,
        lane: int, charmed: bool, source_id: int) -> void:
    if not is_instance_valid(game):
        queue_free()
        return
    var areas: Array[Area2D] = CombatExplosion.query_areas(
            game.get_world_2d().direct_space_state, _profile, origin)
    CombatExplosion.resolve_targets(
            areas, source_id, lane, _profile.lane_radius, charmed, _damage)
    CombatExplosion.emit_visuals(
            game.bombs if is_instance_valid(game.bombs) else game, _profile, origin)
    queue_free()
