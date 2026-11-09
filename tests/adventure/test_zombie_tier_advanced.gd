extends Node

const FLAG: PackedScene = preload("res://scenes/character/zombie/zombie_002_flag.tscn")
const POLE: PackedScene = preload("res://scenes/character/zombie/zombie_004_pole_vaulter.tscn")
const BUCKET: PackedScene = preload("res://scenes/character/zombie/zombie_005_bucket.tscn")
const FACTOR := Character000Base.E_Influence_Speed_Factor.AdventureTierStance

var _failed := false

func _ready() -> void:
    call_deferred("_run")

func _spawn(scene: PackedScene, tier: StringName = &"") -> Zombie000Base:
    var zombie: Zombie000Base = scene.instantiate() as Zombie000Base
    zombie.character_init_type = Character000Base.E_CharacterInitType.IsShow
    if tier != &"":
        _expect(AdventureZombieTierBinding.new(tier).apply(zombie), "spawn tier bound")
    add_child(zombie)
    return zombie

func _run() -> void:
    var block := DamageBlockEffect.new()
    block.set_source(1, 15)
    block.set_source(2, 9)
    block.set_stackable_source(3, 10)
    block.set_stackable_source(4, 10)
    _expect(block.value == 35 and block.reduce(100) == 65, "ordinary max + flags sum")
    block.set_stackable_source(3, 0)
    _expect(block.value == 25, "remove one flag only")
    block.set_source(1, 0)
    _expect(block.value == 19, "remove ordinary max recalculates")

    var dr := DamageReductionEffect.new()
    dr.set_source(1, 0.5)
    dr.set_source(2, 0.5)
    _expect(is_equal_approx(dr.effective_reduction(), 0.715), "DR soft cap at raw 75%")
    _expect(dr.reduce(1000) == 285, "DR applied damage")
    dr.set_source(1, 0.99)
    dr.set_source(2, 0.99)
    _expect(is_equal_approx(dr.effective_reduction(), 0.78997), "DR high threshold curve")
    dr.set_source(1, 0)
    dr.set_source(2, 0)

    var defender := _spawn(BUCKET)
    await get_tree().process_frame
    var health: HpComponentZombie = defender.hp_component as HpComponentZombie
    health.damage_block.set_source(100, 10)
    health.damage_reduction.set_source(101, 0.2)
    health.grant_bonus_armor(200)
    var before_hp := health.curr_hp_armor1
    health.Hp_loss(100, BulletRegistry.AttackMode.Norm, true, false)
    _expect(health.bonus_armor == 128 and health.curr_hp_armor1 == before_hp,
        "block -> DR -> extra armor before native helmet")
    var shield_before := health.bonus_armor
    health.apply_unblocked_loss(before_hp, BulletRegistry.AttackMode.Norm, false, false)
    _expect(health.curr_hp_armor1 == 0 and health.bonus_armor == shield_before,
        "forced helmet removal bypasses temporary shield")
    health.Hp_loss_death(false)
    _expect(health.get_all_hp() == 0 and health.bonus_armor == 0,
        "forced death clears every remaining HP pool including temporary armor")

    var victim := _spawn(FLAG)
    var protector := _spawn(BUCKET)
    await get_tree().process_frame
    victim.lane = 2
    protector.lane = 3
    victim.global_position = Vector2(400, 120)
    protector.global_position = Vector2(450, 180)
    var v_hp := victim.hp_component as HpComponentZombie
    var p_hp := protector.hp_component as HpComponentZombie
    v_hp.damage_transfer.set_source(200, protector, 80.0)
    var v_before: int = v_hp.get_all_hp()
    var p_before: int = p_hp.get_all_hp()
    v_hp.Hp_loss(100, BulletRegistry.AttackMode.Norm, true, false)
    _expect(v_hp.get_all_hp() == v_before, "protected victim takes no damage")
    _expect(p_hp.get_all_hp() == p_before - 100, "protector runs its own hit pipeline")
    protector.global_position.x = 600
    v_hp.Hp_loss(100, BulletRegistry.AttackMode.Norm, true, false)
    _expect(v_hp.get_all_hp() == v_before - 100, "outside range no transfer")
    protector.global_position.x = 450
    p_hp.curr_hp_armor1 = 0
    v_hp.Hp_loss(100, BulletRegistry.AttackMode.Norm, true, false)
    _expect(v_hp.get_all_hp() == v_before - 200, "broken helmet stops transfer")

    var attacker := victim.attack_component as AttackComponentZombieNorm
    var base_bite := attacker.curr_attack_value_per_min
    AdventureZombieTimedCombatBuff.grant_bite(victim, 2.0, 1.0)
    _expect(attacker.curr_attack_value_per_min == base_bite * 2, "bite pulse doubles DPS")
    var buff := victim.get_node("AdventureTimedCombatBuff") as AdventureZombieTimedCombatBuff
    buff.set_process(false)
    buff._process(1.01)
    _expect(attacker.curr_attack_value_per_min == base_bite, "bite pulse expires")
    AdventureZombieTimedCombatBuff.grant_immunity(victim, 1.0)
    var v_no_hit: int = v_hp.get_all_hp()
    v_hp.Hp_loss(100, BulletRegistry.AttackMode.Norm, true, false)
    _expect(v_hp.get_all_hp() == v_no_hit, "pulse immunity blocks damage")
    buff._process(1.01)
    _expect(not v_hp.is_damage_immune(), "pulse immunity expires cleanly")

    AdventureZombieTimedCombatBuff.grant_immunity(victim, 0.5, true)
    AdventureZombieTimedCombatBuff.grant_bite(victim, 2.0, 0.5)
    AdventureZombieTimedSpeedBoost.apply_to(victim, 2.0, 0.5)
    victim.is_hypno = true
    victim.signal_character_be_hypno.emit()
    _expect(v_hp.is_damage_immune(), "innate immunity survives allegiance change")
    _expect(attacker.curr_attack_value_per_min == base_bite,
        "external bite pulse is cleared on allegiance change")
    _expect(is_equal_approx(float(victim.influence_speed_factors.get(
        Character000Base.E_Influence_Speed_Factor.AdventureTierBoost, 1.0)), 1.0),
        "transient movement buff resets on allegiance change")
    buff._process(0.6)
    _expect(not v_hp.is_damage_immune(), "retained innate immunity expires normally")
    victim.is_hypno = false

    var pole4 := _spawn(POLE, &"tier4") as Zombie004PoleVaulter
    await get_tree().process_frame
    var jump4: JumpComponent = pole4.jump_component
    _expect(jump4.max_jumps == 2, "fourth pole gets two jumps")
    _expect(is_equal_approx(pole4.hp_component.damage_reduction.effective_reduction(), 0.4),
        "fourth pole carries 40% DR")
    _expect(is_equal_approx(float(pole4.influence_speed_factors.get(FACTOR, 1.0)), 1.5),
        "pole carrying speed 150%")
    jump4.is_jumping = true
    jump4.jump_end()
    _expect(jump4.is_landing, "jump enters landing lock")
    jump4.jump_start(false)
    _expect(not jump4.is_jumping and jump4.completed_jumps == 1,
        "landing lock prevents overlapping jump start")
    await get_tree().process_frame
    await get_tree().process_frame
    await get_tree().process_frame
    _expect(jump4.completed_jumps == 1 and jump4.has_remaining_jumps(),
        "first jump retains pole")
    jump4.is_jumping = true
    jump4.jump_end()
    await get_tree().process_frame
    await get_tree().process_frame
    await get_tree().process_frame
    _expect(jump4.completed_jumps == 2 and not jump4.has_remaining_jumps(),
        "second jump exhausts pole")
    _expect(is_equal_approx(pole4.hp_component.damage_reduction.effective_reduction(), 0.0),
        "pole DR removed on final jump")
    _expect(is_equal_approx(float(pole4.influence_speed_factors.get(FACTOR, 1.0)), 1.15),
        "pole lost speed 115%")
    var pole5 := _spawn(POLE, &"tier5") as Zombie004PoleVaulter
    await get_tree().process_frame
    _expect(pole5.jump_component.max_jumps == 3 and pole5.jump_component.jump_distance_cells == 2,
        "fifth pole three two-cell jumps")
    _expect(not AdventureZombieTierTraits.description_for(
            CharacterRegistry.ZombieType.Z005Bucket, &"tier5").is_empty(),
        "almanac description lookup")
    _expect(AdventureZombieTierTraits.description_for(
            CharacterRegistry.ZombieType.Z001Norm, &"tier5").is_empty(),
        "no invented normal-zombie species description")

    if not _failed:
        print("ZOMBIE_TIER_ADVANCED_PASS")
    get_tree().quit(1 if _failed else 0)

func _expect(ok: bool, message: String) -> void:
    if not ok:
        _failed = true
        push_error("ZOMBIE_TIER_ADVANCED_FAIL: " + message)
