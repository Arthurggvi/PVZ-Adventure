## 高坚果四阶在正式目录和真实战场的回归。
extends Node

## 测试卡与图书馆查询共用的物种。
const NUT := CharacterRegistry.PlantType.P024TallNut
## 逐阶核对玩家可选的技能书及其顺序。
const BOOKS: Array[String] = ["promotion_tallnut_taishan", "promotion_tallnut_undying",
	"promotion_tallnut_guard", "promotion_tallnut_thorns", "promotion_tallnut_jail",
	"promotion_tallnut_iron", "promotion_tallnut_blessing", "promotion_tallnut_tyr"]
## 图书馆真实常规池。
const Library = preload("res://scripts/adventure/library/library_rules.gd")
## 当前真实战场。
var _game: MainGameManager
## 失败条数决定最终退出码。
var _failures: int = 0

## 保持测试节点跨越真实换场。
func _ready() -> void:
	get_tree().current_scene = null
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

## 记录失败的 [param label]，其余独立情况继续执行。
func _check(ok: bool, label: String) -> bool:
	if not ok:
		_failures += 1
		printerr("TALLNUT_FAIL ", label)
	return ok

## 只在隔离目录载入正式战场。
func _run() -> void:
	if not _check(OS.get_user_data_dir().contains("tallnut-promotions"), "isolated user data"):
		get_tree().quit(1)
		return
	Global.save_service.stop_autosave()
	_catalog()
	if await _open():
		await _health_and_armor()
		await _bodyguard()
		await _crush_and_reflect()
		if OS.get_cmdline_user_args().has("--stress"):
			await _stress()
		await _vehicle_overlap()
		await _explosions()
		await _blessing()
		await _boss_reflect()
	if is_instance_valid(_game):
		_game.queue_free()
		await _wait(4)
	print("TALLNUT_RESULT=", "PASS" if _failures == 0 else "FAIL", " failures=", _failures)
	get_tree().quit(0 if _failures == 0 else 1)

## 技能书可从物品目录、图书馆及正式转职入口取得。
func _catalog() -> void:
	var card: PlantCardInstance = _record([]) # 从一转逐阶推进。
	for tier: int in range(4): # 每阶两个独立书目。
		var expected: Array[String] = BOOKS.slice(tier * 2, tier * 2 + 2) # 当前应显示的两个稳定编号。
		for id: String in expected: # 背包系统识别的物品。
			_check(ItemRegistry.has_item(id), "registered item " + id)
		_check(Library.pool(tier + 1, NUT) == expected, "library tier %s" % [tier + 1])
		_check(AdventurePromotionCatalog.options(card).map(func(entry: Dictionary): return entry.id)
			== expected, "choices at tier %s" % [tier + 1])
		card.set_promotion(tier + 1, expected[0])
	_check(AdventurePromotionCatalog.is_valid_chain(card) and AdventurePromotionCatalog.options(card).is_empty(),
		"consecutive route completes four promotions")
	var data := AdventureState.new() # 不读写玩家真实档案。
	AdventureQuestService.record_event(data, "stage_cleared", "zombie_island.lawn/normal", "2026-11-24")
	data.quests.records["first_expedition"].status = "claimed"
	var bag := AdventureInventoryService.new(data) # 正式技能书扣除入口。
	var wallet := GlobalGameState.new() # 四次转职所需金币。
	wallet.adventure_state = data
	wallet.coin_value = 20000
	var research := AdventureResearchService.new(data, bag, wallet, func() -> bool: return true) # 模拟许可提交的隔离账户。
	var uid: String = bag.add_card(NUT, 10) # 可选择全部四阶。
	for tier: int in range(4): # 每次消耗自己那一阶的书。
		var id: String = BOOKS[2 * tier] # 从第一选项完成一条合法路线。
		bag.add_item(id, 1)
		_check(research.execute("promotion", {"uid": uid, "book_id": id}).ok
			and bag.get_item_count(id) == 0 and wallet.coin_value == 15000 - tier * 5000, "research upgrades and consumes tier %s" % [tier + 1])
	wallet.free()

