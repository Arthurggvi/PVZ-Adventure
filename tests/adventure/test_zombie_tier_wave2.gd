extends Node

const BattleFixture = preload("res://tests/adventure/zombie_tier_battle_fixture.gd") ## 真实战场管理器的测试入口。
const PAPER := preload("res://scenes/character/zombie/zombie_006_paper.tscn")
const DOOR := preload("res://scenes/character/zombie/zombie_007_screendoor.tscn")
const FOOTBALL := preload("res://scenes/character/zombie/zombie_008_football.tscn")
const JACKSON := preload("res://scenes/character/zombie/zombie_009_jackson.tscn")
const DANCER := preload("res://scenes/character/zombie/zombie_010_dancer.tscn")
const PLANT := preload("res://scenes/character/plant/plant_001_pea_shooter_single.tscn")
const PROFILE := preload("res://resources/combat/jackbox_explosion_profile.tres")
const BUCKET := preload("res://scenes/character/zombie/zombie_005_bucket.tscn")
const JACKBOX := preload("res://scenes/character/zombie/zombie_016_jackbox.tscn")


var failed := false
## 测试实体归属的真实战场。
var _battle: MainGameManager

func _ready() -> void:
    call_deferred("_run")

func spawn(scene: PackedScene, tier: StringName) -> Zombie000Base:
    var zombie: Zombie000Base = scene.instantiate() as Zombie000Base
    zombie.character_init_type = Character000Base.E_CharacterInitType.IsShow
    check(AdventureZombieTierBinding.new(tier).apply(zombie), "tier binding")
    _battle.add_child(zombie)
    return zombie

