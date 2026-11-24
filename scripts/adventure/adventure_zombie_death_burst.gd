## Reusable death explosion trigger; targeting and damage belong to CombatExplosion.
extends AdventureZombieTierAbility
class_name AdventureZombieDeathBurst

var _zombie: Zombie000Base
var _damage := 0
var _exploded := false
var _profile: CombatExplosionProfile
var _hit_all_characters := false
var _armed := true
## 单格模式使用死亡所在格的植物占用，其他爆炸仍查询物理范围。
var _single_cell := false
## 触发时所在格的稳定 ID，盘外或空洞时为空。
var _origin_cell_id: StringName = &""

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

## 让 [param zombie] 死亡时对所在格的植物造成 [param damage] 点爆炸伤害。
## 没有脚下格时仍播放音效和特效。
func setup_single_cell(zombie: Zombie000Base, damage: int) -> void:
    _single_cell = true
    var profile := AdventureZombieTierExplosionGeometry.TEMPLATE.duplicate() as CombatExplosionProfile # 复用原小型爆炸的表现配置。
    profile.shape = null
    profile.lane_radius = 0
    profile.visuals_scale = 0.6
    setup(zombie, damage, profile)

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
    if _single_cell and game.board != null:
        var cell: PlantCell = game.board.cell_at_ground_point(origin, lane) # 记录死亡瞬间脚下的实格。
        if cell != null:
            _origin_cell_id = cell.cell_id
    reparent(game.bombs if is_instance_valid(game.bombs) else game)
    _detonate.call_deferred(game, origin, lane, charmed, source_id,
            game.curr_game_round, AdventureSession.get_active_phase(game.game_para))

func _detonate(game: MainGameManager, origin: Vector2,
        lane: int, charmed: bool, source_id: int, round_id: int, phase: StagePhaseDefinition) -> void:
    if not AdventureZombieTierAbility.battle_context_active(game, round_id, phase) \
            or (is_instance_valid(_zombie) and not _zombie.are_tier_skills_active()):
        queue_free()
        return
    var areas: Array[Area2D] = [] # 交给统一爆炸结算的受击区域。
    if _single_cell:
        var cell: PlantCell = game.board.cell_by_id(_origin_cell_id) if game.board != null else null # 延迟结算时重新确认地块仍有效。
        if cell != null:
            for plant: Plant000Base in cell.living_plants(): # 按实际占格命中，包含底座、保护壳和伴生植物。
                var hurt_box: HurtBoxComponent = plant.hurt_box_component # 使用植物自身的受击区域确认角色归属。
                if is_instance_valid(hurt_box) and is_instance_valid(hurt_box.hurt_box_real):
                    areas.append(hurt_box.hurt_box_real)
    else:
        areas = CombatExplosion.query_areas(game.get_world_2d().direct_space_state, _profile, origin)
    CombatExplosion.resolve_targets(
            areas, source_id, lane, _profile.lane_radius, charmed, _damage,
            false, _hit_all_characters)
    CombatExplosion.emit_visuals(
            game.bombs if is_instance_valid(game.bombs) else game, _profile, origin)
    queue_free()
