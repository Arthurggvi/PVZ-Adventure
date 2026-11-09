extends Node

const JACKBOX := preload("res://scenes/character/zombie/zombie_016_jackbox.tscn")
const BALLOON := preload("res://scenes/character/zombie/zombie_017_balloon.tscn")
const DIGGER := preload("res://scenes/character/zombie/zombie_018_digger.tscn")
const PLANT := preload("res://scenes/character/plant/plant_001_pea_shooter_single.tscn")

var failed := false

func _ready() -> void:
    call_deferred("_run")

func _spawn(scene: PackedScene, tier: StringName = &"") -> Zombie000Base:
    var zombie: Zombie000Base = scene.instantiate() as Zombie000Base
    zombie.character_init_type = Character000Base.E_CharacterInitType.IsShow
    if zombie is Zombie018Digger:
        zombie.position.x = 800.0 # Do not auto-surface the staged test miner at x=0.
    if tier != &"":
        _check(AdventureZombieTierBinding.new(tier).apply(zombie), "spawn tier binding")
    add_child(zombie)
    return zombie

func _check(ok: bool, reason: String) -> void:
    if not ok:
        failed = true
        push_error("ZOMBIE_TIER_WAVE4_FAIL: " + reason)

func _child_of_kind(node: Node, script_kind: Script) -> Node:
    for child: Node in node.get_children():
        if child.get_script() == script_kind:
            return child
    return null

