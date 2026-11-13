extends Node

const BUCKET: PackedScene = preload("res://scenes/character/zombie/zombie_005_bucket.tscn")
const CONE: PackedScene = preload("res://scenes/character/zombie/zombie_003_cone.tscn")
## 通过原生场景装配战斗环境。
const BattleFixture = preload("res://tests/adventure/zombie_tier_battle_fixture.gd")
var _failed := false

func _ready() -> void:
    call_deferred("_run")

## 将 [param scene] 实体放入 [param battle] 的测试攻击行 [param lane] 与横坐标 [param x]。
func _spawn(scene: PackedScene, battle: MainGameManager, lane: int, x: float) -> Zombie000Base:
    var zombie: Zombie000Base = scene.instantiate() as Zombie000Base
    zombie.character_init_type = Character000Base.E_CharacterInitType.IsShow
    zombie.lane = lane
    zombie.position = Vector2(x, lane * 80.0)
    battle.add_child(zombie)
    return zombie

func _run() -> void:
    var game: MainGameManager = BattleFixture.mount(self) # 使用已注册地块的真实草坪。
    var manager: ZombieManager = game.zombie_manager # 来源需与当前战场管理器一致。
    var source := _spawn(BUCKET, game, 2, 400)
    var nearby := _spawn(CONE, game, 3, 450)
    var far := _spawn(CONE, game, 4, 450)
    await get_tree().process_frame
    manager.all_zombies_1d.append(source)
    manager.all_zombies_1d.append(nearby)
    manager.all_zombies_1d.append(far)

    var rule := AdventureZombieTierTraits.for_spawn(
        CharacterRegistry.ZombieType.Z005Bucket, &"tier5")[0]
    var field := AdventureZombieTierField.new()
    add_child(field)
    field.setup(source, manager, rule)
    var sh: HpComponentZombie = source.hp_component as HpComponentZombie
    var nh: HpComponentZombie = nearby.hp_component as HpComponentZombie
    var fh: HpComponentZombie = far.hp_component as HpComponentZombie
    _expect(is_equal_approx(sh.damage_reduction.effective_reduction(), 0.5),
        "tier5 bucket own 50%")
    _expect(is_equal_approx(nh.damage_reduction.effective_reduction(), 0.35),
        "neighbor 35% DR")
    _expect(is_zero_approx(fh.damage_reduction.effective_reduction()),
        "beyond one cell no effect")
    var source_start: int = sh.get_all_hp()
    var neighbor_start: int = nh.get_all_hp()
    nh.Hp_loss(100, BulletRegistry.AttackMode.Norm, true, false)
    _expect(nh.get_all_hp() == neighbor_start, "neighbor protected by helmeted bucket")
    _expect(sh.get_all_hp() == source_start - 50,
        "redirected hit gets protector DR (full pipeline)")
    nearby.position.x = 700
    field._refresh()
    _expect(is_zero_approx(nh.damage_reduction.effective_reduction()),
        "aura removed on leaving range")
    nearby.position.x = 450
    field._refresh()
    _expect(is_equal_approx(nh.damage_reduction.effective_reduction(), 0.35),
        "aura reapplied on returning")
    sh.curr_hp_armor1 = 0
    var next_start: int = nh.get_all_hp()
    nh.Hp_loss(100, BulletRegistry.AttackMode.Norm, true, false)
    _expect(nh.get_all_hp() == next_start - 65,
        "no transfer after helmet loss; target DR remains")
    field.clear()
    _expect(is_zero_approx(sh.damage_reduction.effective_reduction()),
        "bucket aura cleans self source")
    _expect(is_zero_approx(nh.damage_reduction.effective_reduction()),
        "bucket aura cleans neighbor source")
    if not _failed:
        print("ZOMBIE_TIER_BUCKET_FIELD_PASS")
    get_tree().quit(1 if _failed else 0)

func _expect(ok: bool, message: String) -> void:
    if not ok:
        _failed = true
        push_error("ZOMBIE_TIER_BUCKET_FIELD_FAIL: " + message)
