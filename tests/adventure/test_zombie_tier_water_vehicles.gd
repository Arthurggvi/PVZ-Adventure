extends Node

const SNORKEL := preload("res://scenes/character/zombie/zombie_012_snorkle.tscn")
const ZAMBONI := preload("res://scenes/character/zombie/zombie_013_zamboni.tscn")
const BOBSLED := preload("res://scenes/character/zombie/zombie_014_bobsled.tscn")
const DOLPHIN := preload("res://scenes/character/zombie/zombie_015_dolphinrider.tscn")
const MEMBER := preload("res://scenes/character/zombie/zombie_1001_bobsled_signle.tscn")

var failed := false

func _ready() -> void:
    call_deferred("_test")

func spawn(scene: PackedScene, tier: StringName) -> Zombie000Base:
    var zombie: Zombie000Base = scene.instantiate() as Zombie000Base
    zombie.character_init_type = Character000Base.E_CharacterInitType.IsShow
    check(AdventureZombieTierBinding.new(tier).apply(zombie), "tier bound")
    add_child(zombie)
    return zombie

func check(ok: bool, reason: String) -> void:
    if not ok:
        failed = true
        push_error("ZOMBIE_WATER_VEHICLE_FAIL: " + reason)

func _test() -> void:
    for tier: StringName in [&"base", &"veteran", &"elite", &"tier4", &"tier5"]:
        check(AdventureZombieTierTraits.for_spawn(
            CharacterRegistry.ZombieType.Z011Duckytube, tier).is_empty(),
            "duck: no species abilities")

    # Tier-by-tier numerical contract: no silent value drift in the rule catalog.
    var expected: Dictionary = {
        CharacterRegistry.ZombieType.Z012Snorkle: {
            &"veteran": ["dive_speed", 1.3], &"elite": ["armor_per_second", 50],
            &"tier4": ["armor_per_second", 100], &"tier5": ["armor_per_second", 200],
        },
        CharacterRegistry.ZombieType.Z013Zamboni: {
            &"veteran": ["speed_bonus", 0.2], &"elite": ["reduction", 0.2],
            &"tier4": ["speed_bonus", 0.5], &"tier5": ["death_blast", 1800],
        },
        CharacterRegistry.ZombieType.Z014Bobsled: {
            &"veteran": ["speed", 1.1], &"elite": ["degrade_time_scale", 2.0],
            &"tier4": ["degrade_time_scale", 3.0], &"tier5": ["degrade_time_scale", 0.0],
        },
        CharacterRegistry.ZombieType.Z015Dolphinrider: {
            &"veteran": ["ride_reduction", 0.2], &"elite": ["jump_distance_cells", 2],
            &"tier4": ["crush_damage", 300], &"tier5": ["crush_damage", 1800],
        },
    }
    for species: int in expected:
        for tier: StringName in expected[species]:
            var rules: Array[Dictionary] = AdventureZombieTierTraits.for_spawn(species, tier)
            var contract: Array = expected[species][tier]
            check(rules.size() == 1 and is_equal_approx(
                float(rules[0].get(contract[0], -999.0)), float(contract[1])),
                "catalog species/tier boundary: " + str(species) + "/" + str(tier))

    var snorkel: Zombie012Snorkle = spawn(SNORKEL, &"tier5") as Zombie012Snorkle
    var car: Zombie013Zamboni = spawn(ZAMBONI, &"tier5") as Zombie013Zamboni
    var sled: Zombie014Bobsled = spawn(BOBSLED, &"tier4") as Zombie014Bobsled
    var rider: Zombie015Dolphinrider = spawn(DOLPHIN, &"tier5") as Zombie015Dolphinrider
    var member: Zombie000Base = spawn(MEMBER, &"elite")
    await get_tree().process_frame
    await get_tree().process_frame

    var dive: AdventureZombieSnorkelDive
    for child: Node in snorkel.get_children():
        if child is AdventureZombieSnorkelDive:
            dive = child
    check(dive != null, "snorkel typed behavior attached")
    if dive != null:
        dive.set_process(false)
        snorkel.is_swimming = true
        snorkel.curr_be_attack_status = Zombie000Base.E_BeAttackStatusZombie.IsDownPool
        dive._process(1.1)
        check((snorkel.hp_component as HpComponentZombie).bonus_armor == 200,
            "fifth snorkel receives +200 armor per underwater second")
        check(is_equal_approx(float(snorkel.influence_speed_factors.get(
                Character000Base.E_Influence_Speed_Factor.AdventureTierStance, 1.0)), 1.5),
            "fifth snorkel moves 50 percent faster underwater")
        snorkel.curr_be_attack_status = Zombie000Base.E_BeAttackStatusZombie.IsNorm
        dive._process(1.1)
        check((snorkel.hp_component as HpComponentZombie).bonus_armor == 200,
            "snorkel never gains armor while surfaced")
        check(is_equal_approx(float(snorkel.influence_speed_factors.get(
                Character000Base.E_Influence_Speed_Factor.AdventureTierStance, 1.0)), 1.0),
            "snorkel surface resets underwater movement")

    var pressure: AdventureZombieZamboniPressure
    for child: Node in car.get_children():
        if child is AdventureZombieZamboniPressure:
            pressure = child
    check(pressure != null, "Zamboni pressure component installed")
    if pressure != null:
        check(is_equal_approx(car.hp_component.damage_reduction.effective_reduction(), 0.5),
            "fifth Zamboni inherits 50 percent DR")
        check(is_equal_approx(float(car.influence_speed_factors.get(
            Character000Base.E_Influence_Speed_Factor.AdventureTierStance, 1.0)), 2.0),
            "fifth Zamboni starts at double speed")
        pressure._on_hit(0)
        check(is_equal_approx(float(car.influence_speed_factors.get(
            Character000Base.E_Influence_Speed_Factor.AdventureTierStance, 1.0)), 1.99),
            "even a blocked attack decreases Zamboni bonus by one percentage point")
        for i in range(130):
            pressure._on_hit(0)
        check(is_equal_approx(float(car.influence_speed_factors.get(
            Character000Base.E_Influence_Speed_Factor.AdventureTierStance, 1.0)), 1.0),
            "Zamboni speed bonus stops at zero and never becomes a slowdown")
    var explosion: AdventureZombieDeathBurst
    for child: Node in car.get_children():
        if child is AdventureZombieDeathBurst:
            explosion = child
    check(explosion != null and explosion._damage == 1800 and explosion._profile != null,
        "fifth Zamboni death blast reuses generic CombatExplosion")

    check(is_equal_approx(sled.ice_absence_lifespan_multiplier, 3.0),
        "fourth bobsled non-ice decay takes three times the normal time")
    check(is_equal_approx(float(sled.influence_speed_factors.get(
        Character000Base.E_Influence_Speed_Factor.AdventureTierStance, 1.0)), 1.1),
        "sled gains ten percent speed")
    var sledge5: Zombie014Bobsled = spawn(BOBSLED, &"tier5") as Zombie014Bobsled
    await get_tree().process_frame
    await get_tree().process_frame
    check(is_zero_approx(sledge5.ice_absence_lifespan_multiplier),
        "fifth sled ignores missing-ice decay")
    check(is_equal_approx(float(member.influence_speed_factors.get(
        Character000Base.E_Influence_Speed_Factor.AdventureTierStance, 1.0)), 1.1),
        "detached bobsled member inherits speed trait")

    check(rider.jump_component.jump_distance_cells == 3,
        "fifth dolphin leap uses three actual grid cells")
    check(is_equal_approx(rider.hp_component.damage_reduction.effective_reduction(), 0.5),
        "riding dolphin grants fifth-tier 50 percent DR")
    var dolphin_effect: AdventureZombieDolphinLeap
    for child: Node in rider.get_children():
        if child is AdventureZombieDolphinLeap:
            dolphin_effect = child
    check(dolphin_effect != null, "dolphin has one independent leap behavior")
    if dolphin_effect != null:
        dolphin_effect._on_jump_start()
        check(is_zero_approx(rider.hp_component.damage_reduction.effective_reduction()),
            "dolphin's riding-only DR ends when it leaps off")
        check(dolphin_effect._damage == 1800,
            "fifth dolphin crush damage configured at 1800")

    for species: int in [
        CharacterRegistry.ZombieType.Z011Duckytube,
        CharacterRegistry.ZombieType.Z012Snorkle,
        CharacterRegistry.ZombieType.Z013Zamboni,
        CharacterRegistry.ZombieType.Z014Bobsled,
        CharacterRegistry.ZombieType.Z015Dolphinrider]:
        if species == CharacterRegistry.ZombieType.Z011Duckytube:
            continue
        check(not AdventureZombieTierTraits.description_for(species, &"tier5").is_empty(),
            "Almanac entry for vehicle/water tiers")

    if not failed:
        print("ZOMBIE_WATER_VEHICLE_PASS")
    get_tree().quit(1 if failed else 0)
