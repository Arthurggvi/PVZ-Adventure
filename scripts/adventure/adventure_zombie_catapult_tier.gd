extends Node
class_name AdventureZombieCatapultTier

var _car: Zombie023Catapult
var _attack: AttackComponentBulletPultBase
var _damage_scale := 1.0
var _blast := 0
var _aura_dr := 0.0
var _profile: CombatExplosionProfile
var _seconds := 0.0
var _three_lane_volley := false
var _volley_target_present := false
var _affected: Dictionary[int, Zombie000Base] = {}

func setup(car: Zombie023Catapult, rule: Dictionary) -> void:
    _car = car
    _attack = car.attack_component as AttackComponentBulletPultBase
    _damage_scale = float(rule.get("basket_multiplier", 1.0))
    _blast = int(rule.get("blast", 0))
    _aura_dr = float(rule.get("aura_dr", 0.0))
    car.update_speed_factor(float(rule.get("speed", 1.0)),
            Character000Base.E_Influence_Speed_Factor.AdventureTierStance)
    if _attack != null:
        _attack.signal_bullet_instantiated.connect(_on_projectile)
        if bool(rule.get("shoot_moving", false)):
            var native_stop: Callable = Callable(car.move_component,
                    "update_move_factor").bind(MoveComponent.E_MoveFactor.IsAttack)
            if _attack.signal_change_is_attack.is_connected(native_stop):
                _attack.signal_change_is_attack.disconnect(native_stop)
            car.move_component.update_move_factor(false, MoveComponent.E_MoveFactor.IsAttack)
        if bool(rule.get("volley", false)):
            _three_lane_volley = true
            _attack.shoot_override = _shoot_three_lanes
            _attack.target_override = _choose_three_lane_primary
            # Detach the native same-lane ray callbacks. The tier strategy
            # drives exactly the same RayEnemy attack factor via a three-lane
            # occupancy query, including when the owner's lane is empty.
            var plus: Callable = Callable(_attack, "update_is_attack_factors").bind(
                    true, AttackComponentBase.E_IsAttackFactors.RayEnemy)
            var minus: Callable = Callable(_attack, "update_is_attack_factors").bind(
                    false, AttackComponentBase.E_IsAttackFactors.RayEnemy)
            if _attack.detect_component.signal_can_attack.is_connected(plus):
                _attack.detect_component.signal_can_attack.disconnect(plus)
            if _attack.detect_component.signal_not_can_attack.is_connected(minus):
                _attack.detect_component.signal_not_can_attack.disconnect(minus)
    if _blast > 0:
        _profile = AdventureZombieTierExplosionGeometry.small_radius(car, 1)
    if _aura_dr > 0.0:
        _refresh_aura()
    set_process(_aura_dr > 0.0 or _three_lane_volley)

func _on_projectile(bullet: Bullet000Base) -> void:
    var ball: Bullet000NormBase = bullet as Bullet000NormBase
    if ball == null:
        return
    ball.attack_value = maxi(0, roundi(float(ball.attack_value) * _damage_scale))
    if _blast > 0:
        ball.impact_resolved.connect(_on_projectile_impact.bind(ball))

func _on_projectile_impact(target: Character000Base,
        location: Vector2, projectile: Bullet000NormBase) -> void:
    if not is_instance_valid(_car) or _car.is_death or not is_instance_valid(Global.main_game):
        return
    var plant: Plant000Base = target as Plant000Base
    if not is_instance_valid(plant):
        return
    CombatExplosion.detonate.call_deferred(Global.main_game,
            plant.global_position if is_instance_valid(plant) else location,
            projectile.lane, _car.get_instance_id(), _car.is_hypno,
            _blast, _profile)

## Three distinct targeted projectiles, not one projectile repeated three times.
## Target lanes are the field's top, middle and bottom rows.
func _choose_three_lane_primary() -> Character000Base:
    if not is_instance_valid(Global.main_game):
        return null
    var rows: Array[Array] = Global.main_game.plant_cell_manager.all_plant_cells
    if rows.is_empty():
        return null
    for lane: int in [0, rows.size() >> 1, rows.size() - 1]:
        var plant: Plant000Base = _choose_plant_in_lane(lane, rows)
        if is_instance_valid(plant):
            return plant
    return null

func _update_volley_target() -> void:
    if not _three_lane_volley or not is_instance_valid(_attack):
        return
    var exists: bool = _car.is_attack_pos and _choose_three_lane_primary() != null
    if exists != _volley_target_present:
        _volley_target_present = exists
        _attack.update_is_attack_factors(exists,
                AttackComponentBase.E_IsAttackFactors.RayEnemy)

