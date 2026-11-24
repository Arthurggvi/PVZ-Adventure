## 杨桃四阶经过正式图书馆、研究室和原生战斗入口的验收。
extends Node

## 杨桃的原生卡片编号。
const STAR := CharacterRegistry.PlantType.P030StarFruit
## 四阶按玩家可见顺序登记两个书目。
const BOOKS: Array[String] = ["promotion_starfruit_lurk", "promotion_starfruit_aim",
	"promotion_starfruit_stellar", "promotion_starfruit_pierce", "promotion_starfruit_comet",
	"promotion_starfruit_refract", "promotion_starfruit_celebrity", "promotion_starfruit_stream"]
## 正式的图书馆目录入口。
const Library = preload("res://scripts/adventure/library/library_rules.gd")
## 与生产齐射共用索敌的碰撞点定义。
const Aim = preload("res://scripts/adventure/research/starfruit_aim_index.gd")
## 直接从当前战场获取实际星弹运行时。
const Runtime = preload("res://scripts/adventure/research/starfruit_battle_runtime.gd")
## 共享画布的退场类型，用于核对物理弹的终端原因。
const StarVisual = preload("res://scripts/adventure/research/starfruit_visual.gd")
## 使用原屋顶斜面场景的真实受击层搭建一段实体测试面。
const TestSlope = preload("res://scenes/main_game_bg/slope.tscn")
## 当前隔离战场。
var game: MainGameManager
## 本轮测试失败计数。
var failures: int = 0

## 保留测试宿主跨越原生换场。
func _ready() -> void:
	get_tree().current_scene = null
	_run.call_deferred()

