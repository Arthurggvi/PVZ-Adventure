## 巨人的冒险等阶能力，分别配置半血投掷、下砸增援、爆炸和死亡压扁。
extends AdventureZombieTierAbility
class_name AdventureZombieGargantuarTier

## 本能力绑定的巨人，统一通过其原生接口投掷小鬼。
var _giant: Zombie024Gargantuar
## 每次下砸额外投掷的小鬼数量，独立于半血投掷数量。
var _each_smash_imps := 0
## 下砸爆炸伤害，零表示不附加爆炸。
var _blast := 0
## 死亡时是否压扁身下及前方植物。
var _crush := false
## 下砸爆炸使用的范围配置。
var _profile: CombatExplosionProfile

## 为 [param giant] 安装 [param rule] 指定的等阶属性和事件能力。
func setup(giant: Zombie024Gargantuar, rule: Dictionary) -> void:
    bind_tier(giant)
    _giant = giant
    _each_smash_imps = int(rule.get("imp_each_smash", 0))
    _blast = int(rule.get("smash_blast", 0))
    _crush = bool(rule.get("death_crush", false))
    set_tier_property(giant, &"throw_imp_count", int(rule.get("imp_per_throw", 1)))
    set_tier_property(giant, &"preserve_death_animation_after_blast", _crush)
    set_tier_speed(float(rule.get("speed", 1.0)))
    if tier_can_grant_entry():
        (giant.hp_component as HpComponentZombie).grant_bonus_armor(
                int(rule.get("spawn_armor", 0)))
    # 原生下砸组件，仅在需要附加效果时连接完成事件。
    var smash: AttackComponentZombieGargantuar = (
            giant.attack_component as AttackComponentZombieGargantuar)
    if smash != null and (_blast > 0 or _each_smash_imps > 0):
        smash.signal_smash_completed.connect(_on_smash)
    if _blast > 0:
        _profile = AdventureZombieTierExplosionGeometry.small_radius(giant, 1)
    if _crush:
        giant.signal_character_death.connect(_on_death)
    var speed: float = float(rule.get("smash_anim_speed", 1.0)) # 只作用于下砸分支的动画倍速。
    if speed > 1.0:
        _install_smash_only_speed(speed)

## 以 [param multiplier] 单独缩放下砸分支，保留原生状态转换和动画方法轨道。
func _install_smash_only_speed(multiplier: float) -> void:
    var tree: AnimationTree = _giant.get_node("AnimationTree") as AnimationTree # 本巨人的动画树。
    var root: AnimationNodeBlendTree = tree.tree_root.duplicate(true) as AnimationNodeBlendTree # 隔离共享资源。
    var machine: AnimationNodeStateMachine = root.get_node("StateMachine") as AnimationNodeStateMachine # 原生状态机。
    var clip: AnimationRootNode = machine.get_node("Zombie_gargantuar_smash") # 保留方法轨道的原下砸动画。
    var branch := AnimationNodeBlendTree.new() # 只包装下砸动画的独立倍速分支。
    branch.add_node(&"SmashClip", clip)
    branch.add_node(&"SmashSpeed", AnimationNodeTimeScale.new())
    branch.connect_node(&"SmashSpeed", 0, &"SmashClip")
    branch.connect_node(&"output", 0, &"SmashSpeed")
    machine.replace_node(&"Zombie_gargantuar_smash", branch)
    tree.tree_root = root
    set_tier_property(tree, &"parameters/StateMachine/Zombie_gargantuar_smash/SmashSpeed/scale", multiplier)

## 下砸完成后对 [param target] 附加爆炸，并按独立数量策略投掷小鬼。
func _on_smash(target: Character000Base) -> void:
    if not tier_can_trigger():
        return
    if _blast > 0:
        # 优先以仍有效的下砸目标定位爆炸，否则使用巨人前方的原生偏移。
        var origin: Vector2 = (
            target.global_position if is_instance_valid(target)
            else _giant.global_position + Vector2(-65, 0))
        queue_tier_explosion(origin, _giant.lane, _blast, _profile)
    _giant.throw_smash_imps(_each_smash_imps)

## 死亡时按原有格距范围压扁植物，同一株植物只处理一次。
func _on_death() -> void:
    if not tier_can_trigger(true):
        return
    if not is_instance_valid(_giant) or not is_instance_valid(Global.main_game):
        return
    var grid: Array[Array] = Global.main_game.plant_cell_manager.all_plant_cells # 当前战场的种植格。
    var lane: int = _giant.lane # 只处理巨人所在行。
    if lane < 0 or lane >= grid.size():
        return
    var seen: Dictionary[int, bool] = {} # 记录已压扁植物，避免多格占位重复处理。
    var crush: CombatHitScope = CombatHitScope.for_plant_attack(_giant, CombatHitScope.PlantImpact.CRUSH) # 亡语仍按原生区域碾压处理。
    for cell: PlantCell in grid[lane]: # 逐格判断原有的身下及前方覆盖范围。
        if not is_instance_valid(cell):
            continue
        var span: float = cell.size.x # 使用实际格宽换算压扁距离。
        var behind: bool = cell.global_position.x <= _giant.global_position.x + span * 0.5 # 后侧半格边界。
        var near: bool = cell.global_position.x >= _giant.global_position.x - span * 1.8 # 前方最远边界。
        if not (behind and near):
            continue
        for plant: Plant000Base in cell.living_plants(): # 不占种植位的伴生同样参与目标选择或伤害。
            if is_instance_valid(plant) and not plant.is_death:
                var id: int = plant.get_instance_id() # 使用实例标识对跨格植物去重。
                if not seen.has(id):
                    seen[id] = true
                    plant.be_hit_instantly(crush)