func _shoot_three_lanes() -> void:
    if _attack == null or not is_instance_valid(Global.main_game):
        return
    var rows: Array[Array] = Global.main_game.plant_cell_manager.all_plant_cells
    if rows.is_empty():
        return
    var lanes: Array[int] = [0, rows.size() >> 1, rows.size() - 1]
    var used: Dictionary[int, bool] = {}
    for lane: int in lanes:
        if used.has(lane):
            continue
        used[lane] = true
        var target: Plant000Base = _choose_plant_in_lane(lane, rows)
        if target == null or _car.curr_num_shoot_bullet >= _car.MaxNumBullet:
            continue
        # One ammo/animation-state update per actual basketball. Three-lane
        # volleys cannot bypass the finite stock of the original vehicle.
        _attack.signal_shoot_bullet.emit()
        var bullet: Bullet000NormBase = Global.bullet_registry.get_bullet_scenes(
                _attack.attack_bullet_type).instantiate() as Bullet000NormBase
        _attack.signal_bullet_instantiated.emit(bullet)
        var marker: Marker2D = _attack.markers_2d_bullet[0]
        var spawn_at: Vector2 = marker.global_position
        var source_row: int = clampi(_car.lane, 0, rows.size() - 1)
        var zombie_rows: Array[ZombieRow] = Global.main_game.zombie_manager.all_zombie_rows # 物理出生行与有无植物格无关。
        var dy: float = zombie_rows[lane].zombie_create_position.global_position.y - zombie_rows[source_row].zombie_create_position.global_position.y
        spawn_at.y += dy
        var direction: Vector2 = _attack.detect_component.ray_area_direction[0]
        var args: Dictionary = _attack.get_bullet_paras(spawn_at, direction)
        args[Bullet000NormBase.E_InitParasAttr.Position] = _attack.bullets.to_local(spawn_at)
        args[Bullet000NormBase.E_InitParasAttr.BulletLane] = lane
        args[Bullet000NormBase.E_InitParasAttr.Enemy] = target
        args[Bullet000NormBase.E_InitParasAttr.EnemyGloPos] = target.hurt_box_component.global_position
        bullet.init_bullet(args)
        _attack.bullets.add_child(bullet)
    _attack.play_throw_sfx()

func _choose_plant_in_lane(lane: int, rows: Array[Array]) -> Plant000Base:
    if lane < 0 or lane >= rows.size():
        return null
    var best: Plant000Base = null # 无候选时必须返回 null，禁止读取未初始化的目标。
    for cell: PlantCell in rows[lane]:
        for plant: Plant000Base in cell.plant_in_cell.values():
            if not is_instance_valid(plant) or plant.is_death or plant.is_queued_for_deletion():
                continue
            if is_instance_valid(_car) and plant.global_position.x > _car.global_position.x:
                continue
            if best == null or plant.global_position.x < best.global_position.x:
                best = plant
    return best

func _process(delta: float) -> void:
    if not is_instance_valid(_car) or _car.is_death:
        _clear_aura()
        set_process(false)
        return
    _update_volley_target()
    _seconds += delta
    if _aura_dr > 0.0 and _seconds >= 0.2:
        _seconds = 0.0
        _refresh_aura()

func _refresh_aura() -> void:
    if not is_instance_valid(Global.main_game) or not is_instance_valid(_car):
        return
    var width: float = Global.main_game.board.cell_width_at(_car.global_position, _car.lane) # 当前地点格宽。
    if width <= 0.0:
        return
    var next: Dictionary[int, Zombie000Base] = {}
    for ally: Zombie000Base in AdventureZombieTierNeighbors.allied_in_range(
            _car, Global.main_game.zombie_manager.all_zombies_1d, width, 1):
        next[ally.get_instance_id()] = ally
        ally.hp_component.damage_reduction.set_source(get_instance_id(), _aura_dr)
    for key: int in _affected:
        if not next.has(key) and is_instance_valid(_affected[key]):
            _affected[key].hp_component.damage_reduction.set_source(get_instance_id(), 0.0)
    _affected = next

func _clear_aura() -> void:
    for ally: Zombie000Base in _affected.values():
        if is_instance_valid(ally):
            ally.hp_component.damage_reduction.set_source(get_instance_id(), 0.0)
    _affected.clear()

func _exit_tree() -> void:
    _clear_aura()