## 使用原生泳池测试植物碰撞，不启用随机刷怪。
func _open() -> bool:
	var level: ResourceLevelData = load("res://resources/level_date_resource/mode_adventure/adventure_03_pool.tres").duplicate(true) # 隔离的关卡配置。
	level.look_show_zombie = false
	level.can_choosed_card = false
	level.monster_mode = ConstLevelData.E_MonsterMode.Null
	level.is_day_sun = false
	level.prechosen_cards = [ResourceCardReference.create(ResourceCardReference.CardType.Plant, NUT)]
	Global.game_para = level
	if not _check(get_tree().change_scene_to_file("res://scenes/main/MainGame02Back.tscn") == OK, "load native battle"):
		return false
	for _frame: int in range(360): # 有界等待原生进场。
		await get_tree().physics_frame
		_game = Global.main_game
		if is_instance_valid(_game) and _game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME:
			return true
	return _check(false, "native battle ready")

## 按 [param choices] 的书目索引冻结真实十星卡。
func _record(choices: Array[int]) -> PlantCardInstance:
	var record := PlantCardInstance.new() # 普通对照也使用同星级的配方。
	record.uid = "PC000024"
	record.plant_type = NUT
	record.stars = 10
	for i: int in range(choices.size()): # 连续选择每一阶。
		record.set_promotion(i + 1, BOOKS[choices[i]])
	return record

## 使用 [param choices] 在 [param address] 种植 [param species]。
func _plant(address: Vector2i, choices: Array[int] = [], species: CharacterRegistry.PlantType = NUT) -> Plant000Base:
	var cell: PlantCell = _game.board.cell_at(address) # 正式格子。
	var profile: PlantSpawnProfile = null # 其他物种为原版对照。
	if species == NUT:
		profile = PlantSpawnProfile.create(_record(choices).to_dict(), AdventureResearchBattleEffects.new())
	var plant: Plant000Base = cell.create_plant(species, false, false, false, false, profile) # 实际出生事务。
	_check(plant != null, "place plant at %s" % [address])
	return plant

## 泰山与提尔按最终倍率叠加，不灭按实时本体生命并限制护甲上限。
func _health_and_armor() -> void:
	var plain: Plant000Base = _plant(Vector2i(0, 0)) # 同星级的生命基线。
	var tai: Plant000Base = _plant(Vector2i(0, 1), [0]) # 泰山单独生效。
	var tyr: Plant000Base = _plant(Vector2i(0, 2), [0, 2, 4, 7]) # 两个最终倍率叠乘。
	var armored: Plant000Base = _plant(Vector2i(0, 3), [1]) # 单独观察积甲。
	if plain != null and tai != null and tyr != null and armored != null:
		# 出生修饰器对最终生命统一取整，不能先按原卡显示值取整再乘一次。
		_check(roundi(tai.hp_component.max_hp / 3.0) == plain.hp_component.max_hp, "Taishan triples maximum")
		_check(roundi(tyr.hp_component.max_hp / 27.0) == plain.hp_component.max_hp, "Tyr multiplies by nine")
		var health := armored.hp_component as HpComponentPlant # 原生技能护甲池。
		health.curr_hp = 1001
		await _wait(64)
		_check(health.bonus_armor == 100, "armor tick uses remaining life")
		health.grant_bonus_armor(3 * health.max_hp - 101)
		await _wait(64)
		_check(health.bonus_armor == 3 * health.max_hp, "armor stops at three times maximum")
	await _retire([plain, tai, tyr, armored])

## 代伤只前进一步，回执和扣血的角色一致。
func _bodyguard() -> void:
	var victim: Plant000Base = _plant(Vector2i(1, 2), [], CharacterRegistry.PlantType.P001PeaShooterSingle) # 身后一格。
	var guard: Plant000Base = _plant(Vector2i(1, 3), [0, 2]) # 实际承伤。
	var next: Plant000Base = _plant(Vector2i(1, 4), [0, 2]) # 本击不会再转出去。
	if victim != null and guard != null and next != null:
		var receipt: Dictionary = {} # 一次命中的真实承伤回执。
		victim.be_attacked_bullet(80, BulletRegistry.AttackMode.Norm, true, false, 0, -1, receipt)
		_check(victim.hp_component.curr_hp == victim.hp_component.max_hp
			and guard.hp_component.curr_hp == guard.hp_component.max_hp - 80
			and next.hp_component.curr_hp == next.hp_component.max_hp
			and receipt.get("recipient") == guard and receipt.get("actual_loss") == 80, "guard takes one hit without chaining")
		var destination: PlantCell = _game.board.cell_at(Vector2i(1, 5)) # 当场搬走第一株护卫。
		_check(guard.plant_cell.relocate_plant(guard, destination), "relocate guard through native board API")
		victim.be_attacked_bullet(30, BulletRegistry.AttackMode.Norm, true, false)
		_check(victim.hp_component.curr_hp == victim.hp_component.max_hp - 30, "moving away clears old protection")
	await _retire([victim, guard, next])

