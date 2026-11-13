## Reusable death explosion trigger; targeting and damage belong to CombatExplosion.
extends AdventureZombieTierAbility
class_name AdventureZombieDeathBurst

var _zombie: Zombie000Base
var _damage := 0
var _exploded := false
var _profile: CombatExplosionProfile
var _hit_all_characters := false
var _armed := true

func disarm() -> void:
    _armed = false

func arm() -> void:
    _armed = true

func setup(zombie: Zombie000Base, damage: int, profile: CombatExplosionProfile,
        on_death: bool = true, hit_all_characters: bool = false) -> void:
    bind_tier(zombie)
    _zombie = zombie
    _damage = damage
    _profile = profile
    _hit_all_characters = hit_all_characters
    if on_death:
        zombie.signal_character_death.connect(_on_death)

func trigger_once() -> void:
    _on_death()

func _on_death() -> void:
    if not tier_can_trigger(true):
        return
    if _exploded or not _armed or _damage <= 0 or not is_instance_valid(_zombie):
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
    _detonate.call_deferred(game, origin, lane, charmed, source_id,
            game.curr_game_round, AdventureSession.get_active_phase(game.game_para))

func _detonate(game: MainGameManager, origin: Vector2,
        lane: int, charmed: bool, source_id: int, round_id: int, phase: StagePhaseDefinition) -> void:
    if not AdventureZombieTierAbility.battle_context_active(game, round_id, phase) \
            or (is_instance_valid(_zombie) and not _zombie.are_tier_skills_active()):
        queue_free()
        return
    var areas: Array[Area2D] = CombatExplosion.query_areas(
            game.get_world_2d().direct_space_state, _profile, origin)
    CombatExplosion.resolve_targets(
            areas, source_id, lane, _profile.lane_radius, charmed, _damage,
            false, _hit_all_characters)
    CombatExplosion.emit_visuals(
            game.bombs if is_instance_valid(game.bombs) else game, _profile, origin)
    queue_free()