func _run() -> void:
    var vanilla: Zombie017Balloon = _spawn(BALLOON) as Zombie017Balloon
    var balloon5: Zombie017Balloon = _spawn(BALLOON, &"tier5") as Zombie017Balloon
    var jack2: Zombie016Jackbox = _spawn(JACKBOX, &"veteran") as Zombie016Jackbox
    var jack3: Zombie016Jackbox = _spawn(JACKBOX, &"elite") as Zombie016Jackbox
    var jack4: Zombie016Jackbox = _spawn(JACKBOX, &"tier4") as Zombie016Jackbox
    var jack5: Zombie016Jackbox = _spawn(JACKBOX, &"tier5") as Zombie016Jackbox
    var miner2: Zombie018Digger = _spawn(DIGGER, &"veteran") as Zombie018Digger
    var miner5: Zombie018Digger = _spawn(DIGGER, &"tier5") as Zombie018Digger
    var plant: Plant000Base = PLANT.instantiate() as Plant000Base
    plant.character_init_type = Character000Base.E_CharacterInitType.IsShow
    add_child(plant)
    await get_tree().process_frame
    await get_tree().process_frame
    await get_tree().process_frame

    var base_hp: HpComponentZombie = vanilla.hp_component as HpComponentZombie
    _check(base_hp.max_hp_armor1 == 1 and base_hp.armor1_fixed_damage_per_hit == 1,
            "vanilla balloon is exactly one hit point")
    var vanilla_body: int = base_hp.curr_hp
    base_hp.damage_block.set_source(10001, 9000)
    base_hp.Hp_loss(2, BulletRegistry.AttackMode.Norm, false, false)
    base_hp.damage_block.set_source(10001, 0)
    _check(base_hp.curr_hp_armor1 == 0 and base_hp.curr_hp == vanilla_body,
            "even a fully blocked positive hit removes exactly one balloon HP")

    var balloon_hp: HpComponentZombie = balloon5.hp_component as HpComponentZombie
    _check(balloon_hp.max_hp_armor1 == 5 and balloon_hp.curr_hp_armor1 == 5,
            "tier5 balloon has exactly five hits")
    _check(is_equal_approx(float(balloon5.influence_speed_factors.get(
            Character000Base.E_Influence_Speed_Factor.AdventureTierStance, 1.0)), 1.2),
            "flying balloon has 20% extra movement speed")
    var balloon_body: int = balloon_hp.curr_hp
    for i in range(4):
        balloon_hp.Hp_loss(20000, BulletRegistry.AttackMode.Norm, false, false)
    _check(balloon_hp.curr_hp_armor1 == 1 and balloon_hp.curr_hp == balloon_body,
            "four independent massive hits leave one balloon HP")
    balloon_hp.Hp_loss(20000, BulletRegistry.AttackMode.Norm, false, false)
    _check(balloon_hp.curr_hp_armor1 == 0 and balloon_hp.curr_hp == balloon_body,
            "fifth hit breaks balloon and never pierces body")
    _check(is_equal_approx(float(balloon5.influence_speed_factors.get(
            Character000Base.E_Influence_Speed_Factor.AdventureTierStance, 1.0)), 1.0),
            "balloon losing flight resets flight-speed bonus")
    var balloon_ability: AdventureZombieBalloonTier = null
    for c: Node in balloon5.get_children():
        if c is AdventureZombieBalloonTier:
            balloon_ability = c
    _check(balloon_ability != null and balloon_ability._landing_burst != null
            and balloon_ability._landing_burst._damage == 5000,
            "fifth balloon landing-only explosion is configured")
    var water_rules: Array[Dictionary] = AdventureZombieTierTraits.for_spawn(
            CharacterRegistry.ZombieType.Z017Balloon, &"elite")
    _check(water_rules.size() == 1 and int(water_rules[0].get("landing_blast", -1)) == 1800,
            "tier3 balloon death explosion damage")

    var bite: AdventureZombieJackboxTier = null
    var touch: AdventureZombieJackboxTier = null
    for c: Node in jack2.get_children():
        if c is AdventureZombieJackboxTier:
            bite = c
    for c: Node in jack3.get_children():
        if c is AdventureZombieJackboxTier:
            touch = c
    _check(bite != null and touch != null, "second/third Jackbox policy installed")
    if bite != null:
        bite.set_process(false)
        var attack2: AttackComponentZombieNorm = jack2.attack_component as AttackComponentZombieNorm
        attack2.detect_component.enemy_can_be_attacked = plant
        attack2.is_attack_res = true
        bite._process(1.0)
        _check(not jack2.is_pop, "second Jackbox waits longer than one second of chewing")
        bite._process(1.02)
        _check(jack2.is_pop and jack2.bomb_component_jackbox.bomb_value == 8000
                and jack2.bomb_component_jackbox.use_numeric_blast,
                "second Jackbox triggers native pop after two seconds at 8000 damage")
    if touch != null:
        touch.set_process(false)
        var attack3: AttackComponentZombieNorm = jack3.attack_component as AttackComponentZombieNorm
        attack3.detect_component.enemy_can_be_attacked = plant
        touch._process(0.01)
        _check(jack3.is_pop and jack3.bomb_component_jackbox.bomb_value == 8000,
                "third Jackbox detonates immediately on contact, without requiring a bite")

    _check(jack4.survive_first_explosion and jack5.survive_first_explosion
            and jack5.bomb_component_jackbox.bomb_value == 16000,
            "fourth and fifth Jackbox first blast survival, fifth damage double")
    var afterlife: AdventureZombieDeathBurst = null
    for c: Node in jack4.get_children():
        if c is AdventureZombieDeathBurst:
            afterlife = c
    _check(afterlife != null and afterlife._damage == 8000 and afterlife._hit_all_characters
            and not afterlife._armed,
            "second Jackbox explosion is disarmed until the first blast actually completes")
    jack4.is_pop = true
    jack4.bomb_component_jackbox.is_bomb = true
    jack4.character_death_disappear()
    _check(not jack4.is_death and jack4.first_explosion_survived and not jack4.is_pop
            and jack4.iron_type == Zombie000Base.IronType.Null and afterlife._armed,
            "native first pop is survived exactly once, box removed, second blast armed")
    _check(is_equal_approx(float(jack4.influence_speed_factors.get(
            Character000Base.E_Influence_Speed_Factor.AdventureTierStance, 1.0)), 1.1),
            "fourth Jackbox speed +10%")

    _check(is_equal_approx(float(miner2.influence_speed_factors.get(
            Character000Base.E_Influence_Speed_Factor.AdventureTierStance, 1.0)), 2.0),
            "second miner doubles digging speed")
    var miner_tier: AdventureZombieDiggerTier = null
    var miner_burst: AdventureZombieDeathBurst = null
    for c: Node in miner5.get_children():
        if c is AdventureZombieDiggerTier:
            miner_tier = c
        if c is AdventureZombieDeathBurst:
            miner_burst = c
    _check(miner_tier != null and miner_burst != null and miner_burst._damage == 1800
            and miner_burst._profile.lane_radius == 1,
            "fifth miner small radius-one explosion installed")
    if miner_tier != null:
        miner_tier.set_process(false)
        miner5.is_dig = false
        miner_tier._process(0.01)
        _check(is_equal_approx(float(miner5.influence_speed_factors.get(
                Character000Base.E_Influence_Speed_Factor.AdventureTierStance, 1.0)), 1.5),
                "fifth miner surface walking speed +50%")
        miner_tier._on_surfaced()
        _check(miner5.move_component.move_mode == MoveComponent.E_MoveMode.Speed,
                "tier3 miner skips stalled surface transition and begins rightward speed movement")

    var cull_manager := ZombieManager.new()
    cull_manager.all_zombies_1d.append(jack4)
    cull_manager.zombie_range_pos_x = Vector2(-300, 1000)
    jack4.global_position.x = 1200.0
    jack4.nonlethal_displacement_exile = true
    cull_manager.set_zombie_death_over_view()
    _check(not jack4.is_death and jack4.nonlethal_displacement_exile,
            "next-wave offscreen cleanup must not kill a ground wind-retreated zombie")
    jack4.global_position.x = 900.0
    cull_manager.set_zombie_death_over_view()
    _check(not jack4.nonlethal_displacement_exile,
            "ground zombie's wind exemption expires on re-entry")
    cull_manager.free()

    _check(AdventureZombieWindGust.displacement_cells(false) == 2
            and AdventureZombieWindGust.displacement_cells(true) == 4,
            "Blover wind is two cells on ground and four when airborne")
    _check(not AdventureZombieWindGust.is_wind_elimination(false, 2500.0, 1000.0)
            and not AdventureZombieWindGust.is_wind_elimination(true, 999.0, 1000.0)
            and AdventureZombieWindGust.is_wind_elimination(true, 1001.0, 1000.0),
            "Blover only kills a flying unit actually carried out of the view")
    for typ: int in [CharacterRegistry.ZombieType.Z016Jackbox,
            CharacterRegistry.ZombieType.Z017Balloon,
            CharacterRegistry.ZombieType.Z018Digger]:
        _check(not AdventureZombieTierTraits.description_for(typ, &"tier5").is_empty(),
                "new tier Almanac text exists")
    # Active animations/tweens belong to the actors and must be released before
    # quitting the isolated scene (avoids false-positive ObjectDB leak warnings).
    for actor: Node in get_children():
        actor.queue_free()
    await get_tree().process_frame
    await get_tree().process_frame
    await get_tree().create_timer(3.0).timeout # Finish native audio before headless exit.
    if not failed:
        print("ZOMBIE_TIER_WAVE4_PASS")
    get_tree().quit(1 if failed else 0)