## 反伤读取护甲和生命的实际损失，原生必杀碾压应折算为十分之一。
func _crush_and_reflect() -> void:
	var plant: Plant000Base = _plant(Vector2i(4, 2), [0, 3, 4]) # 监牢搭配荆棘血。
	var attacker: Zombie000Base = _zombie(Vector2i(4, 8)) # 真实攻击者。
	if plant != null and attacker != null:
		var hp := plant.hp_component as HpComponentPlant # 独立的本体和护甲。
		hp.grant_bonus_armor(100)
		plant.be_zombie_eat(140, attacker)
		_check(hp.bonus_armor == 0 and hp.curr_hp == hp.max_hp - 40
			and attacker.hp_component.curr_hp == 5000 - 140, "thorns returns actual armor and body loss")
		var before: int = hp.curr_hp # 啃食后扣除的大额普通攻击。
		var cap: int = floori(hp.max_hp * 0.10) # 十分之一向下取整。
		plant.be_attacked_bullet(hp.max_hp, BulletRegistry.AttackMode.Norm, true, false)
		_check(hp.curr_hp == before - cap, "jail caps one hit")
		before = hp.curr_hp
		plant.be_flattened_from_enemy(attacker)
		_check(not plant.is_death and hp.curr_hp == before - cap, "native lethal crush becomes one tenth")
	if is_instance_valid(attacker):
		attacker.retire_from_battle()
	await _retire([plant])

## 驱动原生冰车真实碰撞，核对持续重叠只扣一次和虚化恢复。
func _vehicle_overlap() -> void:
	var plant: Plant000Base = _plant(Vector2i(4, 3), [0, 2, 4]) # 监牢，无反伤影响冰车。
	var car: Zombie000Base = _zombie(Vector2i(4, 8), CharacterRegistry.ZombieType.Z013Zamboni) # 第一帧在格外。
	if plant != null and car != null:
		var shape := car.get_node(^"AttackComponent/DetectComponent/Area2d/CollisionShape2D") as CollisionShape2D # 读取车头的真实受力范围。
		var alpha: float = plant.body.modulate.a # 原版体色透明度作为恢复基准。
		var health: int = plant.hp_component.curr_hp # 满血遇上第一次实际碾压。
		var tenth: int = floori(plant.hp_component.max_hp * 0.1) # 理论单次碰撞损失。
		await _wait(4)
		var hurt_area := plant.hurt_box_component.get_node(^"HurtBoxDetection") as Area2D # 冰车索敌使用的原生植株区域。
		car.global_position += hurt_area.global_position - shape.global_position
		await _wait(20)
		_check(plant.hp_component.curr_hp == health - tenth and plant.body.modulate.a < alpha * 0.55,
			"physical Zamboni overlap deals one hit and fades the body")
		await _wait(38)
		_check(not plant.is_death and plant.hp_component.curr_hp == health - tenth
			and plant.body.modulate.a < alpha * 0.55, "lingering overlap lasts without periodic crush damage")
		car.global_position.x += 400.0
		await _wait(40)
		_check(absf(plant.body.modulate.a - alpha) < 0.001 and not plant.is_processing(),
			"departed vehicle restores opacity and stops frame processing")
		car.global_position += hurt_area.global_position - shape.global_position
		await _wait(20)
		_check(plant.hp_component.curr_hp == health - 2 * tenth and plant.body.modulate.a < alpha * 0.55,
			"same vehicle can deal one fresh hit after physical separation")
	if is_instance_valid(car):
		car.retire_from_battle()
	await _retire([plant])

