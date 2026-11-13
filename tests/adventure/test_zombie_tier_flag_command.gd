extends Node

const FLAG: PackedScene = preload("res://scenes/character/zombie/zombie_002_flag.tscn")
const BUCKET: PackedScene = preload("res://scenes/character/zombie/zombie_005_bucket.tscn")
## 通过原生场景装配战斗环境。
const BattleFixture = preload("res://tests/adventure/zombie_tier_battle_fixture.gd")
var _failed := false

func _ready() -> void:
    call_deferred("_run")

## 实例化 [param scene] 作为 [param battle] 的测试实体。只给 [param tier] 非空的实体装配正式等阶。
func _spawn(scene: PackedScene, battle: MainGameManager, tier: StringName = &"") -> Zombie000Base:
    var zombie: Zombie000Base = scene.instantiate() as Zombie000Base
    zombie.character_init_type = Character000Base.E_CharacterInitType.IsShow
    if not tier.is_empty():
        _expect(AdventureZombieTierBinding.new(tier).apply(zombie), "tier binding")
    battle.add_child(zombie)
    return zombie

func _run() -> void:
    var battle: MainGameManager = BattleFixture.mount(self) # 号令及接收者归属同一真实战场。
    var f1 := _spawn(FLAG, battle)
    var f2 := _spawn(FLAG, battle)
    var receiver := _spawn(BUCKET, battle)
    await get_tree().process_frame
    var manager := ZombieManager.new()
    manager.all_zombies_1d.append(f1)
    manager.all_zombies_1d.append(f2)
    manager.all_zombies_1d.append(receiver)
    var hp: HpComponentZombie = receiver.hp_component as HpComponentZombie
    var normal := ZombieBlockAura.new()
    add_child(normal)
    normal.setup(manager, 30)
    var c1 := AdventureZombieFlagCommand.new()
    add_child(c1)
    c1.setup(f1, manager, AdventureZombieTierTraits.for_spawn(
            CharacterRegistry.ZombieType.Z002Flag, &"veteran")[0])
    var c2 := AdventureZombieFlagCommand.new()
    add_child(c2)
    c2.setup(f2, manager, AdventureZombieTierTraits.for_spawn(
            CharacterRegistry.ZombieType.Z002Flag, &"tier4")[0])
    _expect(hp.damage_block.value == 55,
        "ordinary maximum 30 + additive flag 10 + additive flag 15")
    c1.clear()
    _expect(hp.damage_block.value == 45, "removing one flag keeps second")
    c2.clear()
    _expect(hp.damage_block.value == 30, "removing both flags keeps ordinary block")
    normal.clear()
    _expect(hp.damage_block.value == 0, "all sources removed")

    # 出生号令使用正式等阶绑定，与永久光环共用同一个入场资格。
    var battle_manager: ZombieManager = battle.zombie_manager # 生产派发器读取的管理器。
    battle_manager.all_zombies_1d.append(receiver)
    var fifth := _spawn(FLAG, battle, &"tier5") # 出生时由正式派发器创建号令。
    await get_tree().process_frame
    var c5: AdventureZombieFlagCommand # 找到真实创建的第五阶号令节点。
    for ability: Node in fifth.get_node("AdventureTierBehavior").get_children():
        if ability is AdventureZombieFlagCommand:
            c5 = ability
            break
    assert(c5 != null)
    _expect(hp.damage_block.value == 15, "tier5 additive 15 block")
    _expect(hp.is_damage_immune(), "tier5 global entry immunity")
    var speed: float = float(receiver.influence_speed_factors.get(
        Character000Base.E_Influence_Speed_Factor.AdventureTierBoost, 1.0))
    _expect(is_equal_approx(speed, 2.0), "tier5 global entry speed double")
    var attack: AttackComponentZombieNorm = receiver.attack_component as AttackComponentZombieNorm
    var original: int = attack.curr_attack_value_per_min
    c5.pulse()
    _expect(attack.curr_attack_value_per_min == original * 2,
        "tier5 inherits tier4 bite pulse")
    var timed: AdventureZombieTimedCombatBuff = receiver.get_node(
        "AdventureTimedCombatBuff") as AdventureZombieTimedCombatBuff
    timed.set_process(false)
    timed._process(1.1)
    _expect(not hp.is_damage_immune(), "entry invulnerability expires")
    _expect(attack.curr_attack_value_per_min == original, "bite pulse expires")
    var speed_buff: AdventureZombieTimedSpeedBoost = receiver.get_node(
        "AdventureTimedSpeedBoost") as AdventureZombieTimedSpeedBoost
    speed_buff.set_process(false)
    speed_buff._process(1.1)
    _expect(is_equal_approx(float(receiver.influence_speed_factors.get(
        Character000Base.E_Influence_Speed_Factor.AdventureTierBoost, 1.0)), 1.0),
        "entry speed boost expires")
    c5.clear()
    _expect(hp.damage_block.value == 0, "tier5 flag cleanup")
    manager.free()

    if not _failed:
        print("ZOMBIE_TIER_FLAG_COMMAND_PASS")
    get_tree().quit(1 if _failed else 0)

func _expect(ok: bool, message: String) -> void:
    if not ok:
        _failed = true
        push_error("ZOMBIE_TIER_FLAG_COMMAND_FAIL: " + message)
