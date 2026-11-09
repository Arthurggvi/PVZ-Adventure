extends Node

const PAPER := preload("res://scenes/character/zombie/zombie_006_paper.tscn")
const DOOR := preload("res://scenes/character/zombie/zombie_007_screendoor.tscn")
const FOOTBALL := preload("res://scenes/character/zombie/zombie_008_football.tscn")
const JACKSON := preload("res://scenes/character/zombie/zombie_009_jackson.tscn")
const DANCER := preload("res://scenes/character/zombie/zombie_010_dancer.tscn")

var failed := false

func _ready() -> void:
    call_deferred("_run")

func spawn(scene: PackedScene, tier: StringName) -> Zombie000Base:
    var zombie: Zombie000Base = scene.instantiate() as Zombie000Base
    zombie.character_init_type = Character000Base.E_CharacterInitType.IsShow
    check(AdventureZombieTierBinding.new(tier).apply(zombie), "tier binding")
    add_child(zombie)
    return zombie

func _run() -> void:
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

    var door_hp: HpComponentZombie = door.hp_component as HpComponentZombie
    var door_armor: int = door_hp.curr_hp_armor2
    var body_before: int = door_hp.curr_hp
    door_hp.Hp_loss(100, BulletRegistry.AttackMode.Norm, true, false)
    var armor_loss: int = door_armor - door_hp.curr_hp_armor2
    check(armor_loss == door_hp.armor2_reduction.reduce(100),
        "armor-only DR applies to iron screen door")
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

    var mock_manager := JacksonManager.new()
    mock_manager.zombie_dancers[-1] = jackson
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
    var explosion: AdventureZombieDancerBurst
    for child: Node in dancer.get_children():
        if child is AdventureZombieDancerBurst:
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

    if not failed:
        print("ZOMBIE_TIER_WAVE2_PASS")
    get_tree().quit(1 if failed else 0)

func check(ok: bool, what: String) -> void:
    if not ok:
        failed = true
        push_error("ZOMBIE_TIER_WAVE2_FAIL: " + what)
