## Reuses Jack-in-the-box collision shape and particles; supplies numeric combat damage.
extends Node
class_name AdventureZombieDancerBurst

## Load only at detonation: eager preload would cycle through Zombie000Base scene.
const JACKBOX_SCENE_PATH := "res://scenes/character/zombie/zombie_016_jackbox.tscn"
var _zombie: Zombie010Dancer
var _damage := 0
var _exploded := false

func setup(zombie: Zombie010Dancer, damage: int, immunity: float) -> void:
    _zombie = zombie
    _damage = damage
    zombie.signal_character_death.connect(_on_death)
    if immunity > 0.0:
        AdventureZombieTimedCombatBuff.grant_immunity(zombie, immunity)

func _on_death() -> void:
    if _exploded or _damage <= 0 or not is_instance_valid(_zombie):
        return
    _exploded = true
    var game: MainGameManager = Global.main_game
    if not is_instance_valid(game):
        return
    var position_on_death: Vector2 = _zombie.global_position
    var lane_on_death: int = _zombie.lane
    var charmed: bool = _zombie.is_hypno
    var source_id: int = _zombie.get_instance_id()
    # Detach before the corpse is freed; collision queries are deferred until
    # the current physics flush finishes, with all source state snapshotted.
    reparent(game.bombs if is_instance_valid(game.bombs) else game)
    _explode.call_deferred(game, position_on_death, lane_on_death, charmed, source_id)

func _explode(game: MainGameManager, origin: Vector2, lane: int,
        charmed: bool, source_id: int) -> void:
    if not is_instance_valid(game):
        queue_free()
        return
    var jackbox: PackedScene = load(JACKBOX_SCENE_PATH) as PackedScene
    if jackbox == null:
        queue_free()
        return
    var template: Node2D = jackbox.instantiate() as Node2D
    var area: Area2D = template.get_node("BombComponentJackbox/Area2DBomb") as Area2D
    var hitbox: CollisionShape2D = area.get_node("CollisionShape2D") as CollisionShape2D
    var center: Vector2 = origin + area.position + hitbox.position
    var query := PhysicsShapeQueryParameters2D.new()
    query.shape = hitbox.shape
    query.transform = Transform2D(0.0, center)
    query.collision_mask = area.collision_mask
    query.collide_with_areas = true
    query.collide_with_bodies = false
    var fx: BombEffectBase = template.get_node(
            "BombComponentJackbox/BombEffect").duplicate() as BombEffectBase
    template.free()
    var hit: Dictionary[int, bool] = {}
    for impact: Dictionary in game.get_world_2d().direct_space_state.intersect_shape(query, 128):
        var collider: Area2D = impact.get("collider") as Area2D
        if collider == null:
            continue
        var target: Character000Base = collider.owner as Character000Base
        if not is_instance_valid(target) or target.is_death \
                or target.is_queued_for_deletion() or target.get_instance_id() == source_id:
            continue
        if not charmed and not (target is Plant000Base):
            continue
        if charmed and not (target is Zombie000Base):
            continue
        if absi(target.lane - lane) > 1 or hit.has(target.get_instance_id()):
            continue
        hit[target.get_instance_id()] = true
        target.be_attacked_bullet(_damage, BulletRegistry.AttackMode.Penetration, false, false)
    # FX does not require an entire Jack-in-the-box zombie nor its kill-all script.
    var fx_parent: Node = game.bombs if is_instance_valid(game.bombs) else game
    fx_parent.add_child(fx)
    fx.global_position = origin + Vector2(0, -28)
    fx.visible = true
    for child: Node in fx.get_children():
        if child is GPUParticles2D:
            (child as GPUParticles2D).restart()
            (child as GPUParticles2D).emitting = true
    SoundManager.play_character_SFX(&"explosion")
    fx.get_tree().create_timer(1.0).timeout.connect(func() -> void:
        if is_instance_valid(fx):
            fx.queue_free())
    queue_free()
