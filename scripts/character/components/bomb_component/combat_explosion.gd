## Single target-selection and damage authority for area combat explosions.
## Supports existing Jackbox instakill and tiered numeric death-burst damage.
extends RefCounted
class_name CombatExplosion

## 普通、攻击中和魅惑僵尸的检测及真实受击层。
const ZOMBIE_HURTBOX_MASK := 4 | 16 | 32 | 512 | 1024

## 在 [param space] 按 [param profile] 和 [param origin] 查询爆炸范围。
static func query_areas(space: PhysicsDirectSpaceState2D,
        profile: CombatExplosionProfile, origin: Vector2) -> Array[Area2D]:
    if profile == null:
        return []
    return query_shape(space, profile.shape, Transform2D(0.0, origin + profile.hit_offset),
        profile.collision_mask)

## 引爆时使用 [param collider] 的原始形状与当前世界变换，平时无需监听重叠信号。
## [param mask] 为原碰撞掩码。应从通常的引爆事件或延迟回调调用。
static func query_collider(collider: CollisionShape2D, mask: int) -> Array[Area2D]:
    if not is_instance_valid(collider) or not collider.is_inside_tree():
        return []
    return query_shape(collider.get_world_2d().direct_space_state, collider.shape,
        collider.global_transform, mask, true)

## 复用同一物理查询。[param space] 是当前战场，[param shape] 按 [param at] 变换，
## [param mask] 为目标层。命中达到容量时继续扩大，确保密集战场中的后续目标继续结算。
## [param monitorable_only] 为使用 Area2D 重叠语义的调用方排除暂时关闭的受击框。
static func query_shape(space: PhysicsDirectSpaceState2D, shape: Shape2D,
        at: Transform2D, mask: int, monitorable_only: bool = false) -> Array[Area2D]:
    var hits: Array[Area2D] = [] # 本次物理检测命中的所有有效 Area2D。
    if space == null or shape == null:
        return hits
    var query := PhysicsShapeQueryParameters2D.new() # 对所有容量重试复用同一组参数。
    query.shape = shape
    query.transform = at
    query.collision_mask = mask
    query.collide_with_areas = true
    query.collide_with_bodies = false
    var limit: int = 512 if (mask & ZOMBIE_HURTBOX_MASK) != 0 else 256 # 密集僵尸场景减少重复查询。
    var entries: Array[Dictionary] = space.intersect_shape(query, limit) # 当前完整度待确认的命中。
    while entries.size() == limit:
        limit *= 2
        entries = space.intersect_shape(query, limit)
    for entry: Dictionary in entries: # 仅保留仍有效的区域。
        var area: Area2D = entry.get("collider") as Area2D # 物理结果仍可返回被关闭监听的区域。
        if is_instance_valid(area) and (not monitorable_only or area.monitorable):
            hits.append(area)
    return hits

## 对 [param areas] 中的敌方角色按实例去重。
## [param lane] 为爆心所在行，[param radius] 为行半径，-1 表示不限制。[param statuses] 为可命中的僵尸状态位。
static func plant_blast_targets(areas: Array[Area2D], lane: int,
        radius: int, statuses: int) -> Array[Character000Base]:
    var targets: Array[Character000Base] = [] # 当前几何命中的候选快照。
    var seen: Dictionary[int, bool] = {} # 同一角色的多个受击区域只登记一次。
    for area: Area2D in areas: # 保留物理查询返回的首个命中顺序。
        if not is_instance_valid(area):
            continue
        var target := area.owner as Character000Base # 设施与普通僵尸共用角色入口。
        if not is_instance_valid(target):
            continue
        var id: int = target.get_instance_id() # 以角色身份去重。
        if not seen.has(id) and can_hit_plant_blast(target, lane, radius, statuses):
            seen[id] = true
            targets.append(target)
    return targets

