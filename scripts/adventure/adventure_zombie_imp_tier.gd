extends AdventureZombieTierAbility
class_name AdventureZombieImpTier

var _imp: Zombie025Imp
var _degradation := 0.0
var _death_imps := 0
var _child_tier: StringName = &"tier4"

func setup(imp: Zombie025Imp, rule: Dictionary) -> void:
    bind_tier(imp)
    _imp = imp
    _degradation = float(rule.get("degradation", 0.0))
    _death_imps = int(rule.get("death_imps", 0))
    _child_tier = StringName(rule.get("child_tier", &"tier4"))
    var bite: AttackComponentZombieNorm = imp.attack_component as AttackComponentZombieNorm
    if bite != null:
        bite.bite_landed.connect(_on_bite)
    var death_blast: int = int(rule.get("death_blast", 0))
    if death_blast > 0:
        var blast := AdventureZombieDeathBurst.new()
        imp.add_child(blast)
        blast.setup_single_cell(imp, death_blast)
    if _death_imps > 0:
        imp.signal_character_death.connect(_on_death)

func _on_bite(target: Node, _amount: int) -> void:
    if not tier_can_trigger():
        return
    var plant: Plant000Base = target as Plant000Base
    if is_instance_valid(plant) and not plant.is_death:
        AdventurePlantNegativeEffects.apply(plant, AdventurePlantNegativeEffects.Kind.DEGRADATION, _imp.get_instance_id(), _degradation)

## 战斗死亡时按当前阵营派生下一级小鬼；越界离场和清场只注销原实体。
func _on_death() -> void:
    if not tier_can_trigger(true) or _imp.retiring_from_battle:
        return
    var manager: ZombieManager = Global.main_game.zombie_manager
    var lane: int = _imp.lane
    if lane < 0 or lane >= manager.all_zombie_rows.size():
        return
    var attrs: Dictionary = { # 快照原小鬼死亡时的阵营、模式和刷新来源。
        Zombie000Base.E_ZInitAttr.CharacterInitType:
            Character000Base.E_CharacterInitType.IsNorm,
        Zombie000Base.E_ZInitAttr.Lane: lane,
        Zombie000Base.E_ZInitAttr.IsMiniZombie: _imp.is_mini_zombie,
        Zombie000Base.E_ZInitAttr.IsPotZombie: _imp.is_pot_zombie,
        Zombie000Base.E_ZInitAttr.ParticipatesNaturalRefresh:
            _imp.participates_natural_refresh,
        Zombie000Base.E_ZInitAttr.StartsHypnotized: _imp.is_hypno,
    }
    # Deferred call belongs to the long-lived zombie manager, never this
    # dying imp component (which is queued for deletion with its parent).
    var origin: Vector2 = _imp.global_position
    for i in range(_death_imps):
        AdventureZombieTierAbility.spawn_child_if_current.call_deferred(
                Global.main_game, Global.main_game.curr_game_round,
                AdventureSession.get_active_phase(Global.main_game.game_para),
                CharacterRegistry.ZombieType.Z025Imp, attrs,
                origin + Vector2((float(i) - float(_death_imps - 1) / 2.0) * 18.0, 0.0),
                AdventureZombieTierBinding.new(_child_tier))
