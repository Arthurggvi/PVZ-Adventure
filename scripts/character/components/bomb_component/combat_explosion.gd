## Single target-selection and damage authority for area combat explosions.
## Supports existing Jackbox instakill and tiered numeric death-burst damage.
extends RefCounted
class_name CombatExplosion

## Call from outside the physics flush; callers may use call_deferred.
static func query_areas(space: PhysicsDirectSpaceState2D,
        profile: CombatExplosionProfile, origin: Vector2) -> Array[Area2D]:
    var hits: Array[Area2D] = []
    if space == null or profile == null or profile.shape == null:
        return hits
    var query := PhysicsShapeQueryParameters2D.new()
    query.shape = profile.shape
    query.transform = Transform2D(0.0, origin + profile.hit_offset)
    query.collision_mask = profile.collision_mask
    query.collide_with_areas = true
    query.collide_with_bodies = false
    for entry: Dictionary in space.intersect_shape(query, 256):
        var area: Area2D = entry.get("collider") as Area2D
        if is_instance_valid(area):
            hits.append(area)
    return hits

## True=source is charmed and must hit zombies; false=source targets plants.
## 'lethal' retains native Jackbox elimination; numeric blasts always use HP routing.
static func resolve_targets(areas: Array[Area2D], source_id: int,
        lane: int, radius: int, charmed: bool, damage: int,
        lethal: bool = false, hit_all_characters: bool = false) -> int:
    if damage <= 0 and not lethal:
        return 0
    var unique: Dictionary[int, bool] = {}
    var affected := 0
    for area: Area2D in areas:
        if not is_instance_valid(area) or not is_instance_valid(area.owner):
            continue
        var entity: Node = area.owner
        if entity is ScaryPot and (lethal or hit_all_characters) and (hit_all_characters or not charmed):
            var pot: ScaryPot = entity as ScaryPot
            if radius == -1 or absi(pot.lane - lane) <= radius:
                var pot_id: int = pot.get_instance_id()
                if not unique.has(pot_id):
                    unique[pot_id] = true
                    pot.open_pot_be_bomb()
                    affected += 1
            continue
        var target: Character000Base = entity as Character000Base
        if not is_instance_valid(target) or target.is_death or target.is_queued_for_deletion():
            continue
        if target.get_instance_id() == source_id or (radius >= 0 and absi(target.lane - lane) > radius):
            continue
        if not hit_all_characters:
            if charmed and (not (target is Zombie000Base) or target.is_hypno):
                continue
            if not charmed and not (target is Plant000Base):
                continue
        var id: int = target.get_instance_id()
        if unique.has(id):
            continue
        unique[id] = true
        if lethal:
            target.character_death_disappear()
        elif damage > 0:
            target.be_attacked_bullet(damage, BulletRegistry.AttackMode.Penetration, false, false)
        affected += 1
    return affected

## Each FX subclass owns its particle lifetime; the resolver never duplicates
## emitter, tween, or cleanup logic from the established BombEffect pipeline.
static func emit_visuals(parent: Node, profile: CombatExplosionProfile,
        origin: Vector2) -> void:
    if profile == null:
        return
    if profile.sound != &"":
        SoundManager.play_character_SFX(profile.sound)
    if profile.visuals == null or not is_instance_valid(parent):
        return
    var fx: BombEffectBase = profile.visuals.instantiate() as BombEffectBase
    if fx == null:
        push_error("CombatExplosionProfile.visuals must inherit BombEffectBase")
        return
    parent.add_child(fx)
    fx.global_position = origin + profile.visuals_offset
    fx.scale = Vector2.ONE * profile.visuals_scale
    fx.activate_bomb_effect()