## 爆炸直击、斜邻格、同次多目标和即死炸弹都沿真实入口。
func _explosions() -> void:
	var iron: Plant000Base = _plant(Vector2i(1, 5), [0, 3, 5]) # 只启用爆炸保护。
	var side: Plant000Base = _plant(Vector2i(1, 4), [], CharacterRegistry.PlantType.P001PeaShooterSingle) # 同行邻格。
	var diagonal: Plant000Base = _plant(Vector2i(0, 6), [], CharacterRegistry.PlantType.P001PeaShooterSingle) # 斜邻格。
	var outside: Plant000Base = _plant(Vector2i(0, 3), [], CharacterRegistry.PlantType.P001PeaShooterSingle) # 超出一列。
	var attacker: Zombie000Base = _zombie(Vector2i(1, 8)) # 用活体攻击者观察同轮爆炸的反伤归属。
	if iron != null and side != null and diagonal != null and outside != null and attacker != null:
		var source: int = attacker.get_instance_id() # 爆炸保持原技能的多目标去重。
		CombatExplosion.resolve_targets([iron.hurt_box_component.hurt_box_real, side.hurt_box_component.hurt_box_real,
			diagonal.hurt_box_component.hurt_box_real, outside.hurt_box_component.hurt_box_real], source, 1, -1, false, 30)
		_check(iron.hp_component.curr_hp == iron.hp_component.max_hp - 60
			and side.hp_component.curr_hp == side.hp_component.max_hp and diagonal.hp_component.curr_hp == diagonal.hp_component.max_hp
			and outside.hp_component.curr_hp == outside.hp_component.max_hp - 30
			and attacker.hp_component.curr_hp == 4940, "iron absorbs and reflects each nearby blast packet")
		CombatExplosion.resolve_targets([iron.hurt_box_component.hurt_box_real, side.hurt_box_component.hurt_box_real],
			source, 1, -1, false, 0, true)
		_check(not iron.is_death and not side.is_death and iron.hp_component.curr_hp
			== iron.hp_component.max_hp - 60 - side.hp_component.max_hp, "lethal blast protection runs before removal")
	if is_instance_valid(attacker):
		attacker.retire_from_battle()
	await _retire([iron, side, diagonal, outside])

## 圣佑应覆盖统一状态入口与原生行动控制入口。
func _blessing() -> void:
	var plant: Plant000Base = _plant(Vector2i(5, 2), [0, 3, 4, 6]) # 四阶圣佑。
	if plant != null:
		var before: int = plant.hp_component.curr_hp # 冻结附伤不应从底层绕入。
		plant.be_ice_freeze(3.0, 3.0)
		plant.set_action_slowdown(get_instance_id(), 0.4)
		plant.hp_component.apply_degradation(0.25)
		AdventurePlantNullification.grant_stun(plant, 2.0)
		_check(not plant.can_receive_negative_effects() and not plant.is_cold_frozen()
			and is_equal_approx(plant.action_rate(), 1.0) and plant.hp_component.total_degradation_fraction() == 0.0
			and plant.process_mode != Node.PROCESS_MODE_DISABLED and plant.hp_component.curr_hp == before, "blessing rejects native debuffs")
		_check(not AdventurePlantNegativeEffects.apply(plant, AdventurePlantNegativeEffects.Kind.BURN, 0, 5.0),
			"blessing rejects timed damage status")
	await _retire([plant])

## 真实黑将军的受击窗口打开后，核对对 Boss 的反伤比例。
func _boss_reflect() -> void:
	var thorns: Plant000Base = _plant(Vector2i(5, 3), [0, 3]) # 荆棘血，无其他伤害倍率。
	var manager: ZombieManager = _game.zombie_manager # 正式僵王工厂。
	var point: Vector2 = _game.board.cell_at(Vector2i(5, 8)).get_spawn_global_position() # 同一关卡的合法脚点。
	var boss := manager.try_create_boss_from_card(CharacterRegistry.ZombieBossType.ZB002BlackGeneral,
		manager.zombie_boss_root.to_local(point)) as ZB002BlackGeneral # 实际阶段及减伤施加者。
	await _wait(4)
	if _check(is_instance_valid(boss) and thorns != null, "native boss exists"):
		boss.set_physics_process(false)
		boss.visual.player.pause()
		boss._set_invulnerable(false)
		var before: int = boss.hp_component.curr_hp # 启用原生受击窗口后的血量。
		var expected: int = boss.hp_component.resolve_damage(19) # 190 的一成仍经过 Boss 原有减伤。
		thorns.be_hit_from(190, boss, BulletRegistry.AttackMode.Norm)
		_check(expected > 0 and boss.hp_component.curr_hp == before - expected, "Boss takes ten percent thorns")
		before = boss.hp_component.curr_hp
		thorns.hp_component.curr_hp = 37
		expected = boss.hp_component.resolve_damage(3)
		thorns.be_hit_from(190, boss, BulletRegistry.AttackMode.Norm)
		_check(thorns.is_death and boss.hp_component.curr_hp == before - expected, "lethal hit reflects only consumed remaining life")
		boss.queue_free()
	await _retire([thorns])

