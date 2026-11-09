extends Node
class_name AdventureZombieGargantuarTier

var _giant: Zombie024Gargantuar
var _each_smash_imps := 0
var _blast := 0
var _crush := false
var _profile: CombatExplosionProfile

func setup(giant: Zombie024Gargantuar, rule: Dictionary) -> void:
    _giant = giant
    _each_smash_imps = int(rule.get("imp_each_smash", 0))
    _blast = int(rule.get("smash_blast", 0))
    _crush = bool(rule.get("death_crush", false))
    giant.throw_imp_count = int(rule.get("imp_per_throw", 1))
    giant.fallback_throw_column = int(rule.get("fallback_col", -1))
    giant.preserve_death_animation_after_blast = _crush
    giant.update_speed_factor(float(rule.get("speed", 1.0)),
            Character000Base.E_Influence_Speed_Factor.AdventureTierStance)
    (giant.hp_component as HpComponentZombie).grant_bonus_armor(
            int(rule.get("spawn_armor", 0)))
    var smash: AttackComponentZombieGargantuar = (
            giant.attack_component as AttackComponentZombieGargantuar)
    if smash != null and (_blast > 0 or _each_smash_imps > 0):
        smash.signal_smash_completed.connect(_on_smash)
    if _blast > 0:
        _profile = AdventureZombieTierExplosionGeometry.small_radius(giant, 1)
    if _crush:
        giant.signal_character_death.connect(_on_death)
    var speed: float = float(rule.get("smash_anim_speed", 1.0))
    if speed > 1.0:
        _install_smash_only_speed(speed)

## AnimationNodeStateMachine.replace_node preserves native state transitions
## and animation method tracks, with an independently scaled smash branch.
func _install_smash_only_speed(multiplier: float) -> void:
    var tree: AnimationTree = _giant.get_node("AnimationTree") as AnimationTree
    var root: AnimationNodeBlendTree = tree.tree_root.duplicate(true) as AnimationNodeBlendTree
    var machine: AnimationNodeStateMachine = root.get_node("StateMachine") as AnimationNodeStateMachine
    var clip: AnimationRootNode = machine.get_node("Zombie_gargantuar_smash")
    var branch := AnimationNodeBlendTree.new()
    branch.add_node(&"SmashClip", clip)
    branch.add_node(&"SmashSpeed", AnimationNodeTimeScale.new())
    branch.connect_node(&"SmashSpeed", 0, &"SmashClip")
    branch.connect_node(&"output", 0, &"SmashSpeed")
    machine.replace_node(&"Zombie_gargantuar_smash", branch)
    tree.tree_root = root
    tree.set("parameters/StateMachine/Zombie_gargantuar_smash/SmashSpeed/scale",
            multiplier)

func _on_smash(target: Character000Base) -> void:
    if not is_instance_valid(_giant) or _giant.is_death:
        return
    if _blast > 0 and is_instance_valid(Global.main_game):
        var origin: Vector2 = (
            target.global_position if is_instance_valid(target)
            else _giant.global_position + Vector2(-65, 0))
        CombatExplosion.detonate.call_deferred(Global.main_game,
                origin, _giant.lane, _giant.get_instance_id(),
                _giant.is_hypno, _blast, _profile)
    if not _giant.is_hypno and is_instance_valid(Global.main_game):
        for i in range(_each_smash_imps):
            _giant.create_imp()

func _on_death() -> void:
    if not is_instance_valid(_giant) or not is_instance_valid(Global.main_game):
        return
    var grid: Array[Array] = Global.main_game.plant_cell_manager.all_plant_cells
    var lane: int = _giant.lane
    if lane < 0 or lane >= grid.size():
        return
    var seen: Dictionary[int, bool] = {}
    for cell: PlantCell in grid[lane]:
        if not is_instance_valid(cell):
            continue
        var span: float = cell.size.x
        var behind: bool = cell.global_position.x <= _giant.global_position.x + span * 0.5
        var near: bool = cell.global_position.x >= _giant.global_position.x - span * 1.8
        if not (behind and near):
            continue
        for plant: Plant000Base in cell.plant_in_cell.values():
            if is_instance_valid(plant) and not plant.is_death:
                var id: int = plant.get_instance_id()
                if not seen.has(id):
                    seen[id] = true
                    plant.be_flattened()
