## 玉米投手技能书的真实目录、原生战斗及密集空袭验收。
extends "res://tests/adventure/test_starfruit_promotions.gd"

## 图书馆和冻结卡使用同一个投手编号。
const CORN := CharacterRegistry.PlantType.P035CornPult
## 按四阶每阶两项排序的正式编号。
const CORN_BOOKS: Array[String] = ["promotion_corn_popcap", "promotion_corn_slippery",
	"promotion_corn_airraid", "promotion_corn_butter_day", "promotion_corn_poison",
	"promotion_corn_gambler", "promotion_corn_green", "promotion_corn_genetic"]
## 生产战场调度器及三种命中入口。
const CornBattle = preload("res://scripts/adventure/research/corn_battle.gd")
## 用于校对每个目标的周期和滤镜。
const CornPoison = preload("res://scripts/adventure/research/corn_poison.gd")

## 不依赖正式玩家存档。
func _run() -> void:
	if not check(OS.get_user_data_dir().contains("corn-promotion"), "isolated data"):
		get_tree().quit(2)
		return
	Global.save_service.stop_autosave()
	for tier: int in range(4): # 各阶正式图书馆书目。
		check(Library.pool(tier + 1, CORN) == CORN_BOOKS.slice(tier * 2, tier * 2 + 2), "corn tier %d" % (tier + 1))
	for id: String in CORN_BOOKS: # 书能实际入库。
		check(ItemRegistry.has_item(id), "corn inventory " + id)
	_research_corn()
	if await open_battle():
		await _green_air()
		await _butter_and_gambler()
		await _native_fast_throw()
		if OS.get_cmdline_user_args().has("--stress"):
			await _stress_corn()
	if is_instance_valid(game):
		game.queue_free()
		await wait_frames(5)
	print("CORN_RESULT=", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

## 走已有研究室付费和入库入口。
func _research_corn() -> void:
	var state := AdventureState.new() # 独立内存档。
	AdventureQuestService.record_event(state, "stage_cleared", "zombie_island.lawn/normal", "2026-11-24")
	state.quests.records["first_expedition"].status = "claimed"
	var inventory := AdventureInventoryService.new(state) # 背包权威服务。
	var wallet := GlobalGameState.new() # 不连接用户钱包。
	wallet.adventure_state = state
	wallet.coin_value = 4 * AdventurePromotionCatalog.COST
	var service := AdventureResearchService.new(state, inventory, wallet, func() -> bool: return true) # 在内存保存。
	var uid: String = inventory.add_card(CORN, 10) # 四阶完整路线。
	for option: int in [0, 2, 4, 6]: # 每步消费当前实际书籍。
		var id: String = CORN_BOOKS[option] # 当前阶 ID。
		inventory.add_item(id, 1)
		check(service.execute("promotion", {"uid": uid, "book_id": id}).ok and inventory.get_item_count(id) == 0,
			"correct research for " + id)
	check(wallet.coin_value == 0 and AdventurePromotionCatalog.is_valid_chain(state.cards[uid]), "four correct research payments")
	wallet.free()

## 按 [param address] 实际种植由 [param choices] 冻结的正式卡。
func corn_at(address: Vector2i, choices: Array[int]) -> Plant035CornPult:
	var card := PlantCardInstance.new() # 创建实战卡快照。
	card.uid = "PC000035"
	card.plant_type = CORN
	card.stars = 10
	for index: int in range(choices.size()): # 每个下标代表这一阶的正式选择。
		card.set_promotion(index + 1, CORN_BOOKS[choices[index]])
	var profile := PlantSpawnProfile.create(card.to_dict(), AdventureResearchBattleEffects.new()) # 应用数值与转职事件。
	var plant := game.board.cell_at(address).create_plant(CORN, false, false, false, false, profile) as Plant035CornPult # 正常占位。
	if check(is_instance_valid(plant), "create corn on live board"):
		plant.attack_component.disable_component(ComponentNormBase.E_IsEnableFactor.Character)
	return plant

## 从 [param plant] 的真正离手入口向 [param target] 发起 [param butter] 指示的这一次原生投掷。
func fire_corn(plant: Plant035CornPult, target: Character000Base, butter: bool) -> void:
	plant.attack_component.attack_bullet_type = BulletRegistry.BulletType.Bullet011Butter if butter else BulletRegistry.BulletType.Bullet010Corn
	plant.attack_component.last_target_enemy = target
	plant.attack_component.last_target_enemy_global_pos = target.hurt_box_component.global_position
	plant.attack_component._aimed_lane = target.lane if target.lane >= 0 else plant.lane
	plant.attack_component._shoot_bullet()

## 移除本段余弹，供下一段隔离验证。
func clear_corn(runtime: Node) -> void:
	runtime._heap.clear()
	runtime._work.clear()
	runtime._head = 0
	runtime._visual._flights.clear()
	runtime._visual._bursts.clear()
	runtime._visual.queue_redraw()
	runtime.set_physics_process(false)

## PopCap+绿色食品共七枚，空袭每枚六跳，真实邻格与毒层分别验证。
func _green_air() -> void:
	seed(325)
	var plant: Plant035CornPult = corn_at(Vector2i(4, 2), [0, 2, 4, 6]) # 帽子、七粒与中毒叠加。
	var primary: Zombie000Base = spawn(Vector2i(4, 5)) # 单次空袭中心。
	var near: Zombie000Base = spawn(Vector2i(5, 6)) # 3×3的实际斜对角。
	var far: Zombie000Base = spawn(Vector2i(4, 7)) # 离中心两列，不参与这一场雨。
	await wait_frames(4)
	var runtime: Node = CornBattle.for_battle(game) # 读取完整弹幕而非只看可见粒子。
	check(is_instance_valid(plant._popcap_hat) and plant._popcap_hat.get_parent().name == &"Anim_face",
		"transparent hat is mounted to the animated head")
	if is_instance_valid(plant._popcap_hat):
		check((plant._popcap_hat.texture as AtlasTexture).atlas.get_width() <= 384, "hat limits imported texture size, with full-resolution source retained")
	check(plant.attack_component.p_butter == 0.0, "green removes butter from the animation lottery")
	fire_corn(plant, primary, true)
	var shot: RepeaterShotContext = RepeaterShotContext.from_plant(plant) # 这张卡固定的原生伤害倍率。
	check(runtime._heap.size() == 7 and runtime._heap.all(func(item: CornBattle.Drop) -> bool:
		return item.kind == CornBattle.Kind.RAID and item.damage == shot.scaled_damage(40) and item.poison),
		"green and PopCap produce seven strengthened air strikes and no butter")
	var lock_set: Dictionary[int, bool] = {} # 数量足够时应该尽量锁不同活敌。
	for item: CornBattle.Drop in runtime._heap: # 读取实际锁定资格。
		if is_instance_valid(item.target):
			lock_set[item.target.get_instance_id()] = true
	check(lock_set.size() == 3, "extra locks sample all available enemies before reusing a target")
	clear_corn(runtime)
	await wait_frames(2)
	runtime.raid_locks(1)
	var lock: int = runtime._raid_targets.find(primary) # 从真实候选中定位验证对象。
	var point: Vector2 = primary.hurt_box_component.global_position # 保持与实际离手调用相同的参数。
	var origin: Vector2 = plant.attack_component.markers_2d_bullet[0].global_position # 原生动画弹口。
	runtime.launch(shot, CornBattle.Kind.RAID, primary, origin, point, primary.lane, 0.0, 25, true, false, 0.0, lock)
	await wait_frames(87)
	var poison := primary.get_node_or_null(^"CornPoison") as CornPoison # 只为该目标创建一个节拍。
	check(primary.hp_component.curr_hp == 30000 - 6 * 25 and near.hp_component.curr_hp == 30000 - 6 * 25 \
		and far.hp_component.curr_hp == 30000, "one lock deals exactly six 3x3 kernel hits")
	check(poison != null and poison.stacks == 6 and primary.body.change_color.has(BodyCharacter.E_ChangeColors.CornPoison),
		"all six impacts stack one-percent poison and tint the target violet")
	plant.character_death_disappear()
	await wait_frames(23)
	check(primary.hp_component.curr_hp == 30000 - 6 * 25 - 1800, "poison ticks for six percent after the source leaves")
	for target: Zombie000Base in [primary, near, far]: # 下一段使用相同棋盘但独立演员。
		target.retire_from_battle()
	clear_corn(runtime)
	await wait_frames(4)

## 裂行索敌、赌徒、额外黄油和玉米炮走同一击发节点并核对各自的范围。
func _butter_and_gambler() -> void:
	var plant: Plant035CornPult = corn_at(Vector2i(0, 2), [0, 3, 5, 7]) # 有五次赌徒粒弹与范围黄油。
	var target: Zombie000Base = spawn(Vector2i(1, 5)) # 原行没有敌人。
	var side: Zombie000Base = spawn(Vector2i(0, 6)) # 三行与3×3的邻格目标。
	var outside: Zombie000Base = spawn(Vector2i(4, 5)) # 两种效果都不能越出范围。
	side.global_position.x = plant.global_position.x - 145.0
	await wait_frames(4)
	check(plant._three_lane_target() == target, "butter-day automatically reaches the adjacent lane")
	var runtime: Node = CornBattle.for_battle(game) # 实战单例。
	var started: int = runtime._serial # 真正的原生时钟必须能在空本行启动。
	var appearances: Array[Character000Base] = [] # 不使用手动离手判断自动索敌。
	plant.attack_component.signal_shoot_bullet.connect(func() -> void: appearances.append(plant.attack_component.last_target_enemy))
	plant.attack_component.enable_component(ComponentNormBase.E_IsEnableFactor.Character)
	for _frame: int in range(138): # 最多等待一轮原生动画。
		await wait_frames(1)
		if runtime._serial > started:
			break
	plant.attack_component.disable_component(ComponentNormBase.E_IsEnableFactor.Character)
	check(runtime._serial > started and appearances.size() == 1 and appearances[0] == target, "native cooldown actually fires at the adjacent lane")
	clear_corn(runtime)
	await wait_frames(64)
	plant.gambler_stacks = 0
	plant.update_speed_factor(plant._fixed_attack_rate, Character000Base.E_Influence_Speed_Factor.AdventurePromotionAttackRate)
	side.global_position = game.board.cell_at(Vector2i(0, 6)).get_spawn_global_position()
	var shot: RepeaterShotContext = RepeaterShotContext.from_plant(plant) # 所有派生值按原卡。
	fire_corn(plant, target, false)
	var events: Array[CornBattle.Drop] = runtime._heap.duplicate() # 记录出手顺序与成长基数。
	events.sort_custom(func(a: CornBattle.Drop, b: CornBattle.Drop) -> bool: return a.serial < b.serial)
	check(events.size() == 5 and events[0].damage == shot.scaled_damage(30) \
		and events[4].damage == shot.scaled_damage(78) and plant.gambler_stacks == 5 \
		and is_equal_approx(plant.influence_speed_factors[Character000Base.E_Influence_Speed_Factor.AdventurePromotionAttackRate],
			plant._fixed_attack_rate + 2.0), "each non-butter kernel boosts subsequent damage and attack rate by 40 percent")
	clear_corn(runtime)
	seed(_seed_for_butter(false))
	fire_corn(plant, target, true)
	var butter: CornBattle.Drop = runtime._heap[0] # 一次普通主投。
	check(butter.kind == CornBattle.Kind.BUTTER and butter.butter_seconds == 5.5 and butter.damage == shot.scaled_damage(120) \
		and plant.gambler_stacks == 0, "butter gets existing damage, resets the stacks and lasts 5.5 seconds")
	await wait_frames(86)
	check(target.all_timer[Character000Base.E_TimerType.Butter] != null and side.all_timer[Character000Base.E_TimerType.Butter] != null \
		and outside.all_timer[Character000Base.E_TimerType.Butter] == null and side.hp_component.curr_hp == 30000,
		"butter-day pins the whole 3x3 without splash damage")
	var before: int = target.hp_component.curr_hp # 爆炸前剩余生命。
	seed(_seed_for_butter(true))
	fire_corn(plant, target, true)
	check(runtime._heap.size() == 1 and runtime._heap[0].kind == CornBattle.Kind.COB and runtime._heap[0].damage == 1200,
		"butter independently converts to a fixed 1200 cob")
	await wait_frames(61)
	check(target.hp_component.curr_hp == before - 1200 and side.hp_component.curr_hp == 30000 - 1200 \
		and outside.hp_component.curr_hp == 30000, "cob explosion lands once within the 3x3")
	plant.character_death_disappear()
	var slippery: Plant035CornPult = corn_at(Vector2i(1, 2), [1]) # 只有一转小心地滑，方便测试额外概率。
	seed(_seed_for_butter(true))
	fire_corn(slippery, target, true)
	check(runtime._heap.size() == 2 and runtime._heap.all(func(item: CornBattle.Drop) -> bool:
		return item.kind == CornBattle.Kind.BUTTER), "slippery can add butter even to a native butter throw")
	clear_corn(runtime)
	var green: Plant035CornPult = corn_at(Vector2i(1, 3), [1, 3, 5, 6]) # 绿色食品屏蔽小心地滑。
	seed(_seed_for_butter(true))
	fire_corn(green, target, true)
	check(runtime._heap.size() == 3 and runtime._heap.all(func(item: CornBattle.Drop) -> bool:
		return item.kind == CornBattle.Kind.KERNEL), "green also suppresses slippery extra butter")
	for zombie: Zombie000Base in [target, side, outside]: # 清理临时实战角色。
		zombie.retire_from_battle()
	green.character_death_disappear()
	slippery.character_death_disappear()
	clear_corn(runtime)
	await wait_frames(4)

## 高赌徒层数下真实动画仍须出现装填、甩篮和回收，并且离手贴住当帧弹篮。
func _native_fast_throw() -> void:
	var plant: Plant035CornPult = corn_at(Vector2i(4, 3), [0, 2, 5, 6]) # 绿色食品允许赌徒长期累积。
	var target: Zombie000Base = spawn(Vector2i(4, 6)) # 真实探测范围内唯一目标。
	target.hp_component.set_spawn_max_health(100000000)
	var component: AttackComponentBulletCorn = plant.attack_component # 只让正常攻击时钟驱动动画。
	var runtime: Node = CornBattle.for_battle(game) # 用于验证视觉和实际投掷同帧衔接。
	var basket := plant.get_node(^"Body/BodyCorrect/Cabbagepult_basket") as Sprite2D # 原生甩篮位置与角度曲线。
	var kernel := plant.get_node(^"Body/BodyCorrect/Cornpult_kernal") as Sprite2D # 原生装填粒的精确边界。
	plant.gambler_stacks = 120
	plant.update_speed_factor(plant._fixed_attack_rate + 48.0, Character000Base.E_Influence_Speed_Factor.AdventurePromotionAttackRate)
	var motion_frames: int = 0 # 在真正离手前出现的拉篮画面。
	var recovery_frames: int = 0 # 离手后清晰可见的甩臂余势。
	var first_release: int = -1 # 读取正式离手事件。
	var origin_error: float = INF # 确认画布接手了手里的玉米粒。
	var marker: Array[int] = [] # 收到第一次 native shoot 之前不得向前发射。
	var cooling: Array[int] = [0] # 记录真正的原生冷却次数，与动画批次分开验算。
	component.bullet_attack_cd_timer.timeout.connect(func() -> void: cooling[0] += 1)
	component.signal_shoot_bullet.connect(func() -> void: marker.append(Engine.get_process_frames()))
	component.enable_component(ComponentNormBase.E_IsEnableFactor.Character)
	for _frame: int in range(168): # 足以观察第一轮真实装填、摆臂和回收。
		await get_tree().process_frame
		if first_release < 0:
			if marker.is_empty():
				if basket.rotation < -0.47:
					motion_frames += 1
			else:
				first_release = marker[0]
				if not runtime._visual._flights.is_empty():
					var flight: CornBattle.Visual.Flight = runtime._visual._flights[0] # 同一张画布接收真实发射起点。
					origin_error = flight.start.distance_to(kernel.to_global(kernel.get_rect().get_center()))
		elif Engine.get_process_frames() - first_release < 28 and basket.rotation > 0.88:
			recovery_frames += 1
		if first_release >= 0 and Engine.get_process_frames() - first_release >= 28:
			break
	check(first_release >= 0 and motion_frames >= 4 and recovery_frames >= 7 and origin_error < 8.0,
		"native throw has readable load, recovery and basket origin (pre=%d post=%d origin=%.2f)" \
			% [motion_frames, recovery_frames, origin_error])
	for _frame: int in range(108): # 观察下一轮收势是否能顺利进入装填。
		await get_tree().process_frame
		if not marker.is_empty() and marker[-1] != first_release:
			break
	var reserved: int = int(component._swing_active and not component._released) # 当前已装填的一轮尚未消费。
	check(marker.count(first_release) >= 2 and not marker.is_empty() and marker[-1] - first_release >= 20
		and marker.size() + component._ready_volleys + reserved == cooling[0],
		"high-rate volleys are retained across full native swings (requested=%d, fired=%d, pending=%d)" \
			% [cooling[0], marker.size(), component._ready_volleys + reserved])
	for _frame: int in range(95): # 等到真正的下一轮拉篮，准备在中间冻结。
		await get_tree().process_frame
		if component._swing_active and not component._released and basket.rotation < -0.43:
			break
	var paused_pose: float = basket.rotation # 零速期间原生动画停在同一姿态。
	var frozen_count: int = marker.size() # 等待证实冻结期间不迟到发射。
	check(component._swing_active and not component._released, "third swing is still loading before freeze")
	plant.update_speed_factor(0.0, Character000Base.E_Influence_Speed_Factor.IceFreezeSpeed)
	await wait_frames(14)
	check(is_equal_approx(basket.rotation, paused_pose) and marker.size() == frozen_count, "freezing pauses the loaded basket")
	plant.update_speed_factor(1.0, Character000Base.E_Influence_Speed_Factor.IceFreezeSpeed)
	for _frame: int in range(60): # 原手势恢复后只到达一次真实离手。
		await get_tree().process_frame
		if marker.size() > frozen_count:
			break
	check(marker.size() > frozen_count, "the same loaded swing resumes after thaw")
	component.disable_component(ComponentNormBase.E_IsEnableFactor.Character)
	clear_corn(runtime)
	target.retire_from_battle()
	plant.character_death_disappear()
	await wait_frames(4)

## 选择原生全局随机下一次是否落在 [param proc] 的30%区间。
func _seed_for_butter(proc: bool) -> int:
	for value: int in range(256): # 固定范围内两种结果都存在。
		seed(value)
		if (randf() < 0.30) == proc:
			return value
	return 0

## 用96个真实僵尸和96次独立锁定检验所有576个落雨的消化及显示上限。
func _stress_corn() -> void:
	var plant: Plant035CornPult = corn_at(Vector2i(4, 2), [0, 2, 4, 6]) # 真正的物理战局。
	var targets: Array[Zombie000Base] = [] # 全部选在两个陆行的同一3×3。
	for index: int in range(96): # 重复同格也是真实角色。
		var zombie: Zombie000Base = spawn(Vector2i(4 + index % 2, 4 + (index / 2) % 3)) # 六个不同格。
		zombie.hp_component.set_spawn_max_health(100000)
		targets.append(zombie)
	await wait_frames(5)
	var runtime: Node = CornBattle.for_battle(game) # 使用正式时钟和队列。
	var shot: RepeaterShotContext = RepeaterShotContext.from_plant(plant) # 工作量不依赖角色伤害增长。
	var lock: int = -1 # 让所有空袭共享同一真实覆盖中心。
	runtime.raid_locks(1)
	for index: int in range(runtime._raid_cells.size()): # 在对应行中央选择最密落点。
		if runtime._raid_cells[index].row_col == Vector2i(4, 5):
			lock = index
			break
	if not check(lock >= 0, "stress center lock"):
		return
	var target: Zombie000Base = runtime._raid_targets[lock] # 实际锁定者不会走动。
	var point: Vector2 = target.hurt_box_component.global_position # 原生受击中心。
	for _index: int in range(96): # 同帧最多96次飞行。
		runtime.launch(shot, CornBattle.Kind.RAID, target, plant.global_position, point, target.lane, 0.0, 20, false, false, 0.0, lock)
	check(runtime._heap.size() == 96 and runtime._visual._flights.size() <= 96 and runtime.get_child_count() == 1,
		"no per-projectile nodes or timers")
	var peak: float = 0.0 # 观察最重一帧的事件和受击逻辑。
	var frames: int = 0 # 有界等到最后一个落地工作完成。
	runtime.set_physics_process(false)
	while (not runtime._heap.is_empty() or not runtime._work.is_empty()) and frames < 750:
		var start: int = Time.get_ticks_usec() # 单独统计共享运行时。
		runtime._physics_process(1.0 / 60.0)
		peak = maxf(peak, (Time.get_ticks_usec() - start) / 1000.0)
		runtime.set_physics_process(false)
		frames += 1
		await wait_frames(1)
	check(runtime._heap.is_empty() and runtime._work.is_empty() \
		and targets[-1].hp_component.curr_hp == 100000 - 96 * 6 * 20, "all six pulses per lock survive overload and preserve actual damage")
	print("CORN_STRESS locks=96 targets=96 processed_frames=", frames, " max_step_ms=", "%.2f" % peak)
	for zombie: Zombie000Base in targets: # 不保留任何验收档演员。
		zombie.retire_from_battle()
	plant.character_death_disappear()
	clear_corn(runtime)
	await wait_frames(4)