## 结算 [param areas] 覆盖的植物爆炸，沿用 [param lane]、[param radius] 和 [param statuses] 筛选。
## [param damage] 是出战修正后的伤害，[param ash] 标记灰烬类爆炸及其死亡表现。
## [param context] 是可选来源快照，逐目标修饰伤害并仅奖励本次实际击杀。
## [param boss_damage_cap] 只在僵王原生减伤前限制本次爆炸伤害，负一表示不限制。
## 返回实际击杀的僵尸或僵王，设施销毁不计入击杀。
static func resolve_plant_blast(areas: Array[Area2D], lane: int, radius: int,
        statuses: int, damage: int, ash: bool, context: PlantAttackContext = null,
        boss_damage_cap: int = -1) -> Array[Character000Base]:
    var casualties: Array[Character000Base] = [] # 只保存本次受击从存活变为死亡的角色。
    if context != null and not context.is_active():
        return casualties
    clear_plant_blast_ladders(areas, lane, radius)
    # 一次伤害可能同步销毁后续目标，逐个结算前复核有效性。
    for reference: Variant in plant_blast_targets(areas, lane, radius, statuses):
        if context != null and not context.is_active():
            break
        if not is_instance_valid(reference):
            continue
        var target: Character000Base = reference # 同步回调后重新验证。
        if not can_hit_plant_blast(target, lane, radius, statuses):
            continue
        var hit_damage: int = context.modify_damage(damage, target) if context != null else damage # 每个目标独立计算距离。
        if target is ZB000Base and boss_damage_cap >= 0:
            hit_damage = mini(hit_damage, boss_damage_cap)
        var armor: float = context.armor_multiplier if context != null else 1.0 # 防具消耗与承伤归因仍走原生入口。
        var casualty: Character000Base = hit_plant_blast_target(target, hit_damage, ash, armor)
        if is_instance_valid(casualty):
            casualties.append(casualty)
        if context != null:
            context.resolve_kill(casualty) # 未致死同样消费本次同步奖励资格。
    return casualties

## 清理 [param areas] 中被从 [param lane] 发出的爆炸击中的梯子，[param radius] 为 -1 时不限行。
static func clear_plant_blast_ladders(areas: Array[Area2D], lane: int, radius: int) -> void:
    for area: Area2D in areas: # 同一梯子可出现在多个相交区域，已排队释放时跳过。
        if not is_instance_valid(area) or not is_instance_valid(area.owner):
            continue
        var ladder := area.owner as Ladder # 保留设施自己的拆除入口。
        if ladder != null and not ladder.is_queued_for_deletion() and (radius < 0 or absi(ladder.lane - lane) <= radius):
            ladder.ladder_death()

## 对已验证的 [param target] 施加 [param damage] 点爆炸伤害和 [param armor] 防具倍率。
## [param ash] 决定原生灰烬及僵王抗性，[param scope] 可去重实际承伤者并观察致死位置。
## 返回本次真正死亡的僵尸或僵王，可能与原碰撞目标不同。
static func hit_plant_blast_target(target: Character000Base, damage: int, ash: bool,
        armor: float = 1.0, scope: CombatHitScope = null) -> Character000Base:
    if target is Zombie000Base:
        return target.be_bomb(damage, ash, armor, scope)
    if ash and target is ZB000Base:
        damage = target.ash_damage_received(damage)
    target.be_attacked_bullet(damage, BulletRegistry.AttackMode.Penetration, false, false, 0, -1, null, scope)
    return target if is_instance_valid(target) and target is ZB000Base and target.is_death else null

## 判断 [param target] 是否仍可被以 [param lane] 为中心的植物爆炸命中。
## [param radius] 为行限制，[param statuses] 为允许的受击状态位。
static func can_hit_plant_blast(target: Character000Base, lane: int, radius: int, statuses: int) -> bool:
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

