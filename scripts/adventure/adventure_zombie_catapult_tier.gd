extends AdventureZombieTierAbility
class_name AdventureZombieCatapultTier

var _car: Zombie023Catapult
var _attack: AttackComponentBulletPultBase
var _damage_scale := 1.0
var _blast := 0
var _aura_dr := 0.0
var _profile: CombatExplosionProfile
var _seconds := 0.0
var _three_lane_volley := false
## 是否拥有移动射击策略；沉默时恢复原生攻击停步。
var _shoot_moving := false
## 接管策略前的原生回调连接情况，恢复时不制造原本不存在的连接。
var _native_stop_connected := false
## 原本行检测的命中连接是否存在。
var _native_plus_connected := false
## 原本行检测的脱离连接是否存在。
var _native_minus_connected := false
var _volley_target_present := false
var _affected: Dictionary[int, Zombie000Base] = {}

func setup(car: Zombie023Catapult, rule: Dictionary) -> void:
    bind_tier(car)
    _car = car
    _attack = car.attack_component as AttackComponentBulletPultBase
    _damage_scale = float(rule.get("basket_multiplier", 1.0))
    _blast = int(rule.get("blast", 0))
    _aura_dr = float(rule.get("aura_dr", 0.0))
    set_tier_speed(float(rule.get("speed", 1.0)))
    _shoot_moving = bool(rule.get("shoot_moving", false))
    _three_lane_volley = bool(rule.get("volley", false))
    if _attack != null:
        _attack.signal_bullet_instantiated.connect(_on_projectile)
        var native_stop: Callable = Callable(car.move_component, "update_move_factor").bind(MoveComponent.E_MoveFactor.IsAttack) # 只接管原有停步回调。
        _native_stop_connected = _attack.signal_change_is_attack.is_connected(native_stop)
        var plus: Callable = Callable(_attack, "update_is_attack_factors").bind(true, AttackComponentBase.E_IsAttackFactors.RayEnemy) # 原本行检测的可攻击信号。
        var minus: Callable = Callable(_attack, "update_is_attack_factors").bind(false, AttackComponentBase.E_IsAttackFactors.RayEnemy) # 原本行检测的不可攻击信号。
        _native_plus_connected = _attack.detect_component.signal_can_attack.is_connected(plus)
        _native_minus_connected = _attack.detect_component.signal_not_can_attack.is_connected(minus)
        if _three_lane_volley:
            set_tier_property(_attack, &"shoot_override", _shoot_three_lanes)
            set_tier_property(_attack, &"target_override", _choose_three_lane_primary)
        _apply_attack_strategy(tier_enabled())
    if _blast > 0:
        _profile = AdventureZombieTierExplosionGeometry.small_radius(car, 1)
    if _aura_dr > 0.0:
        _refresh_aura()
    set_process(_aura_dr > 0.0 or _three_lane_volley)

func _on_projectile(bullet: Bullet000Base) -> void:
    if not tier_can_trigger():
        return
    var ball: Bullet000NormBase = bullet as Bullet000NormBase
    if ball == null:
        return
    ball.attack_value = maxi(0, roundi(float(ball.attack_value) * _damage_scale))
    if _blast > 0:
        ball.impact_resolved.connect(_on_projectile_impact.bind(ball))

func _on_projectile_impact(target: Character000Base,
        location: Vector2, projectile: Bullet000NormBase) -> void:
    if not tier_can_trigger() or not is_instance_valid(Global.main_game):
        return
    var plant: Plant000Base = target as Plant000Base
    if not is_instance_valid(plant):
        return
    queue_tier_explosion(plant.global_position if is_instance_valid(plant) else location,
            projectile.lane, _blast, _profile)

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
    if not tier_can_trigger():
        return
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
        for plant: Plant000Base in cell.living_plants(): # 不占种植位的伴生同样参与目标选择或伤害。
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
    if not tier_can_trigger():
        _clear_aura()
        return
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


## [param active] 撤销或恢复主动策略与光环；原生单行攻击继续，冷却与弹药保持进度。
func _tier_state_changed(active: bool) -> void:
    _apply_attack_strategy(active)
    if active:
        _refresh_aura()
    else:
        _clear_aura()


## 按 [param active] 切换本能力拥有的连接，不删除或重建攻击组件。
func _apply_attack_strategy(active: bool) -> void:
    if not is_instance_valid(_attack) or not is_instance_valid(_car):
        return
    if _shoot_moving:
        var native_stop: Callable = Callable(_car.move_component, "update_move_factor").bind(MoveComponent.E_MoveFactor.IsAttack) # 与原生绑定完全相同，防重复连接。
        _set_connection(_attack.signal_change_is_attack, native_stop, _native_stop_connected and not active)
        _car.move_component.update_move_factor(false if active else _attack.is_attack_res, MoveComponent.E_MoveFactor.IsAttack)
    if not _three_lane_volley:
        return
    var plus: Callable = Callable(_attack, "update_is_attack_factors").bind(true, AttackComponentBase.E_IsAttackFactors.RayEnemy) # 恢复原有本行检测。
    var minus: Callable = Callable(_attack, "update_is_attack_factors").bind(false, AttackComponentBase.E_IsAttackFactors.RayEnemy) # 只改本能力接管的两个回调。
    _set_connection(_attack.detect_component.signal_can_attack, plus, _native_plus_connected and not active)
    _set_connection(_attack.detect_component.signal_not_can_attack, minus, _native_minus_connected and not active)
    if active:
        _volley_target_present = _car.is_attack_pos and _choose_three_lane_primary() != null
        _attack.update_is_attack_factors(_volley_target_present, AttackComponentBase.E_IsAttackFactors.RayEnemy)
    else:
        _attack.detect_component.judge_is_have_enemy()
        _attack.last_target_enemy = _attack._choose_pult_target()
        if is_instance_valid(_attack.last_target_enemy):
            _attack.last_target_enemy_global_pos = _attack.last_target_enemy.hurt_box_component.global_position


## [param source] 仅对 [param callback] 按 [param connected] 调整连接，重复切换无副作用。
func _set_connection(source: Signal, callback: Callable, connected: bool) -> void:
    if connected and not source.is_connected(callback):
        source.connect(callback)
    elif not connected and source.is_connected(callback):
        source.disconnect(callback)

func _exit_tree() -> void:
    if is_instance_valid(_car) and _car.is_changing_lane:
        return
    _clear_aura()
