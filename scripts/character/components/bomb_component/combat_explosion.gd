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
    var limit: int = 256 # 满额时扩大查询，多受击框的密集僵尸也能覆盖。
    var entries: Array[Dictionary] = space.intersect_shape(query, limit) # 当前完整度待确认的命中。
    while entries.size() == limit:
        limit *= 2
        entries = space.intersect_shape(query, limit)
    for entry: Dictionary in entries: # 仅保留仍有效的区域。
        var area: Area2D = entry.get("collider") as Area2D
        if is_instance_valid(area):
            hits.append(area)
    return hits

## 对 [param areas] 中的敌方角色按实例去重。
## [param lane] 为爆心所在行，[param radius] 为行半径，-1 表示不限制。[param statuses] 为可命中的僵尸状态位。
static func plant_blast_targets(areas: Array[Area2D], lane: int,
        radius: int, statuses: int) -> Array[Character000Base]:
    var targets: Array[Character000Base] = [] # 当前几何命中的候选快照。
    var seen: Dictionary[int, bool] = {} # 同一角色的多个受击区域只登记一次。
    for area: Area2D in areas:
        if not is_instance_valid(area) or not is_instance_valid(area.owner):
            continue
        var target := area.owner as Character000Base # 设施与普通僵尸共用角色入口。
        if not _can_hit_plant_blast(target, lane, radius, statuses):
            continue
        var id: int = target.get_instance_id() # 以角色身份去重。
        if not seen.has(id):
            seen[id] = true
            targets.append(target)
    return targets

## 结算 [param areas] 覆盖的植物爆炸，沿用 [param lane]、[param radius] 和 [param statuses] 筛选。
## [param damage] 是出战修正后的伤害，[param ash] 选择普通僵尸是否播放灰烬。
## [param context] 是可选来源快照，逐目标修饰伤害并仅奖励本次实际击杀。
## 返回实际击杀的僵尸或僵王，设施销毁不计入击杀。
static func resolve_plant_blast(areas: Array[Area2D], lane: int, radius: int,
        statuses: int, damage: int, ash: bool, context: PlantAttackContext = null) -> Array[Character000Base]:
    var casualties: Array[Character000Base] = [] # 只保存本次受击从存活变为死亡的角色。
    if context != null and not context.is_active():
        return casualties
    for area: Area2D in areas: # 梯子按原爆炸区域与行限制清理。
        if not is_instance_valid(area) or not is_instance_valid(area.owner):
            continue
        var ladder := area.owner as Ladder # 具有自身销毁入口的非角色目标。
        if ladder != null and (radius < 0 or absi(ladder.lane - lane) <= radius):
            ladder.ladder_death()
    # 一次伤害可能同步销毁后续目标，逐个结算前复核有效性。
    for reference: Variant in plant_blast_targets(areas, lane, radius, statuses):
        if context != null and not context.is_active():
            break
        if not is_instance_valid(reference):
            continue
        var target: Character000Base = reference # 同步回调后重新验证。
        if not _can_hit_plant_blast(target, lane, radius, statuses):
            continue
        var hit_damage: int = context.modify_damage(damage, target) if context != null else damage # 每个目标独立计算距离。
        var casualty: Character000Base = null # 实际死者可能是承受转伤的保护者。
        if target is Zombie000Base:
            var armor: float = context.armor_multiplier if context != null else 1.0 # 只扩展原爆炸的防具消耗参数。
            casualty = target.be_bomb(hit_damage, ash, armor)
        else:
            target.be_attacked_bullet(hit_damage, BulletRegistry.AttackMode.Penetration, false, false)
            if is_instance_valid(target) and target is ZB000Base and target.is_death:
                casualty = target
        if is_instance_valid(casualty):
            casualties.append(casualty)
        if context != null:
            context.resolve_kill(casualty) # 未致死同样消费本次同步奖励资格。
    return casualties

## 判断 [param target] 是否仍可被以 [param lane] 为中心的植物爆炸命中。
## [param radius] 为行限制，[param statuses] 为允许的受击状态位。
static func _can_hit_plant_blast(target: Character000Base, lane: int, radius: int, statuses: int) -> bool:
    if not is_instance_valid(target) or target.is_death or target.is_hypno \
            or target.is_queued_for_deletion() or not target.is_inside_tree() \
            or not is_instance_valid(target.hurt_box_component) or not target.hurt_box_component.is_enabling:
        return false
    if target is ZB000Base:
        # 跨行僵王由实际受击区域决定几何命中。
        return target.character_init_type == Character000Base.E_CharacterInitType.IsNorm \
            and (statuses & Zombie000Base.E_BeAttackStatusZombie.IsNorm) != 0
    if radius >= 0 and absi(target.lane - lane) > radius:
        return false
    if target is EnemyStructureBase:
        return (statuses & Zombie000Base.E_BeAttackStatusZombie.IsNorm) != 0
    return target is Zombie000Base and (target.curr_be_attack_status & statuses) != 0

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
## Common runtime entry for non-death explosions: impact, smash, steal, etc.
static func detonate(game: MainGameManager, origin: Vector2, lane: int,
        source_id: int, charmed: bool, damage: int,
        profile: CombatExplosionProfile, all_characters: bool = false) -> int:
    if not is_instance_valid(game) or profile == null or damage <= 0:
        return 0
    var hits: Array[Area2D] = query_areas(
            game.get_world_2d().direct_space_state, profile, origin)
    var affected: int = resolve_targets(hits, source_id, lane,
            profile.lane_radius, charmed, damage, false, all_characters)
    emit_visuals(game.bombs if is_instance_valid(game.bombs) else game,
            profile, origin)
    return affected

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
