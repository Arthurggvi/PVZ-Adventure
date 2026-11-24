extends Node

const POGO := preload("res://scenes/character/zombie/zombie_019_pogo.tscn")
const YETI := preload("res://scenes/character/zombie/zombie_020_yeti.tscn")
const BUNGEE := preload("res://scenes/character/zombie/zombie_021_bungi.tscn")
const LADDER_Z := preload("res://scenes/character/zombie/zombie_022_ladder.tscn")
const CATAPULT := preload("res://scenes/character/zombie/zombie_023_catapult.tscn")
const GIANT := preload("res://scenes/character/zombie/zombie_024_gargantuar.tscn")
const IMP := preload("res://scenes/character/zombie/zombie_025_imp.tscn")
const PLANT := preload("res://scenes/character/plant/plant_001_pea_shooter_single.tscn")
const LADDER := preload("res://scenes/item/game_scenes_item/ladder.tscn")
const BALL := preload("res://scenes/bullet/bullet_013_basketball.tscn")

var failed := false

func _ready() -> void:
    call_deferred("_run")

func check(ok: bool, what: String) -> void:
    if not ok:
        failed = true
        push_error("ZOMBIE_TIER_WAVE5_FAIL: " + what)

func spawn(scene: PackedScene, tier: StringName = &"base") -> Zombie000Base:
    var z: Zombie000Base = scene.instantiate() as Zombie000Base
    z.character_init_type = Character000Base.E_CharacterInitType.IsShow
    check(AdventureZombieTierBinding.new(tier).apply(z), "spawn " + str(tier))
    add_child(z)
    return z