## 在测试档加载并验证正式卡牌。
func _run() -> void:
	if not check(OS.get_user_data_dir().contains("starfruit-promotion"), "isolated user directory"):
		get_tree().quit(2)
		return
	Global.save_service.stop_autosave()
	seed(30024)
	_catalog()
	_research()
	if await open_battle() and AdventurePromotionCatalog.BOOKS.has(BOOKS[0]):
		await _combat()
		await _lurk()
		await _contact_and_refraction()
		await _celebrity()
		await _projectile_exits()
		if OS.get_cmdline_user_args().has("--stress"):
			await _stress_aim()
	if is_instance_valid(game):
		game.queue_free()
		await wait_frames(5)
	print("STARFRUIT_RESULT=", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

## 报告 [param label] 对应的 [param valid]，保留其他独立检查。
func check(valid: bool, label: String) -> bool:
	if not valid:
		failures += 1
		printerr("STARFRUIT_FAIL ", label)
	return valid

## 本阶两件物品都可借书，流光在研究与存档同时要求二转贯穿。
func _catalog() -> void:
	for tier: int in range(4): # 物品与图书馆使用同一权威目录。
		var expected: Array[String] = BOOKS.slice(tier * 2, tier * 2 + 2) # 本阶书目。
		check(Library.pool(tier + 1, STAR) == expected, "library tier %d" % [tier + 1])
		for id: String in expected: # 每本书都可存入背包。
			check(ItemRegistry.has_item(id), "book " + id)
	check(AdventurePromotionCatalog.is_valid_chain(make_record([1, 3, 5, 7])), "pierce allows stream")
	check(not AdventurePromotionCatalog.is_valid_chain(make_record([1, 2, 5, 7])), "stellar disallows stream")
	check(AdventurePromotionCatalog.effects(make_record([1, 2, 5, 7])).events.is_empty(),
		"forged incompatible card has no promotion events")
	check(AdventurePromotionCatalog.options(make_record([0, 2, 4])).map(func(book: Dictionary): return book.id)
		== [BOOKS[6]], "research hides incompatible stream")

## 贯穿前置在正式研究报价及提交时均有效，并保留被拒时的书和金币。
func _research() -> void:
	var state := AdventureState.new() # 使用测试内存状态。
	AdventureQuestService.record_event(state, "stage_cleared", "zombie_island.lawn/normal", "2026-11-24")
	state.quests.records["first_expedition"].status = "claimed"
	var inventory := AdventureInventoryService.new(state) # 真实库存验证器。
	var wallet := GlobalGameState.new() # 不触碰玩家的存档钱包。
	wallet.adventure_state = state
	wallet.coin_value = AdventurePromotionCatalog.COST * 8
	var service := AdventureResearchService.new(state, inventory, wallet, func() -> bool: return true) # 事务只在隔离内存提交。
	var alt: String = inventory.add_card(STAR, 10) # 恒星路线用于核对拒绝。
	var legal: String = inventory.add_card(STAR, 10) # 贯穿路线用于正式支付。
	for key: String in BOOKS: # 资源充足仍不能越过前置。
		inventory.add_item(key, 2)
	for choice: int in [0, 2, 4]: # 前三转走恒星路线。
		check(service.execute("promotion", {"uid": alt, "book_id": BOOKS[choice]}).ok, "alternate branch transaction")
	var forbidden := {"uid": alt, "book_id": BOOKS[7]} # 模拟主动绕过界面选项。
	check(not service.quote("promotion", forbidden).ready and not service.execute("promotion", forbidden).ok \
		and wallet.coin_value == AdventurePromotionCatalog.COST * 5 and inventory.get_item_count(BOOKS[7]) == 2,
		"non-piercing fourth tier rolls back cleanly")
	for choice: int in [1, 3, 5, 7]: # 四个正式阶次消耗对应技能书。
		check(service.execute("promotion", {"uid": legal, "book_id": BOOKS[choice]}).ok, "legal transaction " + BOOKS[choice])
	check(wallet.coin_value == AdventurePromotionCatalog.COST and inventory.get_item_count(BOOKS[7]) == 1,
		"legal stream consumes exactly one book and one fee")
	wallet.free()

## 冻结 [param choices] 指定的真实十星卡。
func make_record(choices: Array[int]) -> PlantCardInstance:
	var card := PlantCardInstance.new() # 在本测试内四阶均可选择。
	card.uid = "PC000030"
	card.plant_type = STAR
	card.stars = 10
	for i: int in range(choices.size()): # 每项是当前阶的书目索引。
		card.set_promotion(i + 1, BOOKS[choices[i]])
	return card

## 使用原生后院棋盘和正式主游戏入口；关闭自然刷怪。
func open_battle() -> bool:
	var level: ResourceLevelData = load("res://resources/level_date_resource/mode_adventure/adventure_03_pool.tres").duplicate(true) # 测试不改正式关卡。
	level.look_show_zombie = false
	level.can_choosed_card = false
	level.monster_mode = ConstLevelData.E_MonsterMode.Null
	level.is_day_sun = false
	level.prechosen_cards = [ResourceCardReference.create(ResourceCardReference.CardType.Plant, STAR)]
	Global.game_para = level
	if not check(get_tree().change_scene_to_file("res://scenes/main/MainGame02Back.tscn") == OK, "native scene"):
		return false
	for _frame: int in range(420): # 有界等待实际进场。
		await get_tree().physics_frame
		game = Global.main_game
		if is_instance_valid(game) and game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME:
			return true
	return check(false, "native battlefield ready")

## 按 [param address] 和 [param choices] 使用正常占格事务种植。
func plant_at(address: Vector2i, choices: Array[int]) -> Plant030StarFruit:
	var cell: PlantCell = game.board.cell_at(address) # 权威棋格。
	var profile := PlantSpawnProfile.create(make_record(choices).to_dict(), AdventureResearchBattleEffects.new()) # 出战前按卡冻结。
	var plant := cell.create_plant(STAR, false, false, false, false, profile) as Plant030StarFruit # 真实出战对象。
	if check(plant != null, "place Starfruit"):
		plant.attack_component.detect_component.disable_component(ComponentNormBase.E_IsEnableFactor.Character)
	return plant

## 向 [param address] 生成真实 [param kind]，固定移动供精确检查。
func spawn(address: Vector2i, kind: CharacterRegistry.ZombieType = CharacterRegistry.ZombieType.Z001Norm) -> Zombie000Base:
	var cell: PlantCell = game.board.cell_at(address) # 原生脚点和地形。
	var manager: ZombieManager = game.zombie_manager # 复用普通僵尸工厂，不让自然波次提前结束。
	var zombie: Zombie000Base = manager.create_norm_zombie(kind, manager.all_zombie_rows[address.x], {
		Zombie000Base.E_ZInitAttr.Lane: address.x,
		Zombie000Base.E_ZInitAttr.CurrZombieRowType: cell.get_spawn_terrain_type(),
		Zombie000Base.E_ZInitAttr.ParticipatesNaturalRefresh: false,
	}, cell.get_spawn_global_position()) # 走正常入场。
	if check(zombie != null, "spawn enemy"):
		zombie.move_component.update_move_factor(true, MoveComponent.E_MoveFactor.IsDisable)
		zombie.hp_component.set_spawn_max_health(30000)
	return zombie

## 在正式棋盘核对普通一轮与额外星弹。
func _combat() -> void:
	var plant: Plant030StarFruit = plant_at(Vector2i(4, 3), [1, 2, 4]) # 瞄准、恒星及彗星均在同一株。
	if plant == null:
		return
	check(is_equal_approx(plant.influence_speed_factors[Character000Base.E_Influence_Speed_Factor.AdventurePromotionAttackRate], 1.4),
		"stellar and comet each grant 20% rate")
	plant.attack_component._shoot_bullet()
	var volley: Array[Bullet008Star] = projectiles() # 发射动画回调同步产生15个弹体。
	if check(volley.size() == 15, "one regular event fires five golden, five violet and five blue stars"):
		var target: Zombie000Base = spawn(Vector2i(0, 7)) # 紫蓝命中走真实攻击与状态门面。
		var before: float = target.global_position.x # 轻微击退向右。
		for index: int in range(0, 15, 3): # 同步出手的三色弹按三个一组。
			var gap: Vector2 = (volley[index].direction + volley[(index + 3) % 15].direction).normalized() # 原生方向夹角中线。
			check(volley[index].kind == Bullet008Star.Kind.GOLD and volley[index + 1].kind == Bullet008Star.Kind.VIOLET \
				and volley[index + 1].direction.is_equal_approx(gap) and volley[index + 2].kind == Bullet008Star.Kind.BLUE \
				and volley[index + 2].direction.is_equal_approx(volley[index].direction), "synchronized directions %d" % index)
		volley[1].attack_once(target)
		var timer: Timer = target.all_timer[Character000Base.E_TimerType.Stun] # 同一角色原有行动时钟。
		check(timer != null and is_equal_approx(timer.time_left, 0.2) and target.global_position.x > before, "purple stuns for 0.2s and nudges")
		volley[2].attack_once(target)
		var charge := target.get_node_or_null(^"AdventureFreezeChargeEffect") as AdventureFreezeChargeEffect # 读取正式冻结值。
		check(charge != null and charge._points == 2.0, "blue awards two freeze points")
		await _clear_projectiles()
		var ground: Node2D = Aim.aim_point(target) # 测试以真正碰撞点定位弹线。
		var air: Zombie000Base = spawn(Vector2i(1, 7), CharacterRegistry.ZombieType.Z017Balloon) # 更近但空中的干扰目标。
		var origin: Vector2 = ground.global_position + Vector2(-100, -120) # 初段不会提前与地面敌人相交。
		var sky_point: Node2D = Aim.aim_point(air) # 真实空中受击点，不是脚下的影子。
		air.global_position += origin + Vector2(102, -9) - sky_point.global_position
		var runtime := Runtime.for_battle(game) # 用同样的星弹构造和索引。
		var shot: RepeaterShotContext = RepeaterShotContext.from_plant(plant) # 保留卡牌增伤。
		var guided: Bullet008Star = runtime.launch(shot, origin, Vector2.RIGHT, Bullet008Star.Trait.AIM, Bullet008Star.Kind.GOLD) # 真实物理飞行。
		var base: Dictionary = AdventureResearchBattleEffects._stats(make_record([])) # 同星级无转职的基础成长。
		check(guided.attack_value == roundi(20.0 * AdventurePromotionCatalog.resolve_stat(1.0, base.damage) + 4.0),
			"aim receives the frozen attack growth and 20% damage")
		await wait_frames(11)
		check(is_instance_valid(guided) and guided._target == null and guided.direction == Vector2.RIGHT, "still straight before 0.2s")
		await wait_frames(2)
		check(is_instance_valid(guided) and guided._target == target and guided.direction.y > 0.0, "0.2s redirect skips nearer flying target")
		target.retire_from_battle()
		air.retire_from_battle()
	plant.character_death_disappear()
	await _clear_projectiles()

## 正常啃食和蹦极索敌跳过蛰伏，物理车头即使没有别的活植物仍会碾压。
func _lurk() -> void:
	var plant: Plant030StarFruit = plant_at(Vector2i(4, 3), [0]) # 原生子弹、仅带蛰伏词条。
	var zombie: Zombie000Base = spawn(Vector2i(4, 8)) # 暂停移动，只模拟检测盒的实际重叠。
	var car: Zombie000Base = spawn(Vector2i(4, 7), CharacterRegistry.ZombieType.Z013Zamboni) # 等普通啃食检验结束再驶近。
	if plant != null and zombie != null and car != null:
		var near := zombie.get_node(^"AttackComponent/DetectComponent/Area2d/CollisionShape2D") as CollisionShape2D # 近战检测盒。
		var front := car.get_node(^"AttackComponent/DetectComponent/Area2d/CollisionShape2D") as CollisionShape2D # 原生车头检测盒。
		var hurt := plant.hurt_box_component.get_node(^"HurtBoxDetection") as Area2D # 地面敌人在此体积内查询。
		var full: int = plant.hp_component.curr_hp # 与重叠前满血比较。
		check(is_equal_approx(plant.influence_speed_factors[Character000Base.E_Influence_Speed_Factor.AdventurePromotionAttackRate], 1.2),
			"lurk grants 20% rate")
		zombie.global_position += hurt.global_position - near.global_position
		await wait_frames(30)
		var detector := near.get_parent().get_parent() as DetectComponent # 读取真正的敌方索敌字段。
		check(detector.enemy_can_be_attacked == null and plant.hp_component.curr_hp == full \
			and plant.plant_cell.get_bungi_target() == null, "active bite and bungee ignore lurked starfruit")
		car.global_position += hurt.global_position - front.global_position
		await wait_frames(16)
		check(not is_instance_valid(plant) or plant.is_death, "vehicle still crushes a lone lurked starfruit")
	if is_instance_valid(plant) and not plant.is_death:
		plant.character_death_disappear()
	if is_instance_valid(zombie):
		zombie.retire_from_battle()
	if is_instance_valid(car):
		car.retire_from_battle()
	await wait_frames(4)

## 流光从真实重叠按逻辑钟采样，分开后停止；击倒被标记的目标只放出一圈。
func _contact_and_refraction() -> void:
	var plant: Plant030StarFruit = plant_at(Vector2i(4, 3), [0, 3, 5, 7]) # 贯穿、折射、流光整条合法路径。
	var target: Zombie000Base = spawn(Vector2i(0, 6)) # 无防具的实际敌人。
	if plant == null or target == null:
		return
	var runtime := Runtime.for_battle(game) # 战场共享时钟。
	var shot: RepeaterShotContext = RepeaterShotContext.from_plant(plant) # 最高阶倍率与原卡一致。
	var stats: Dictionary = AdventureResearchBattleEffects._stats(make_record([0, 3, 5])) # 去掉四转后读取同一正式属性聚合。
	var full: float = AdventurePromotionCatalog.resolve_stat(1.0, stats.damage) # 三转时的完整伤害倍率。
	var raw: int = target.hp_component.curr_hp # 与实际损失比较，检查每跳的减半伤害。
	var ticks: Array[int] = [] # 记录实际生命路由的攻击事件。
	target.hp_component.received_attack.connect(func(amount: int) -> void: ticks.append(amount))
	var point: Node2D = Aim.aim_point(target) # 使用同步后的物理受击框中心。
	var star: Bullet008Star = runtime.launch(shot, point.global_position, Vector2.RIGHT,
		plant._traits, Bullet008Star.Kind.GOLD) # 真实贯穿流光弹。
	star.speed = 0.0
	check(star.attack_value == shot.scaled_damage(20) and is_equal_approx(shot.damage_multiplier, full * 0.5),
		"stream final half damage applies after pierce and refraction modifiers")
	await wait_frames(10)
	var warm: int = ticks.size() # 碰撞注册前有一帧原生物理传播。
	await wait_frames(60)
	check(warm > 0 and ticks.size() - warm == 30 and target.hp_component.curr_hp < raw \
		and is_equal_approx(target.hp_component.degradation_fraction, 0.3), "actual overlapping projectile ticks exactly 30 Hz with 30% degradation")
	star.global_position += Vector2(0, -370)
	await wait_frames(5)
	var stopped: int = ticks.size() # 分离后不再被时钟重复采样。
	await wait_frames(12)
	check(ticks.size() == stopped and runtime._flow.is_empty(), "flow stops on separation")
	star.queue_free()
	# 外部伤害击倒同一目标，验证真实的先验标记和单次溅射。
	(target.hp_component as HpComponentZombie).apply_hit(100000, BulletRegistry.AttackMode.Real, true, false)
	await wait_frames(4)
	var bloom: Array[Bullet008Star] = projectiles() # 亡语星都保留普通贯穿和流光属性。
	check(bloom.size() == 10 and bloom.all(func(child: Bullet008Star) -> bool: return child._flow), "one marked death releases one ring of ordinary flow stars")
	plant.character_death_disappear()
	await _clear_projectiles()

## 明星只数普通齐射，定时落下一次，之后分两圈释放红星。
func _celebrity() -> void:
	var plant: Plant030StarFruit = plant_at(Vector2i(4, 3), [0, 2, 4, 6]) # 带有两种额外攻击检查递归。
	var first: Zombie000Base = spawn(Vector2i(0, 7)) # 初始随机候选都在同一格。
	var second: Zombie000Base = spawn(Vector2i(0, 7)) # 两只同时接受一次真实落点伤害。
	if plant == null or first == null or second == null:
		return
	var runtime := Runtime.for_battle(game) # 实际明星队列。
	var impacts: Array[int] = [] # 两个目标的600点坠落，额外弹另记伤害。
	first.hp_component.received_attack.connect(func(amount: int) -> void: impacts.append(amount))
	second.hp_component.received_attack.connect(func(amount: int) -> void: impacts.append(amount))
	var red: Array[int] = [] # 入树时记录真正发射，不依赖弹体是否已经命中。
	var track := func(child: Node) -> void: # 记录每颗红星的真实发射物理帧。
		if child is Bullet008Star and child.kind == Bullet008Star.Kind.RED:
			red.append(Engine.get_physics_frames())
	check(is_equal_approx(plant.influence_speed_factors[Character000Base.E_Influence_Speed_Factor.AdventurePromotionAttackRate], 1.8),
		"lurk, stellar, comet and celebrity combine their independent 20% bonuses")
	game.bullets.child_entered_tree.connect(track)
	for index: int in range(3): # 只有第三次正常出手触发。
		plant.attack_component._shoot_bullet()
		check(runtime._meteors.size() == int(index == 2), "meteor counts native volley %d" % index)
	var adjacent: Zombie000Base = spawn(Vector2i(0, 8)) # 在选中落点后加入相邻格。
	var nearby: Array[int] = [] # 红星可能命中邻格，但落点600不扩散。
	adjacent.hp_component.received_attack.connect(func(amount: int) -> void: nearby.append(amount))
	await wait_frames(32)
	check(not impacts.has(600) and red.is_empty(), "meteor telegraphs before landing")
	await wait_frames(7)
	check(impacts.count(600) == 2 and not nearby.has(600) and red.size() == 12, "one 600-damage landing and first red ring")
	await wait_frames(11)
	check(red.size() == 24 and red[-1] - red[0] >= 8, "second twelve-star ring launches distinctly")
	var red_stars: Array[Bullet008Star] = projectiles().filter(func(child: Bullet008Star) -> bool: return child.kind == Bullet008Star.Kind.RED) # 取一颗尚未命中的红星校对状态门面。
	if check(not red_stars.is_empty(), "still flying red stars"):
		var points_before: AdventureDetonationChargeEffect = adjacent.get_node_or_null(^"AdventureDetonationChargeEffect") # 累积值依真实命中而不同。
		var initial: float = points_before._points if points_before != null else 0.0 # 手动验证一步生命路由。
		red_stars[0].attack_once(adjacent)
		var charge: AdventureDetonationChargeEffect = adjacent.get_node_or_null(^"AdventureDetonationChargeEffect") # 原生引爆值。
		check(charge != null and charge._points == initial + 1.0, "red hit awards one detonation point")
	game.bullets.child_entered_tree.disconnect(track)
	for zombie: Zombie000Base in [first, second, adjacent]: # 测速前不保留此轮演员。
		zombie.retire_from_battle()
	plant.character_death_disappear()
	await _clear_projectiles()

## 96个活体实战目标、每批600次锁定。用全量基准校对空间索引并复用物理帧快照。
func _stress_aim() -> void:
	var targets: Array[Zombie000Base] = [] # 仅存本次创建的测试僵尸。
	for index: int in range(96): # 包含同格、相邻格和边缘重叠。
		var lane: int = [0, 1, 4, 5][index % 4] # 避免陆地敌人因水深变换状态。
		var target: Zombie000Base = spawn(Vector2i(lane, (index / 4) % 9)) # 使用真实战斗登记。
		target.global_position += Vector2(randi_range(-37, 37), randi_range(-20, 20))
		targets.append(target)
	await wait_frames(4)
	var indexer := Aim.new() # 与真实弹体使用同一索引模块。
	var samples: Array[float] = [] # 每批耗时，不混入基准比较与渲染。
	var origins := PackedVector2Array() # 随机点覆盖目标上下和盘外边缘。
	var excluded: Dictionary[int, bool] = {targets[0].get_instance_id(): true} # 模拟已穿过的敌人。
	for index: int in range(600): # 同一批弹的各自位置不同。
		origins.append(Vector2(randf_range(-350, 1400), randf_range(-200, 880)))
	for trial: int in range(16): # 16批统计批次耗时，逐物理步重新索引。
		await wait_frames(1)
		var start: int = Time.get_ticks_usec() # 只计构建和精确搜索。
		indexer.refresh(game)
		for origin: Vector2 in origins: # 模拟每个实际弹道的首次重定向。
			indexer.refresh(game)
			indexer.nearest(origin, excluded)
		samples.append((Time.get_ticks_usec() - start) / 1000.0)
	check(indexer.builds == 16, "600 same-frame locks share one index build per step")
	for origin: Vector2 in origins: # 逐点独立全表基准，含盘外和已命中目标。
		var best: float = INF # 当前参考距离平方。
		var expected: Zombie000Base # 真实最小欧氏距离者。
		for target: Zombie000Base in targets: # 真正的地面候选。
			if not Aim.ground_target(target) or excluded.has(target.get_instance_id()):
				continue
			var distance: float = origin.distance_squared_to(Aim.aim_point(target).global_position) # 与正式比较的参考坐标一致。
			if distance < best or (distance == best and target.get_instance_id() < expected.get_instance_id()):
				best = distance
				expected = target
		var match_index: int = indexer.nearest(origin, excluded) # 核对空间剪枝不跳过最佳桶。
		if not check(match_index >= 0 and indexer.target_at(match_index) == expected, "nearest matches full scan at %s" % origin):
			break
	samples.sort()
	print("STARFRUIT_STRESS targets=96 queries_per_step=600 batches=16 builds=", indexer.builds,
		" p95_ms=", "%.2f" % samples[ceili(samples.size() * 0.95) - 1])
	for target: Zombie000Base in targets: # 结束前保留原生退场流程。
		target.retire_from_battle()
	await wait_frames(4)

## 删除本阶段真正飞行的星弹，等待物理注册表消除旧重叠。
func _clear_projectiles() -> void:
	for star: Bullet008Star in projectiles(): # 不影响战场的其他节点。
		star.queue_free()
	await wait_frames(4)

## 检查真实命中、硬坡、射程以及跨战斗回收；演出与弹体分别验收。
func _projectile_exits() -> void:
	await wait_frames(25)
	var plant: Plant030StarFruit = plant_at(Vector2i(1, 4), []) # 原生分支也绑定同一份退场画布。
	var target: Zombie000Base = spawn(Vector2i(1, 6)) # 绝对位置由普通僵尸的真实碰撞区提供。
	if plant == null or target == null:
		return
	var runtime := Runtime.for_battle(game) # 使用正式发射入口。
	var visual: StarVisual = runtime._visual # 在战斗结束前只验证画布中的实际收据。
	var shot: RepeaterShotContext = RepeaterShotContext.from_plant(plant) # 无转职的基础伤害快照。
	var point: Vector2 = Aim.aim_point(target).global_position # 共享真实僵尸受击点。
	var before: int = target.hp_component.curr_hp # 命中前血量。
	var single: Bullet008Star = runtime.launch(shot, point - Vector2(52, 0), Vector2.RIGHT, 0, Bullet008Star.Kind.BLUE) # 真正命中一次。
	await wait_frames(13)
	var fragments: Array = _exit_sparks(visual, StarVisual.Effect.EXIT_HIT) # 命中亮片必须在弹回收后仍存在。
	check(not is_instance_valid(single) and fragments.size() == 1 and target.hp_component.curr_hp == before - shot.scaled_damage(20),
		"terminal hit emits one independent effect and applies one hit")
	target.retire_from_battle()
	var wall: Slope = make_exit_wall(point) # 实体坡段走原子弹世界层。
	var rel: Vector2 = Vector2(-56.0, 0.0) # 两枚星从坡面外向内飞行。
	var flow: Bullet008Star = runtime.launch(shot, point + rel, Vector2.RIGHT, Bullet008Star.Trait.PIERCE | Bullet008Star.Trait.STREAM, Bullet008Star.Kind.GOLD)
	var other: Bullet008Star = runtime.launch(shot, point + rel + Vector2(0, 17), Vector2.RIGHT, 0, Bullet008Star.Kind.VIOLET)
	await wait_frames(17)
	var walls: Array = _exit_sparks(visual, StarVisual.Effect.EXIT_TERRAIN) # 穿透与普通弹都验证一次，不叠加两段回收特效。
	check(not is_instance_valid(flow) and not is_instance_valid(other) and walls.size() == 2, "solid terrain ends flow and single stars exactly once")
	for spark: StarVisual.Spark in walls: # 法线朝来路，记录点必须贴合真实斜面。
		check(absf(spark.b.dot(visual.to_global(spark.point) - point)) < 0.1 and spark.b.x < -0.9,
			"solid-terrain exit is anchored at the native segment with its outward normal")
	wall.queue_free()
	plant.attack_component._shoot_bullet()
	var native: Bullet008Star = projectiles()[0] # 从杨桃原生攻击信号收到的金星。
	check(native._exit_visual == visual, "unpromoted native StarFruit reuses the canvas")
	native.max_distance = 31.0
	var expired: Bullet008Star = runtime.launch(shot, point - Vector2(40, 45), Vector2.RIGHT, 0, Bullet008Star.Kind.RED, null, 31.0) # 红色星环使用同样的有限射程入口。
	var distant: Bullet008Star = runtime.launch(shot, point + Vector2(3200, 0), Vector2.RIGHT, 0, Bullet008Star.Kind.VIOLET, null, 31.0) # 远离镜头的弹同样准时销毁。
	var stale: Bullet008Star = runtime.launch(shot, point + Vector2(0, 55), Vector2.RIGHT, 0, Bullet008Star.Kind.GOLD, null, 1.0) # 旧批次失效走战场门禁。
	stale.attack_validity = func() -> bool: return false
	await wait_frames(10)
	var ranges: Array = _exit_sparks(visual, StarVisual.Effect.EXIT_RANGE) # 只有镜头附近两颗留下淡出。
	check(not is_instance_valid(native) and not is_instance_valid(expired) and not is_instance_valid(distant) \
		and not is_instance_valid(stale) and ranges.size() == 2, "only visible active stars emit an expiry fade")
	await _clear_projectiles()
	await wait_frames(29)
	check(visual._sparks.is_empty() and not visual.is_processing(), "shared canvas becomes idle after exit visuals")
	plant.character_death_disappear()

## 从 [param visual] 只取当前仍在表现的 [param effect]。
func _exit_sparks(visual: StarVisual, effect: StarVisual.Effect) -> Array:
	return visual._sparks.filter(func(spark: StarVisual.Spark) -> bool: return spark.kind == effect)

## 用原生斜面在世界点 [param center] 搭建单段碰撞供测试和录像。
func make_exit_wall(center: Vector2) -> Slope:
	var wall := TestSlope.instantiate() as Slope # 保留世界碰撞层和所有者协议。
	var detector := wall.get_node(^"Area2DSlopeDetection") as Area2D # 无需更改本关僵尸的走路斜率。
	detector.monitoring = false
	var surface := wall.get_node(^"SlopeReal/Area2DReal") as Area2D # 只保留一个演示受击区。
	surface.position = Vector2.ZERO
	var shape := SegmentShape2D.new() # 法线朝来路，保留清晰可见的斜面。
	shape.a = Vector2(-21, 94)
	shape.b = Vector2(21, -94)
	(surface.get_node(^"CollisionShape2D") as CollisionShape2D).shape = shape
	for other: Area2D in surface.get_parent().get_children(): # 本段外的面积不会产生重复碰撞。
		if other != surface:
			other.collision_layer = 0
	wall.solid_for_projectiles = true
	game.add_child(wall)
	wall.global_position = center
	return wall

## 返回当前仍在移动的实际杨桃子弹。
func projectiles() -> Array[Bullet008Star]:
	var result: Array[Bullet008Star] = [] # 只计星弹，不计其他世界效果。
	for node: Node in game.bullets.get_children(): # 来自原生弹体容器。
		if node is Bullet008Star and not node.is_queued_for_deletion():
			result.append(node)
	return result

## 等待 [param frames] 帧战斗步。
func wait_frames(frames: int) -> void:
	for _frame: int in range(frames): # 测试与正式物理与碰撞同步。
		await get_tree().physics_frame