## 结算 [param areas] 中的爆炸目标，跳过 [param source_id]。从 [param lane] 起按 [param radius] 限制行数，-1 表示全行。
## [param charmed] 为真时跳过僵王。单阵营爆炸在魅惑后命中敌方僵尸，原阵营时命中植物。
## [param hit_all_characters] 同时允许两方与罐子，仍应用魅惑时的僵王过滤。
## [param attack_source] 可指定独立弹体的发射者；[param source_id] 仍用于排除爆心实体。
## [param lethal] 使用原生小丑消灭行为，否则按 [param damage] 逐次结算。返回实际处理的目标数。
static func resolve_targets(areas: Array[Area2D], source_id: int,
        lane: int, radius: int, charmed: bool, damage: int,
        lethal: bool = false, hit_all_characters: bool = false, attack_source: Character000Base = null) -> int:
    if damage <= 0 and not lethal:
        return 0
    var unique: Dictionary[int, bool] = {} # 本次已处理的角色或罐子。
    var affected := 0 # 已触发伤害、消灭或开罐的目标数。
    var source: Character000Base = attack_source # 优先将独立弹体还原为发射者。
    if not is_instance_valid(source) and is_instance_id_valid(source_id):
        source = instance_from_id(source_id) as Character000Base
    var attacker := source as Zombie000Base if charmed else null # 魅惑侧保留已有击杀归属。
    var plant_hit: CombatHitScope = null # 仅在爆炸确实命中植物时创建归因，并由这一轮共享。
    for area: Area2D in areas: # 前一击可能同步移除后续目标。
        if not is_instance_valid(area):
            continue
        var entity: Node = area.owner # 受击区域可能属于角色或罐子。
        if hit_all_characters and entity is Character000Base:
            entity = (entity as Character000Base).combat_hit_owner() # 附属受击代理与本体必须作为同一个实际承伤者。
        if not is_instance_valid(entity):
            continue
        var id: int = entity.get_instance_id() # 多个区域命中同一目标时只结算首个合格区域。
        if unique.has(id):
            continue
        if entity is ScaryPot and (lethal or hit_all_characters) and (hit_all_characters or not charmed):
            var pot := entity as ScaryPot # 罐子按原开罐路径处理。
            if radius == -1 or absi(pot.lane - lane) <= radius:
                unique[id] = true
                pot.open_pot_be_bomb()
                affected += 1
            continue
        var target := entity as Character000Base # 只有角色走伤害或即死结算。
        if not is_instance_valid(target) or target.is_death or target.is_queued_for_deletion():
            continue
        if id == source_id or (radius >= 0 and absi(target.lane - lane) > radius) \
                or (charmed and target is ZB000Base):
            continue
        if not hit_all_characters:
            if charmed and (not (target is Zombie000Base) or target.is_hypno):
                continue
            if not charmed and not (target is Plant000Base):
                continue
        unique[id] = true
        if target is Plant000Base:
            if plant_hit == null:
                plant_hit = CombatHitScope.for_plant_attack(source, CombatHitScope.PlantImpact.EXPLOSION)
            if lethal:
                target.be_hit_instantly(plant_hit)
            elif damage > 0:
                target.be_attacked_bullet(damage, BulletRegistry.AttackMode.Penetration, false, false, 0, -1, null, plant_hit)
            affected += 1
            continue
        if lethal:
            target.character_death_disappear()
            if is_instance_valid(attacker) and attacker.signal_hypno_enemy_killed.has_connections():
                attacker.report_hypno_kill(target as Zombie000Base)
        elif damage > 0:
            if is_instance_valid(attacker) and target is Zombie000Base and not target.is_hypno:
                attacker.hit_as_hypnotized(target, damage, false, false)
            else:
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
        SoundManager.play_character_SFX(profile.sound, parent, origin, 3)
    if profile.visuals == null or not is_instance_valid(parent):
        return
    var at: Vector2 = origin + profile.visuals_offset # 在场景分配前确定爆心的表现位置。
    var game := parent.get_tree().current_scene as MainGameManager if parent.is_inside_tree() else null # 预览可直接播放。
    if is_instance_valid(game) and not game.blast_fx_budget.can_start(StringName(profile.visuals.resource_path), at):
        return
    var fx: BombEffectBase = profile.visuals.instantiate() as BombEffectBase
    if fx == null:
        push_error("CombatExplosionProfile.visuals must inherit BombEffectBase")
        return
    parent.add_child(fx)
    fx.global_position = at
    fx.scale = Vector2.ONE * profile.visuals_scale
    fx.activate_bomb_effect()