func _run() -> void:
    var pogo2: Zombie019Pogo = spawn(POGO, &"veteran") as Zombie019Pogo
    var pogo3: Zombie019Pogo = spawn(POGO, &"elite") as Zombie019Pogo
    var yeti2: Zombie020Yeti = spawn(YETI, &"veteran") as Zombie020Yeti
    var yeti5: Zombie020Yeti = spawn(YETI, &"tier5") as Zombie020Yeti
    var bungee2: Zombie021Bungi = spawn(BUNGEE, &"veteran") as Zombie021Bungi
    var bungee5: Zombie021Bungi = spawn(BUNGEE, &"tier5") as Zombie021Bungi
    var ladder3: Zombie022Ladder = spawn(LADDER_Z, &"elite") as Zombie022Ladder
    var catapult5: Zombie023Catapult = spawn(CATAPULT, &"tier5") as Zombie023Catapult
    var giant4: Zombie024Gargantuar = spawn(GIANT, &"tier4") as Zombie024Gargantuar
    var giant5: Zombie024Gargantuar = spawn(GIANT, &"tier5") as Zombie024Gargantuar
    var imp2: Zombie025Imp = spawn(IMP, &"veteran") as Zombie025Imp
    var imp5: Zombie025Imp = spawn(IMP, &"tier5") as Zombie025Imp
    var plant: Plant000Base = PLANT.instantiate() as Plant000Base
    plant.character_init_type = Character000Base.E_CharacterInitType.IsShow
    add_child(plant)
    await get_tree().process_frame
    await get_tree().process_frame
    await get_tree().process_frame

    var pogo_effect: AdventureZombiePogoTier
    for n: Node in pogo2.get_children():
        if n is AdventureZombiePogoTier:
            pogo_effect = n
    check(pogo_effect != null and pogo_effect._damage == 300,
            "Pogo second tier swept jump damage 300")
    check(pogo3.big_jump_cells == 2, "Pogo third tier exactly 2 grid cells")

    var yeti_drops: DropItemComponent = yeti5.get_node("DropItemComponent") as DropItemComponent
    check(is_equal_approx(yeti_drops.drop_coin_rate, 0.3)
            and float(yeti_drops.drop_coin_silver_glod_diamond_rate[2]) < 1.0,
            "Yeti loses guaranteed diamond reward but retains ordinary random coins")
    var yeti_hp: HpComponentZombie = yeti5.hp_component as HpComponentZombie
    check(yeti_hp.bonus_armor == 500, "Yeti fifth tier entry armor")
    var y5: AdventureZombieYetiTier
    for n: Node in yeti5.get_children():
        if n is AdventureZombieYetiTier:
            y5 = n
    check(y5 != null and y5._heal == 120 and is_equal_approx(y5._per_hit, 0.04),
            "Yeti fifth tier heal and per-hit speed")
    var y2: AdventureZombieYetiTier
    for n: Node in yeti2.get_children():
        if n is AdventureZombieYetiTier:
            y2 = n
    check(y2 != null, "Yeti second tier installed")
    if y2 != null:
        y2._on_hit(1)
        check(is_equal_approx(float(yeti2.influence_speed_factors.get(
                Character000Base.E_Influence_Speed_Factor.AdventureTierStance, 1.0)), 1.02),
                "Yeti second tier 2 percent speed per hit")
    var yeti_hp2: HpComponentZombie = yeti2.hp_component as HpComponentZombie
    var old_hp: int = yeti_hp2.get_all_hp()
    yeti_hp2.damage_block.set_source(86001, 9000)
    yeti_hp2.Hp_loss(100, BulletRegistry.AttackMode.Norm, false, false)
    check(yeti_hp2.get_all_hp() == old_hp
            and is_equal_approx(float(yeti2.influence_speed_factors.get(
                Character000Base.E_Influence_Speed_Factor.AdventureTierStance, 1.0)), 1.04),
            "Yeti reacts once to a fully blocked attack attempt")
    yeti_hp2.damage_block.set_source(86001, 0)
    var bite: AttackComponentZombieNorm = yeti5.attack_component as AttackComponentZombieNorm
    check(bite != null and is_equal_approx(float(bite.attack_value_factor.get(
            AttackComponentZombieNorm.E_AttackValueFactor.AdventureSpeciesBite, 0.0)), 4.0),
            "Yeti +300 percent bite means four times original")

    check(is_equal_approx(bungee2.linger_seconds, 1.0),
            "Bungee 2nd tier hold duration half")
    check(is_zero_approx(bungee5.linger_seconds),
            "Bungee 5th tier zero hold time")
    var bungee_blast: AdventureZombieDeathBurst
    for n: Node in bungee5.get_children():
        if n is AdventureZombieDeathBurst:
            bungee_blast = n
    check(bungee_blast != null and bungee_blast._damage == 3000,
            "Bungee fifth tier landing-only explosion 3000")

    check(ladder3.allow_any_ladder_target, "Ladder third tier targets every plant")
    var cell: PlantCell = PlantCell.new()
    cell.row_col = Vector2i(1, 2)
    var placed: Ladder = LADDER.instantiate() as Ladder
    placed.init_ladder(cell, &"elite", plant)
    check(placed.max_hp == 2000 and placed.current_hp == 2000,
            "Ladder tier3 2000 HP")
    check(((placed.get_node("Area2DReal") as Area2D).collision_layer & 512) != 0,
            "Placed ladder collision layer is hit by plant projectile mask 512")
    check(plant.process_mode == Node.PROCESS_MODE_DISABLED
            and is_zero_approx(plant.modulate.r)
            and plant.hurt_box_component.process_mode == Node.PROCESS_MODE_ALWAYS,
            "Ladder nullifies plant while keeping combat hurtbox alive")
    check(placed.take_damage(2500) == 2000 and placed.current_hp == 0,
            "Ladder takes actual projectile damage and dies at zero")
    check(plant.process_mode != Node.PROCESS_MODE_DISABLED,
            "Ladder destruction restores plant processing at tier3")
    var ladder5: Ladder = LADDER.instantiate() as Ladder
    ladder5.init_ladder(cell, &"tier5", plant)
    check(ladder5.max_hp == 4000, "Tier5 ladder HP is 4000")
    ladder5.ladder_death()
    check(plant.process_mode == Node.PROCESS_MODE_DISABLED,
            "Tier5 nullification intentionally persists after ladder destruction")
    cell.free()
    placed.free()
    ladder5.free()

    var attack: AttackComponentBulletPultBase = (
            catapult5.attack_component as AttackComponentBulletPultBase)
    check(attack != null and attack.shoot_override.is_valid()
            and attack.target_override.is_valid(),
            "Catapult fifth tier has custom three-lane targeting and volley")
    var basketball: Bullet000NormBase = BALL.instantiate() as Bullet000NormBase
    if attack != null:
        attack.signal_bullet_instantiated.emit(basketball)
        check(basketball.attack_value == 300,
                "Catapult basketball cumulative damage x4 (75 to 300)")
    basketball.free()
    var catapult_effect: AdventureZombieCatapultTier
    for n: Node in catapult5.get_children():
        if n is AdventureZombieCatapultTier:
            catapult_effect = n
    check(catapult_effect != null and catapult_effect._blast == 3600,
            "Catapult fifth tier 3x3 explosion 3600")

    check(giant4.throw_imp_count == 1 and giant5.throw_imp_count == 3,
            "Giant third/fourth smash throws one, fifth native throw sends three")
    var tree: AnimationTree = giant4.get_node("AnimationTree") as AnimationTree
    var root: AnimationNodeBlendTree = tree.tree_root as AnimationNodeBlendTree
    var sm: AnimationNodeStateMachine = (
            root.get_node("StateMachine") as AnimationNodeStateMachine)
    check(sm.get_node("Zombie_gargantuar_smash") is AnimationNodeBlendTree,
            "Giant fourth tier has separate smash-only animation branch")
    var smash_factor: float = float(tree.get(
            "parameters/StateMachine/Zombie_gargantuar_smash/SmashSpeed/scale"))
    check(is_equal_approx(smash_factor, 2.0),
            "Giant fourth-tier smash animation doubles speed without affecting walking")
    check((giant4.hp_component as HpComponentZombie).bonus_armor == 1000,
            "Giant third-tier inherited 1000 armor")
    check(giant5.preserve_death_animation_after_blast,
            "Giant fifth tier explosion death preserves collapse animation")
    # Release locally retained duplicated AnimationTree resources before
    # the test scene frees its two giant actors.
    sm = null
    root = null
    tree = null

    var imp_effect: AdventureZombieImpTier
    for n: Node in imp5.get_children():
        if n is AdventureZombieImpTier:
            imp_effect = n
    check(imp_effect != null and imp_effect._death_imps == 2
            and imp_effect._child_tier == &"tier4",
            "Fifth imp spawns exactly two fourth-tier descendants")
    var imp_bite: AdventureZombieImpTier
    for n: Node in imp2.get_children():
        if n is AdventureZombieImpTier:
            imp_bite = n
    if imp_bite != null:
        imp_bite._on_bite(plant, 10)
        check(is_equal_approx(plant.hp_component.degradation_fraction, 0.5),
                "Imp bite applies exactly 50 percent degradation")

    for typ: int in [CharacterRegistry.ZombieType.Z019Pogo,
            CharacterRegistry.ZombieType.Z020Yeti,
            CharacterRegistry.ZombieType.Z021Bungi,
            CharacterRegistry.ZombieType.Z022Ladder,
            CharacterRegistry.ZombieType.Z023Catapult,
            CharacterRegistry.ZombieType.Z024Gargantuar,
            CharacterRegistry.ZombieType.Z025Imp]:
        check(not AdventureZombieTierTraits.description_for(typ, &"tier5").is_empty(),
                "New species has fifth-tier almanac text")
    for n: Node in get_children():
        n.queue_free()
    await get_tree().process_frame
    await get_tree().process_frame
    # Headless scenes can still have native audio started by base zombie
    # initialization. Allow those short SFX nodes to finish before exit.
    await get_tree().create_timer(3.0).timeout
    if not failed:
        print("ZOMBIE_TIER_WAVE5_PASS")
    get_tree().quit.call_deferred(1 if failed else 0)