func _run() -> void:
    _battle = BattleFixture.mount(self)
    var paper: Zombie000Base = spawn(PAPER, &"tier5")
    var door: Zombie000Base = spawn(DOOR, &"tier5")
    var football: Zombie000Base = spawn(FOOTBALL, &"tier4")
    var jackson: Zombie000Base = spawn(JACKSON, &"tier4")
    var dancer: Zombie000Base = spawn(DANCER, &"elite")
    await get_tree().process_frame
    await get_tree().process_frame
    var paper_hp: HpComponentZombie = paper.hp_component as HpComponentZombie
    var paper_attack: AttackComponentZombieNorm = paper.attack_component as AttackComponentZombieNorm
    check(is_equal_approx(float(paper_attack.attack_value_factor.get(
        AttackComponentZombieNorm.E_AttackValueFactor.AdventureSpeciesBite, 1.0)), 4.0),
        "fifth newspaper unconditional 300 percent bite bonus")
    paper_hp.curr_hp_armor2 = 0
    await get_tree().process_frame
    await get_tree().process_frame
    check(paper_hp.bonus_armor == 500, "newspaper loss grants 500 extra armor")
    check(is_equal_approx(float(paper_attack.attack_value_factor.get(
        AttackComponentZombieNorm.E_AttackValueFactor.AdventureSpeciesRage, 1.0)), 2.5),
        "fourth newspaper rage inherited at fifth tier")
    check(is_equal_approx(float(paper.influence_speed_factors.get(
        Character000Base.E_Influence_Speed_Factor.AdventureTierStance, 1.0)), 1.5),
        "newspaper loss +50% speed")

    var paper2: Zombie000Base = spawn(PAPER, &"veteran")
    await get_tree().process_frame
    await get_tree().process_frame
    var immediate: HpComponentZombie = paper2.hp_component as HpComponentZombie
    immediate.curr_hp_armor2 = 10
    var paper_body_before: int = immediate.curr_hp
    immediate.Hp_loss(500, BulletRegistry.AttackMode.Norm, true, false)
    check(immediate.is_damage_immune() and immediate.curr_hp == paper_body_before,
        "paper loss immunity applies inside the same armor-breaking hit")

    var bucket4: Zombie000Base = spawn(BUCKET, &"tier4")
    bucket4.lane = 2 # 授甲需要来源位于一个可查询的棋盘攻击行。
    await get_tree().process_frame
    await get_tree().process_frame
    var bucket_hp: HpComponentZombie = bucket4.hp_component as HpComponentZombie
    bucket_hp.curr_hp_armor1 = 10
    var bucket_body_before: int = bucket_hp.curr_hp
    var overflow: int = bucket_hp.resolve_damage(150) - bucket_hp.curr_hp_armor1 # 先扣生效的减伤及铁桶。
    bucket_hp.Hp_loss(150, BulletRegistry.AttackMode.Norm, true, false)
    check(overflow > 0 and bucket_hp.bonus_armor == 200 - overflow
        and bucket_hp.curr_hp == bucket_body_before,
        "bucket armor-loss grant immediately absorbs same-hit overflow")

    var door_hp: HpComponentZombie = door.hp_component as HpComponentZombie
    var door_armor: int = door_hp.curr_hp_armor2
    var body_before: int = door_hp.curr_hp
    door_hp.Hp_loss(100, BulletRegistry.AttackMode.Norm, true, false)
    var armor_loss: int = door_armor - door_hp.curr_hp_armor2
    check(armor_loss == 20 and armor_loss == door_hp.armor2_reduction.reduce_gear(100),
        "fifth screendoor exactly 80% gear-only DR, not body soft cap")
    check(door_hp.curr_hp == body_before, "gear hit does not damage body")
    door_hp.curr_hp_armor2 = 0
    door_hp.Hp_loss(100, BulletRegistry.AttackMode.Norm, true, false)
    check(door_hp.curr_hp == body_before - 100,
        "armor-only DR cannot protect body after the door breaks")
    door_hp.apply_degradation(0.07)
    door_hp.apply_degradation(0.05)
    check(is_equal_approx(door_hp.degradation_fraction, 0.07),
        "degradation takes max, never sums")
    check(door_hp.outgoing_damage(100) == 93 and door_hp.resolve_damage(100) == 107,
        "degradation works on incoming and outgoing damage")
    check(door.body.change_color.has(BodyCharacter.E_ChangeColors.Degradation),
        "degradation has an independent lead-gray color channel")

    var growth: AdventureZombieFootballGrowth
    for child: Node in football.get_children():
        if child is AdventureZombieFootballGrowth:
            growth = child
    check(growth != null, "football lifecycle component attached")
    if growth != null:
        var football_hp: HpComponentZombie = football.hp_component as HpComponentZombie
        var initial_armor: int = football_hp.bonus_armor
        growth._process(1.01)
        check(football_hp.bonus_armor == initial_armor + 20,
            "fourth football generates 20 armor per second")
        var before_factor: float = float(football.influence_speed_factors.get(
            Character000Base.E_Influence_Speed_Factor.AdventureTierStance, 1.0))
        football_hp.Hp_loss(100, BulletRegistry.AttackMode.Norm, true, false)
        check(is_equal_approx(float(football.influence_speed_factors.get(
            Character000Base.E_Influence_Speed_Factor.AdventureTierStance, 1.0)),
            before_factor + 0.005), "fourth football hit adds 0.5 percent speed")

    var king_hp: HpComponentZombie = jackson.hp_component as HpComponentZombie
    king_hp.curr_hp = king_hp.max_hp - 50
    check(king_hp.heal(30) == 30 and king_hp.curr_hp == king_hp.max_hp - 20,
        "shared heal API restores exactly the requested HP")
    check(king_hp.heal(100) == 20 and king_hp.curr_hp == king_hp.max_hp,
        "shared heal API clamps at combat maximum")
    var mock_manager := JacksonManager.new()
    mock_manager.zombie_dancers[-1] = jackson
    var fourth_rules: Array[Dictionary] = AdventureZombieTierTraits.for_spawn(
        CharacterRegistry.ZombieType.Z009Jackson, &"tier4")
    mock_manager.configure_summon_policy(fourth_rules[0])
    for i in range(4):
        mock_manager.zombie_dancers[i] = true
    check(mock_manager.judge_need_call_dance(),
        "fourth king summons even when all four slots already occupied")
    mock_manager.free()
    var king5: Array[Dictionary] = AdventureZombieTierTraits.for_spawn(
        CharacterRegistry.ZombieType.Z009Jackson, &"tier5")
    check(not king5.is_empty() and king5[0].get("replacement_tier") == &"tier4",
        "fifth king replacement tier has explicit recursion boundary")
    check(king5[0].get("replacement_type") ==
        CharacterRegistry.ZombieType.Z009Jackson, "fifth king replaces dancer species")

    var dancer_hp: HpComponentZombie = dancer.hp_component as HpComponentZombie
    check(dancer_hp.is_damage_immune(), "third dancer entry invulnerability")
    var explosion: AdventureZombieDeathBurst
    for child: Node in dancer.get_children():
        if child is AdventureZombieDeathBurst:
            explosion = child
    check(explosion != null and explosion._damage == 1800,
        "third dancer configured for death explosion")
    for species: int in [
        CharacterRegistry.ZombieType.Z006Paper,
        CharacterRegistry.ZombieType.Z007ScreenDoor,
        CharacterRegistry.ZombieType.Z008Football,
        CharacterRegistry.ZombieType.Z009Jackson,
        CharacterRegistry.ZombieType.Z010Dancer]:
        check(not AdventureZombieTierTraits.description_for(species, &"tier5").is_empty(),
            "almanac description exists for each new species")

    var plant: Plant000Base = PLANT.instantiate() as Plant000Base
    plant.character_init_type = Character000Base.E_CharacterInitType.IsShow
    _battle.add_child(plant)
    var plant_area := Area2D.new()
    plant.add_child(plant_area)
    plant_area.owner = plant
    var door_area := Area2D.new()
    door.add_child(door_area)
    door_area.owner = door
    var hit_areas: Array[Area2D] = [plant_area, plant_area, door_area]
    var plant_hp: HpComponent = plant.hp_component
    var plant_before: int = plant_hp.curr_hp
    var door_before: int = door_hp.get_all_hp()
    check(CombatExplosion.resolve_targets(
        hit_areas, 1, 0, -1, false, 50) == 1,
        "explosion de-duplicates overlapping areas and filters plant faction")
    check(plant_hp.curr_hp == plant_before - 50 and door_hp.get_all_hp() == door_before,
        "explosion reaches plant HP once, never harms allied zombies")
    check(CombatExplosion.resolve_targets(
        hit_areas, 1, 0, -1, true, 50) == 1,
        "hypnotized explosion reverses target faction")
    check(door_hp.get_all_hp() == door_before - door_hp.resolve_damage(50),
        "charmed explosion routes numeric damage through zombie HP pools")
    check(PROFILE.shape is RectangleShape2D
            and (PROFILE.shape as RectangleShape2D).size == Vector2(250, 200)
            and PROFILE.visuals != null and PROFILE.lane_radius == 1,
        "native Jackbox explosion shape and FX exposed as reusable profile")
    var native_jackbox: Node = JACKBOX.instantiate()
    check(native_jackbox.get_node("BombComponentJackbox/BombEffect") is BombEffectBase,
        "native Jackbox uses independently extracted shared explosion FX")
    native_jackbox.free()
    check(paper_hp.is_damage_immune(), "paper-loss invulnerability takes effect immediately")
    _battle.queue_free()
    await get_tree().process_frame
    await get_tree().process_frame
    if not failed:
        print("ZOMBIE_TIER_WAVE2_PASS")
    get_tree().quit(1 if failed else 0)

func check(ok: bool, what: String) -> void:
    if not ok:
        failed = true
        push_error("ZOMBIE_TIER_WAVE2_FAIL: " + what)
