## 卷心菜投手的正式图书馆、卡片和战场路径。
extends "res://tests/adventure/test_starfruit_promotions.gd"

## 卷心菜的原生卡片编号。
const CABBAGE := CharacterRegistry.PlantType.P033CabbagePult
## 稳定书目按转职次序排列。
const CABBAGE_BOOKS: Array[String] = ["promotion_cabbage_gold", "promotion_cabbage_triple",
	"promotion_cabbage_hell", "promotion_cabbage_split", "promotion_cabbage_homerun",
	"promotion_cabbage_again", "promotion_cabbage_black", "promotion_cabbage_two_hundred"]
## 从正式落点解释各特殊颜色。
const CabbageLanding = preload("res://scripts/adventure/research/cabbage_landing.gd")
## 实际抛物线场景的脚本类型。
const CabbageBall = preload("res://scripts/bullet/bullet_009_cabbage.gd")

## 走隔离正式棋盘，测试各阶书目和实际线程。
func _run() -> void:
	if not check(OS.get_user_data_dir().contains("cabbage-promotion"), "isolated data"):
		get_tree().quit(2)
		return
	Global.save_service.stop_autosave()
	for tier: int in range(4): # 每阶两个可借书目。
		check(Library.pool(tier + 1, CABBAGE) == CABBAGE_BOOKS.slice(tier * 2, tier * 2 + 2),
			"cabbage books available in tier %d" % (tier + 1))
		for index: int in range(tier * 2, tier * 2 + 2): # 背包和图书馆使用相同 ID。
			check(ItemRegistry.has_item(CABBAGE_BOOKS[index]), "registered " + CABBAGE_BOOKS[index])
	_research_cabbage()
	if await open_battle():
		await _volleys()
		await _damage()
		await _boss()
		if OS.get_cmdline_user_args().has("--stress"):
			await _stress_landings()
	if is_instance_valid(game):
		game.queue_free()
		await wait_frames(5)
	print("CABBAGE_RESULT=", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

## 使用真正的研究服务执行四转，验证书、金币、星级门槛共用原事务。
func _research_cabbage() -> void:
	var state := AdventureState.new() # 独立内存状态。
	AdventureQuestService.record_event(state, "stage_cleared", "zombie_island.lawn/normal", "2026-11-24")
	state.quests.records["first_expedition"].status = "claimed"
	var inventory := AdventureInventoryService.new(state) # 物品只使用正式库存接口。
	var wallet := GlobalGameState.new() # 测试钱包不连接实际存档。
	wallet.adventure_state = state
	wallet.coin_value = AdventurePromotionCatalog.COST * 4
	var service := AdventureResearchService.new(state, inventory, wallet, func() -> bool: return true) # 成功在内存中保存。
	var uid: String = inventory.add_card(CABBAGE, 10) # 完整路线的十星卡。
	for choice: int in [0, 2, 4, 7]: # 各阶真实消费一次。
		var key: String = CABBAGE_BOOKS[choice] # 当前书目。
		inventory.add_item(key, 1)
		check(service.execute("promotion", {"uid": uid, "book_id": key}).ok and inventory.get_item_count(key) == 0,
			"official research and consumption for " + key)
	check(wallet.coin_value == 0 and AdventurePromotionCatalog.is_valid_chain(state.cards[uid]), "four fees and a valid saved route")
	wallet.free()

## [param choices] 按一至四阶应用到真实占格 [param address]。
func _plant_cabbage(address: Vector2i, choices: Array[int]) -> Plant033CabbagePult:
	var card := PlantCardInstance.new() # 与出战事务的冻结格式一致。
	card.uid = "PC000033"
	card.plant_type = CABBAGE
	card.stars = 10
	for index: int in range(choices.size()): # 每个输入都是权威书目下标。
		card.set_promotion(index + 1, CABBAGE_BOOKS[choices[index]])
	var cell: PlantCell = game.board.cell_at(address) # 正式占位的对应格。
	var profile := PlantSpawnProfile.create(card.to_dict(), AdventureResearchBattleEffects.new()) # 实际数值和事件在入树前应用。
	var plant := cell.create_plant(CABBAGE, false, false, false, false, profile) as Plant033CabbagePult # 原生实例。
	if check(plant != null, "place cabbage"):
		plant.attack_component.disable_component(ComponentNormBase.E_IsEnableFactor.Character)
	return plant

## 从真实动画离手验证裂叶选敌，再压排程的概率、去重和数量上限。
func _volleys() -> void:
	var plant: Plant033CabbagePult = _plant_cabbage(Vector2i(0, 2), [1, 3, 5, 6]) # 三连投、裂叶、再来可叠加。
	var primary: Zombie000Base = spawn(Vector2i(1, 3)) # 卷心菜本行空，邻行能够主动开火。
	var extras: Array[Zombie000Base] = [] # 只用实际相邻行的额外目标。
	for index: int in range(6): # 多于五个的敌人也不能突破每轮上限。
		extras.append(spawn(Vector2i(1, 4 + index % 4)))
	var distant: Zombie000Base = spawn(Vector2i(4, 4)) # 物理最靠前也不允许隔行锁定。
	await wait_frames(5)
	check(plant._choose_split_primary() == primary, "empty native lane can find adjacent primary")
	check(is_equal_approx(plant.influence_speed_factors[Character000Base.E_Influence_Speed_Factor.AdventurePromotionAttackRate], 1.9),
		"triple split again and black attack-rate modifiers")
	var native_attacks: Array[int] = [] # 每轮普通动画事件与其余派生发数分开计。
	var launched_rows: Array[int] = [] # 捕获实际离手，避免快弹已经命中造成漏数。
	var observe := func(child: Node) -> void: # 入树时目标行已经初始化。
		if child is CabbageBall:
			launched_rows.append(child.lane)
	game.bullets.child_entered_tree.connect(observe)
	plant.attack_component.signal_shoot_bullet.connect(func() -> void: native_attacks.append(Engine.get_physics_frames()))
	plant.attack_component.enable_component(ComponentNormBase.E_IsEnableFactor.Character)
	for _frame: int in range(150): # 只等待自动开火后产生的第一轮原生动画。
		await wait_frames(1)
		if not native_attacks.is_empty():
			break
	plant.attack_component.disable_component(ComponentNormBase.E_IsEnableFactor.Character)
	await wait_frames(30)
	check(native_attacks.size() == 1 and launched_rows.size() >= 2,
		"native animation emitted %d attack events and %d physical throws" % [native_attacks.size(), launched_rows.size()])
	check(launched_rows.all(func(row: int) -> bool: return row == 1), "shots stay in the assigned adjacent lane")
	game.bullets.child_entered_tree.disconnect(observe)
	await _clear_cabbage()
	plant.attack_component.last_target_enemy = primary
	plant.attack_component.last_target_enemy_global_pos = primary.hurt_box_component.global_position
	plant.attack_component._aimed_lane = primary.lane
	var peak: int = 0 # 统计观察到的最大一次排程，不批量生成整个棋盘。
	for trial: int in range(320): # 固定随机种子，确保覆盖能同时触顶的极端组合。
		seed(trial + 332)
		plant._release_volley()
		peak = maxi(peak, 1 + plant._pending.size())
		plant._pending.clear()
		for ball: CabbageBall in _cabbage_projectiles(): # 只释放当前刚创建的实际弹。
			ball.free()
	check(peak >= 12 and peak <= 16, "triple and split with repeats stay below the sixteen-shot ceiling, observed %d" % peak)
	check(plant._nearby_targets(5, primary).size() == 5 and not plant._nearby_targets(5, primary).has(distant), "split target selection bounded by lane and count")
	plant.character_death_disappear()
	for target: Zombie000Base in extras + [primary, distant]: # 清理此轮全部演员。
		target.retire_from_battle()
	await wait_frames(4)

## 使用实际弹体和僵尸验证金、红、巨型、黑弹与200%的范围边界。
func _damage() -> void:
	var plant: Plant033CabbagePult = _plant_cabbage(Vector2i(4, 2), [0, 2, 4, 7]) # 可用三种特殊词条叠出强化。
	var primary: Zombie000Base = spawn(Vector2i(4, 5)) # 同格两只。
	var same: Zombie000Base = spawn(Vector2i(4, 5)) # 细小横移仍在同格。
	same.global_position.x += 14.0
	var near: Zombie000Base = spawn(Vector2i(5, 6)) # 3×3的对角边界。
	var far: Zombie000Base = spawn(Vector2i(4, 7)) # 相隔两列，不应受影响。
	var center_positions: Array[Vector2] = [primary.global_position, same.global_position] # 控制测试结束后复原原落点。
	var shot: RepeaterShotContext = RepeaterShotContext.from_plant(plant) # 用于与卡成长后的基数校对。
	var speed: float = plant.influence_speed_factors[Character000Base.E_Influence_Speed_Factor.AdventurePromotionAttackRate] # +30+20+20-30。
	check(is_equal_approx(speed, 1.4), "200% reduces attack rate by 30 percentage points")
	var base_hp: int = primary.hp_component.curr_hp # 各测试僵尸的相同初始体力。
	var gold: CabbageBall = _cabbage_ball(plant, primary, CabbageLanding.Payload.GOLD, false) # 真正从空中到达碰撞或地面。
	await wait_frames(100)
	check(not is_instance_valid(gold) and primary.hp_component.curr_hp == base_hp - shot.scaled_damage(40) * 2 \
		and same.hp_component.curr_hp == base_hp - shot.scaled_damage(40) * 2 and near.hp_component.curr_hp == base_hp \
		and far.hp_component.curr_hp == base_hp, "real gold parabola is double damage, confined to one cell with no direct duplicate")
	var red: CabbageBall = _cabbage_ball(plant, primary, CabbageLanding.Payload.HELL, false) # 单次真实命中入口。
	red.attack_once(primary)
	await wait_frames(3)
	var burn := primary.get_node_or_null(^"AdventureBurnEffect") as AdventureBurnEffect # 读取正式灼烧时钟。
	var charge := primary.get_node_or_null(^"AdventureDetonationChargeEffect") as AdventureDetonationChargeEffect # 小数引爆值原样叠加。
	check(burn != null and burn._remaining <= 3.0 and burn._remaining > 2.8 and charge != null and charge._points == 1.5 \
		and same.get_node_or_null(^"AdventureBurnEffect") == null, "red grants three seconds burn and 1.5 charge on direct victim (burn=%s, charge=%s)" \
			% [burn._remaining if burn != null else -1.0, charge._points if charge != null else -1.0])
	var before_x: float = near.global_position.x # 获取对角僵尸的实际格位。
	var pitch: float = shot.pitch_at(near.global_position, near.lane).x # 排除把一格写死为像素。
	var giant: CabbageBall = _cabbage_ball(plant, primary, CabbageLanding.Payload.HOMERUN, false) # 原生抛飞动作。
	giant.attack_once(primary)
	await wait_frames(3)
	var stun: Timer = near.all_timer[Character000Base.E_TimerType.Stun] # 读取真实眩晕时限。
	check(stun != null and stun.time_left > 0.9 and stun.time_left <= 1.0 and near.move_component.is_forced_airborne() \
		and not far.is_stunned(), "3x3 giant stuns and throws only qualifying zombies")
	await wait_frames(25)
	check(absf(near.global_position.x - before_x - pitch) < 3.0, "giant throws exactly one local cell")
	near.global_position.x = before_x
	primary.global_position = center_positions[0]
	same.global_position = center_positions[1]
	await wait_frames(2)
	var landing: CabbageBall = _cabbage_ball(plant, primary, CabbageLanding.Payload.GOLD, true) # 200%先乘原生基础再算金菜。
	var boosted: int = landing.attack_value # 入树时已经乘卡牌倍率。
	var splash_before: int = near.hp_component.curr_hp # 溅射只对非中心目标生效。
	var core_before: int = same.hp_component.curr_hp # 中心不叠加溅射。
	landing.attack_once(primary)
	await wait_frames(3)
	check(boosted == shot.scaled_damage(120) and not is_instance_valid(landing) and same.hp_component.curr_hp == core_before - 2 * boosted \
		and near.hp_component.curr_hp == splash_before - int(float(boosted) / 3.0) and far.hp_component.curr_hp == base_hp,
		"200% triples special base and applies only nearby secondary splash")
	var plain: CabbageBall = _cabbage_ball(plant, primary, 0, true) # 强化卡的非特殊弹保持正常值。
	check(not plain.has_splash and plain.attack_value == shot.scaled_damage(40), "200% leaves ordinary projectiles alone")
	plain.queue_free()
	var black: CabbageBall = _cabbage_ball(plant, primary, CabbageLanding.Payload.BLACK | CabbageLanding.Payload.GOLD, false) # 同次彩弹以黑菜爆伤结算。
	splash_before = near.hp_component.curr_hp
	core_before = same.hp_component.curr_hp
	black.attack_once(primary)
	await wait_frames(4)
	check(near.hp_component.curr_hp == splash_before - 600 and same.hp_component.curr_hp == core_before - 600 \
		and far.hp_component.curr_hp == base_hp, "black deals a single 600 to its 3x3, including overlapping gold")
	for target: Zombie000Base in [primary, same, near, far]: # 下一案例保持空棋盘。
		target.retire_from_battle()
	plant.character_death_disappear()
	await _clear_cabbage()

## 真僵王的易伤仍然受黑弹的最终300承伤上限。
func _boss() -> void:
	var plant: Plant033CabbagePult = _plant_cabbage(Vector2i(4, 2), [0, 2, 4, 6]) # 黑弹攻击来源。
	_check_payload_rates(plant)
	var manager: ZombieManager = game.zombie_manager # 走正式僵王工厂。
	var point: Vector2 = game.board.cell_at(Vector2i(4, 7)).get_spawn_global_position() # 真实落点。
	var boss := manager.try_create_boss_from_card(CharacterRegistry.ZombieBossType.ZB002BlackGeneral,
		manager.zombie_boss_root.to_local(point)) as ZB002BlackGeneral # 使用实际受击窗口。
	await wait_frames(5)
	if check(is_instance_valid(boss), "real boss available"):
		boss.set_physics_process(false)
		boss.visual.player.pause()
		boss._set_invulnerable(false)
		boss.hp_component.apply_degradation(0.50)
		var before: int = boss.hp_component.curr_hp # 取受击前的真实血量。
		var black: CabbageBall = _cabbage_ball(plant, boss, CabbageLanding.Payload.BLACK, false) # 原生僵王命中路径并非直接设置血量。
		black.attack_once(boss)
		await wait_frames(3)
		check(boss.hp_component.curr_hp == before - 300, "black final boss damage capped at 300 even after vulnerability")
		boss.queue_free()
	plant.character_death_disappear()
	await _clear_cabbage()

## 从实际 [param plant] 的四种独立判定验证30%触发率及组合可能性。
func _check_payload_rates(plant: Plant033CabbagePult) -> void:
	seed(332156)
	var hits := [0, 0, 0, 0] # 按颜色位记录各技能出现次数。
	var joint: int = 0 # 同一弹多种特效必须有机会共同发出。
	for _index: int in range(12000): # 固定种子减少波动，避免大量实体实例化。
		var flags: int = plant._roll_payload() # 实际每发离手调用的生产入口。
		for bit: int in range(hits.size()): # 四个概率互不抢占。
			hits[bit] += int((flags & (1 << bit)) != 0)
		joint += int((flags & (flags - 1)) != 0)
	check(hits.all(func(count: int) -> bool: return absi(count - 3600) < 220) and joint > 3000,
		"all four payloads are independently close to 30 percent")

## [param plant] 从真实弹口向 [param enemy] 发出已确定 [param flags] 与 [param boosted] 的测试投弹。
func _cabbage_ball(plant: Plant033CabbagePult, enemy: Character000Base, flags: int, boosted: bool) -> CabbageBall:
	var shot: RepeaterShotContext = RepeaterShotContext.from_plant(plant) # 相同出战快照协议。
	var runtime := CabbageLanding.for_battle(game) # 真实落点处理器。
	var ball := Global.bullet_registry.get_bullet_scenes(BulletRegistry.BulletType.Bullet009Cabbage).instantiate() as CabbageBall # 同一原生资源。
	var row: int = enemy.lane if enemy.lane >= 0 else plant.lane # 供僵王根节点无行时回退。
	var end: Vector2 = enemy.hurt_box_component.global_position # 实际受击锚点。
	ball.configure(runtime, shot, flags, boosted, CabbageLanding.foot_at(shot, enemy, end.x, row))
	var args: Dictionary = plant.attack_component.get_bullet_paras(plant.attack_component.markers_2d_bullet[0].global_position, Vector2.RIGHT) # 原生投手参数。
	args[Bullet000NormBase.E_InitParasAttr.Enemy] = enemy
	args[Bullet000NormBase.E_InitParasAttr.EnemyGloPos] = end
	args[Bullet000NormBase.E_InitParasAttr.BulletLane] = row
	args[Bullet000NormBase.E_InitParasAttr.AttackValidity] = shot.is_active
	ball.init_bullet(args)
	game.bullets.add_child(ball)
	return ball

## 在96个真实僵尸上执行48颗同时落地的范围弹。
func _stress_landings() -> void:
	var plant: Plant033CabbagePult = _plant_cabbage(Vector2i(4, 2), [0, 2, 4, 6]) # 继续使用正式出战。
	var targets: Array[Zombie000Base] = [] # 大量同区目标，检查批量索引是否重复工作。
	for index: int in range(96): # 足以逼近多株的高峰。
		var target: Zombie000Base = spawn(Vector2i(4 + index % 2, 4 + (index / 2) % 3)) # 都在两行三列范围。
		target.hp_component.set_spawn_max_health(100000)
		targets.append(target)
	await wait_frames(4)
	var runtime := CabbageLanding.for_battle(game) # 一批投弹只更新一次落点索引。
	var batch: Array[CabbageLanding.Impact] = [] # 预先准备，只计正式结算段。
	var shot: RepeaterShotContext = RepeaterShotContext.from_plant(plant) # 冻结战斗身份。
	var foot: Vector2 = game.board.cell_at(Vector2i(4, 5)).get_spawn_global_position() # 48发集中在同一3×3。
	for _index: int in range(48): # 不进入庞大临时渲染场景。
		var item := CabbageLanding.Impact.new() # 模拟已经真实抵达终点的落点快照。
		item.shot = shot
		item.foot = foot
		item.row = 4
		item.flags = CabbageLanding.Payload.BLACK
		item.base_damage = 40
		item.statuses = 5
		batch.append(item)
	var start: int = Time.get_ticks_usec() # 单独统计同帧落点准备成本。
	for item: CabbageLanding.Impact in batch: # 与真实队列共用捕获入口。
		runtime._prepare(item)
	var prep_ms: float = (Time.get_ticks_usec() - start) / 1000.0 # 不包含真实扣血。
	var peak_ms: float = 0.0 # 最慢一次伤害预算。
	var steps: int = 0 # 等待生产调度器的每批结果。
	while not runtime._work.is_empty() and steps < 100: # 冻结的目标仍然必须全部消费。
		start = Time.get_ticks_usec()
		runtime._drain()
		peak_ms = maxf(peak_ms, (Time.get_ticks_usec() - start) / 1000.0)
		runtime.set_physics_process(false) # 验收用时逐步采样，避免同一步执行两次。
		steps += 1
		await wait_frames(1)
	check(targets[-1].hp_component.curr_hp == 100000 - 48 * 600 and runtime._by_cell.size() == 6, "dense burst retains every valid hit")
	check(steps > 1 and runtime._work.is_empty(), "dense burst is spread across bounded steps")
	print("CABBAGE_STRESS targets=96 landings=48 steps=", steps, " prepare_ms=", "%.2f" % prep_ms, " drain_peak_ms=", "%.2f" % peak_ms)
	for target: Zombie000Base in targets: # 不保存压力测试档。
		target.retire_from_battle()
	plant.character_death_disappear()
	await wait_frames(4)

## 返回当前仍活着的卷心菜物理弹。
func _cabbage_projectiles() -> Array[CabbageBall]:
	var result: Array[CabbageBall] = [] # 从原生弹体容器读取。
	for node: Node in game.bullets.get_children(): # 跳过伤害和视觉运行时。
		if node is CabbageBall and not node.is_queued_for_deletion():
			result.append(node)
	return result

## 分案回收旧弹以清理真实重叠数据。
func _clear_cabbage() -> void:
	for ball: CabbageBall in _cabbage_projectiles(): # 只删除本案例产生的真弹。
		ball.queue_free()
	await wait_frames(4)