## 密集重复命中一个真实棋盘；采样只覆盖同步生命结算时长。
func _stress() -> void:
	var fields: Array[Plant000Base] = [] # 全部真实占格，包含铁铠和普通目标。
	var targets: Array[Area2D] = [] # 同一范围攻击可命中这批真实受击区。
	for row: int in [0, 1, 4, 5]: # 四条陆路均种满可用的一段。
		for column: int in range(8): # 奇数列承接普通及爆炸伤害。
			var choices: Array[int] = [] # 偶数列使用未转职对照植物。
			if column % 2 == 1:
				choices.assign([0, 2, 5])
			var plant: Plant000Base = _plant(Vector2i(row, column), choices) # 每处都有真实生命与外观。
			if plant != null:
				fields.append(plant)
				targets.append(plant.hurt_box_component.hurt_box_real)
	var samples: PackedInt64Array = [] # 只保留本次测试的有限采样。
	for _step: int in range(120): # 每一逻辑帧结算一轮覆盖与一轮直击。
		var began: int = Time.get_ticks_usec() # 不计自然帧等待和场景加载。
		CombatExplosion.resolve_targets(targets, 0, -1, -1, false, 1)
		for plant: Plant000Base in fields: # 连续直击覆盖普通前后守护路径。
			plant.be_attacked_bullet(1, BulletRegistry.AttackMode.Norm, false, false)
		samples.append(Time.get_ticks_usec() - began)
		await get_tree().physics_frame
	samples.sort()
	_check(fields.size() == 32 and fields.all(func(plant: Plant000Base) -> bool: return is_instance_valid(plant) and not plant.is_death),
		"stress preserves the dense board")
	print("TALLNUT_STRESS plants=", fields.size(), " attacks=", fields.size() * 240, " p95_ms=", samples[113] / 1000.0)
	await _retire(fields)

## 在 [param address] 创建 [param species]，固定位置供受击观察。
func _zombie(address: Vector2i, species: CharacterRegistry.ZombieType = CharacterRegistry.ZombieType.Z001Norm) -> Zombie000Base:
	var cell: PlantCell = _game.board.cell_at(address) # 该格真实脚点。
	var manager: ZombieManager = _game.zombie_manager # 原生角色工厂。
	var zombie: Zombie000Base = manager.create_norm_zombie(species, manager.all_zombie_rows[address.x], {
		Zombie000Base.E_ZInitAttr.Lane: address.x,
		Zombie000Base.E_ZInitAttr.CurrZombieRowType: cell.get_spawn_terrain_type(),
		Zombie000Base.E_ZInitAttr.ParticipatesNaturalRefresh: false,
	}, cell.get_spawn_global_position())
	if _check(zombie != null, "native zombie exists"):
		zombie.move_component.update_move_factor(true, MoveComponent.E_MoveFactor.IsDisable)
		zombie.hp_component.set_spawn_max_health(5000)
	return zombie

## 撤掉 [param plants] 的原生占格。
func _retire(plants: Array[Plant000Base]) -> void:
	for plant: Plant000Base in plants: # 仅处理该测试生成的仍存活实例。
		if is_instance_valid(plant) and not plant.is_death:
			plant.be_shovel_kill()
	await _wait(4)

## 推进有限个 [param frames] 仿真步。
func _wait(frames: int) -> void:
	for _frame: int in range(frames): # 同步到真实游戏循环。
		await get_tree().physics_frame
