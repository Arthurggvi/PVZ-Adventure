## 仙人掌转职在真实攻击动画、弹体与战斗状态的回归。
extends Node

## 正常研究与战斗共用的物种。
const CACTUS := CharacterRegistry.PlantType.P027Cactus
## 一至四阶的两条选择。
const BOOKS: Array[String] = ["promotion_cactus_guided", "promotion_cactus_pierce",
	"promotion_cactus_wound", "promotion_cactus_shock", "promotion_cactus_flood", "promotion_cactus_thunder",
	"promotion_cactus_burst", "promotion_cactus_scatter"]
## 正常图书馆书目入口。
const Library = preload("res://scripts/adventure/library/library_rules.gd")
## 正式的图书馆及出战状态使用的同一份定义。
const Runtime = preload("res://scripts/adventure/research/cactus_battle_effects.gd")
## 僵尸状态枚举，地面与空中保持原生规则。
const States = Zombie000Base.E_BeAttackStatusZombie
## 正式负面效果门面的输入类型。
const Status = AdventurePlantNegativeEffects.Kind
## 当前隔离战斗。
var game: MainGameManager
## 本轮失败条数。
var failures: int = 0

## 保持本节点跨越换场。
func _ready() -> void:
	get_tree().current_scene = null
	_run.call_deferred()

## 运行隔离验收，选择性执行密集战场测试。
func _run() -> void:
	if not check(OS.get_user_data_dir().contains("cactus-promotion"), "isolated user directory"):
		get_tree().quit(1)
		return
	Global.save_service.stop_autosave()
	seed(27024)
	_catalog()
	if await open_battle() and AdventurePromotionCatalog.BOOKS.has(BOOKS[0]):
		await _combat()
	if is_instance_valid(game):
		game.queue_free()
		await wait_frames(3)
	print("CACTUS_RESULT=", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

## 报告 [param label] 便于定位，返回 [param ok]。
func check(ok: bool, label: String) -> bool:
	if not ok:
		failures += 1
		printerr("CACTUS_FAIL ", label)
	return ok

## 正式图书馆、物品和技能选项必须指向同一组 ID。
func _catalog() -> void:
	var record: PlantCardInstance = make_record([]) # 逐阶按正式顺序推进。
	for tier: int in range(4): # 一阶一对，任何一阶缺失仍继续核对。
		var choices: Array[String] = BOOKS.slice(tier * 2, tier * 2 + 2) # 本阶玩家可以看到的书。
		check(Library.pool(tier + 1, CACTUS) == choices, "library tier %d" % [tier + 1])
		check(AdventurePromotionCatalog.options(record).map(func(book: Dictionary): return book.id) == choices,
			"research options tier %d" % [tier + 1])
		for id: String in choices: # 两条路线均需注册物品。
			check(ItemRegistry.has_item(id), "book " + id)
		record.set_promotion(tier + 1, choices[0])
	check(AdventurePromotionCatalog.is_valid_chain(record), "valid four-tier chain")
	var data := AdventureState.new() # 隔离账户解锁正式研究入口。
	AdventureQuestService.record_event(data, "stage_cleared", "zombie_island.lawn/normal", "2026-11-24")
	data.quests.records["first_expedition"].status = "claimed"
	var items := AdventureInventoryService.new(data) # 真正的战斗植物与技能书物品。
	var wallet := GlobalGameState.new() # 四次转职总费用。
	wallet.adventure_state = data
	wallet.coin_value = 20000
	var service := AdventureResearchService.new(data, items, wallet, func() -> bool: return true) # 模拟成功提交的隔离本地存档。
	var uid: String = items.add_card(CACTUS, 10) # 用另一条合法路线上全部八本已测试的书目。
	for tier: int in range(4): # 每阶准确消耗本阶一本书和金币。
		var id: String = BOOKS[tier * 2 + 1] # 走每阶第二项。
		items.add_item(id, 1)
		check(service.execute("promotion", {"uid": uid, "book_id": id}).ok and items.get_item_count(id) == 0
			and wallet.coin_value == 15000 - tier * 5000, "paid promotion tier %d" % [tier + 1])
	wallet.free()

## 构造 [param choices] 指定的一至四阶研究快照。
func make_record(choices: Array[int]) -> PlantCardInstance:
	var record := PlantCardInstance.new() # 十星允许全部可玩阶数。
	record.uid = "PC000027"
	record.plant_type = CACTUS
	record.stars = 10
	for i: int in range(choices.size()): # 以书目 ID 登记到真正的卡片状态。
		record.set_promotion(i + 1, BOOKS[choices[i]])
	return record

## 开启原生泳池关卡，清空随机波次。
func open_battle() -> bool:
	var level: ResourceLevelData = load("res://resources/level_date_resource/mode_adventure/adventure_03_pool.tres").duplicate(true) # 只修改隔离关卡。
	level.look_show_zombie = false
	level.can_choosed_card = false
	level.monster_mode = ConstLevelData.E_MonsterMode.Null
	level.is_day_sun = false
	level.prechosen_cards = [ResourceCardReference.create(ResourceCardReference.CardType.Plant, CACTUS)]
	Global.game_para = level
	if not check(get_tree().change_scene_to_file("res://scenes/main/MainGame02Back.tscn") == OK, "load gameplay"):
		return false
	for _frame: int in range(360): # 用实际物理帧等待原生进场。
		await get_tree().physics_frame
		game = Global.main_game
		if is_instance_valid(game) and game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME:
			return true
	return check(false, "native battle ready")

## 实际种下 [param choices] 指定的仙人掌 [param address]。
func plant_at(address: Vector2i, choices: Array[int]) -> Plant027Cactus:
	var cell: PlantCell = game.board.cell_at(address) # 原生棋盘的权威占格。
	var profile := PlantSpawnProfile.create(make_record(choices).to_dict(), AdventureResearchBattleEffects.new()) # 正式入树前效果。
	var plant := cell.create_plant(CACTUS, false, false, false, false, profile) as Plant027Cactus # 真实角色。
	check(plant != null, "place cactus")
	return plant

## 在 [param address] 生成 [param species]，固定位置指调用原生命中的人偶。
func spawn(address: Vector2i, species: CharacterRegistry.ZombieType = CharacterRegistry.ZombieType.Z001Norm) -> Zombie000Base:
	var cell: PlantCell = game.board.cell_at(address) # 真实行和脚点。
	var manager: ZombieManager = game.zombie_manager # 原生僵尸工厂。
	# 通过原生入场登记状态、受击区和游戏行。
	var zombie: Zombie000Base = manager.create_norm_zombie(species, manager.all_zombie_rows[address.x], {
		Zombie000Base.E_ZInitAttr.Lane: address.x,
		Zombie000Base.E_ZInitAttr.CurrZombieRowType: cell.get_spawn_terrain_type(),
		Zombie000Base.E_ZInitAttr.ParticipatesNaturalRefresh: false,
	}, cell.get_spawn_global_position())
	if check(zombie != null, "native enemy"):
		zombie.move_component.update_move_factor(true, MoveComponent.E_MoveFactor.IsDisable)
		zombie.hp_component.set_spawn_max_health(30000)
	return zombie

## 核对紫色实弹、创伤、两类防具以及多次碰撞去重。
func _combat() -> void:
	var plant: Plant027Cactus = plant_at(Vector2i(1, 2), [1, 2]) # 带贯穿的创伤弹。
	var target: Zombie000Base = spawn(Vector2i(1, 5)) # 无甲目标。
	var helmet: Zombie000Base = spawn(Vector2i(1, 6), CharacterRegistry.ZombieType.Z005Bucket) # 一类防具。
	var shield: Zombie000Base = spawn(Vector2i(1, 7), CharacterRegistry.ZombieType.Z007ScreenDoor) # 二类防具。
	if plant != null and target != null and helmet != null and shield != null:
		plant.attack_component._shoot_bullet()
		var bullet: BulletLinear007Cactus = projectiles().back() # 原生场景中的实际弹体。
		var before: int = target.hp_component.curr_hp # 本击发生前的本体生命。
		bullet.attack_once(target)
		check(target.hp_component.cactus_wound_stacks == 20 and before - target.hp_component.curr_hp == bullet.attack_value,
			"twenty wounds apply after the projectile's own hit")
		before = target.hp_component.curr_hp
		bullet.attack_once(target)
		check(before == target.hp_component.curr_hp and target.hp_component.cactus_wound_stacks == 20,
			"one piercing projectile cannot hit the same zombie twice")
		target.be_attacked_bullet(10, BulletRegistry.AttackMode.Norm, false, false)
		check(before - target.hp_component.curr_hp == 30, "wounds add once to the next damage packet")
		var helmet_hp := helmet.hp_component as HpComponentZombie # 普通防具仍按原生扣血。
		var equipment: int = helmet_hp.curr_hp_armor1 # 防具伤害与贯穿资格可同时存在。
		bullet.attack_once(helmet)
		check(not bullet.is_queued_for_deletion() and helmet_hp.curr_hp_armor1 < equipment, "pierces first-class equipment")
		var shield_hp := shield.hp_component as HpComponentZombie # 一击破盾仍要被盾拦住。
		shield_hp.curr_hp_armor2 = 1
		bullet.attack_once(shield)
		check(bullet.is_queued_for_deletion() and shield_hp.curr_hp_armor2 == 0, "second-class equipment stops a projectile even on break")
	await reset_field()
	await _salvos_and_air()
	await _shock_and_thunder()
	await _death_bloom()
	if OS.get_cmdline_user_args().has("--stress"):
		await _stress()

## 读场上真实弹体的数量及角度，五连发应错开，散射应为第四轮整组十发。
func _salvos_and_air() -> void:
	var burst: Plant027Cactus = plant_at(Vector2i(0, 1), [1, 2, 4, 6]) # 测试原生突破时钟。
	if burst != null:
		burst.attack_component._shoot_bullet()
		check(projectiles().size() == 1, "burst starts with only the first shot")
		await wait_frames(26)
		check(projectiles().size() == 5, "burst releases five shots on the native field")
	await reset_field()
	var fan: Plant027Cactus = plant_at(Vector2i(4, 1), [0, 3, 5, 7]) # 低高态分别提供90%和40%额外攻速。
	if fan != null:
		check(is_equal_approx(fan.attack_component.bullet_attack_cd_timer.speed_scale,
			fan.attack_component._owner_speed_product * 1.9), "ground guided rate includes fifty points")
		for _volley: int in range(4): # 前三次单发，第四次十发散射。
			fan.attack_component._shoot_bullet()
		var darts: Array[BulletLinear007Cactus] = projectiles() # 都由原槽发出。
		check(darts.size() == 13, "fourth volley contains exactly ten shots")
		if darts.size() == 13:
			check(is_equal_approx(darts[3].direction.angle_to(darts.back().direction), PI / 3.0), "scatter covers exactly sixty degrees")
	await reset_field()
	var cactus: Plant027Cactus = plant_at(Vector2i(4, 1), [0, 3]) # 真实检测器驱动伸展和射击。
	var balloon: Zombie000Base = spawn(Vector2i(4, 7), CharacterRegistry.ZombieType.Z017Balloon) # 可被一发尖刺击破。
	if cactus != null and balloon != null:
		var homed: bool = false # 空中弹体首段要确实向垂直方向转向。
		for _frame: int in range(240): # 等待真实伸展动画的高态射击帧。
			await wait_frames(1)
			for dart: BulletLinear007Cactus in projectiles(): # 不手动触发高态攻击。
				if (dart.can_attack_zombie_status & States.IsSky) != 0 and absf(dart.direction.y) > 0.013:
					homed = true
					break
			if homed:
				break
		check(cactus.is_rise and is_equal_approx(cactus.attack_component.bullet_attack_cd_timer.speed_scale,
			cactus.attack_component._owner_speed_product * 1.2), "native cactus rises and uses air attack rate")
		check(homed, "a naturally fired cactus dart turns toward the real balloon")
	await reset_field()

## 感电只从真实血池扣减触发，最近三跳限时，惊雷满五层只打当前合法占格。
func _shock_and_thunder() -> void:
	var plant: Plant027Cactus = plant_at(Vector2i(4, 0), [0, 3, 5]) # 使用正式出手快照。
	if plant == null:
		return
	var shot: RepeaterShotContext = RepeaterShotContext.from_plant(plant) # 本轮可以在母株离场后继续。
	var runtime: Runtime = ensure_runtime(plant) # 综合战斗中真实弹体创建共享结算器。
	plant.be_shovel_kill()
	var victims: Array[Zombie000Base] = [] # 同一行从触发者到第四个候选。
	for i: int in range(5): # 相邻距离均在真实一格内，超出三跳的最后一只用来验上限。
		var target: Zombie000Base = spawn(Vector2i(4, 2)) # 固定坐标的实战目标。
		target.global_position.x += i * 34.0
		victims.append(target)
	await wait_frames(4)
	check(apply_status(victims[0], Status.CACTUS_SHOCK, 1, runtime, shot), "first shock mark accepted")
	check(apply_status(victims[1], Status.CACTUS_SHOCK, 1, runtime, shot), "adjacent shock mark accepted")
	for _hit: int in range(4): # 同一窗口对同一目标多次伤害只发一链。
		victims[0].be_attacked_bullet(12, BulletRegistry.AttackMode.Norm, false, false)
	await wait_frames(15)
	check(victims[0].hp_component.curr_hp == 30000 - 48 and victims[1].hp_component.curr_hp == 29990
		and victims[2].hp_component.curr_hp == 29990 and victims[3].hp_component.curr_hp == 29990
		and victims[4].hp_component.curr_hp == 30000, "exactly three unique hops and no electric feedback")
	victims[0].be_attacked_bullet(1, BulletRegistry.AttackMode.Norm, false, false)
	await wait_frames(6)
	check(victims[1].hp_component.curr_hp == 29990, "hits strictly before 0.3 seconds do not retrigger")
	victims[0].be_attacked_bullet(1, BulletRegistry.AttackMode.Norm, false, false)
	await wait_frames(15)
	check(victims[1].hp_component.curr_hp == 29980, "shock re-arms after 0.3 combat seconds")
	await reset_field()
	var origin: Zombie000Base = spawn(Vector2i(4, 4)) # 落雷目标脚下格。
	var sibling: Zombie000Base = spawn(Vector2i(4, 4)) # 同格另一个目标。
	var adjacent: Zombie000Base = spawn(Vector2i(4, 5)) # 相邻格绝不能被选中。
	sibling.global_position.x += 8.0
	await wait_frames(3)
	for _mark: int in range(4): # 前四层仍未伤害。
		apply_status(origin, Status.CACTUS_THUNDER, 1, runtime, shot)
	await wait_frames(2)
	check(origin.hp_component.curr_hp == 30000 and sibling.hp_component.curr_hp == 30000, "thunder waits for its fifth mark")
	apply_status(origin, Status.CACTUS_THUNDER, 1, runtime, shot)
	await wait_frames(3)
	check(origin.hp_component.curr_hp == 28200 and sibling.hp_component.curr_hp == 28200
		and adjacent.hp_component.curr_hp == 30000, "one 1800 damage strike covers only the actual cell")
	if DisplayServer.get_name() != "headless":
		_check_sky_strike(runtime, game.board.cell_at(Vector2i(4, 4)))
	var lethal_plant: Plant027Cactus = plant_at(Vector2i(4, 0), [0, 3, 5]) # 用实际第五发杀死同格的一只。
	if lethal_plant != null:
		for _mark: int in range(4): # 置于下一次落雷的触发阈值前。
			apply_status(origin, Status.CACTUS_THUNDER, 1, runtime, shot)
		origin.hp_component.curr_hp = origin.hp_component.death_hp + 1
		lethal_plant.attack_component._shoot_bullet()
		projectiles().back().attack_once(origin)
		await wait_frames(4)
		check(sibling.hp_component.curr_hp == 26400 and adjacent.hp_component.curr_hp == 30000,
			"lethal fifth shot still strikes the original actual cell")
	await reset_field()

## 校验 [param runtime] 真实落雷的唯一主干，从主视口上方贯通到 [param cell] 的实际脚点。
func _check_sky_strike(runtime: Runtime, cell: PlantCell) -> void:
	var effect := runtime.get_node_or_null(^"CactusThunderStrike") as Node2D # 实战第五层创建的共享演出。
	if not check(effect != null, "native fifth hit creates a full-height sky strike"):
		return
	if not check(effect._strikes.size() == 1, "single cast has just one lightning trunk"):
		return
	var trunk: PackedVector2Array = effect._strikes[0].trunk # 同一组顶点是原生画布实际绘制的折线。
	var screen: Transform2D = effect.get_global_transform_with_canvas() # 当前相机偏移也参与坐标核对。
	var ground: Vector2 = cell.get_spawn_global_position() # 本格的世界脚点。
	check(trunk.size() >= 12 and (screen * trunk[0]).y < effect.get_viewport_rect().position.y
		and effect.to_global(trunk[-1]).is_equal_approx(ground), "lightning spans the actual viewport down to the struck cell")
	check(game.camera_2d._shake_duration > 0.0, "lightning triggers a native camera impact")
	check(runtime._thunder_audio != null and runtime._thunder_audio.get_length() > 2.0,
		"the ground impact loads an independent thunder recording")
	var previously_paused: bool = get_tree().paused # 暂停菜单不能留下一帧高亮一直铺在战场上。
	get_tree().paused = true
	check(not effect.visible, "pausing hides the full-screen flash")
	get_tree().paused = previously_paused
	check(effect.visible or previously_paused, "resuming restores the remaining lightning animation")

## 验证泛滥初次致死、精确传播现有层数，以及原株离场后的作用域。
func _death_bloom() -> void:
	var plant: Plant027Cactus = plant_at(Vector2i(5, 1), [1, 2, 4]) # 创伤和亡语组合。
	var target: Zombie000Base = spawn(Vector2i(5, 4)) # 将要被第一发就杀死的伤者。
	var nearby: Zombie000Base = spawn(Vector2i(5, 6)) # 亡语尖刺的目标。
	if plant != null and target != null and nearby != null:
		var shot: RepeaterShotContext = RepeaterShotContext.from_plant(plant) # 保留实际母株来源。
		var runtime: Runtime = ensure_runtime(plant) # 先发实弹再配置靶子。
		apply_status(target, Status.CACTUS_WOUND, 37, runtime, shot)
		target.hp_component.curr_hp = target.hp_component.death_hp + 1
		var shot_bullet: BulletLinear007Cactus = projectiles().back() # 即使在母株铲除后仍可命中。
		plant.be_shovel_kill()
		shot_bullet.attack_once(target)
		shot_bullet.queue_free()
		await wait_frames(4)
		var ring: Array[BulletLinear007Cactus] = projectiles() # 亡语应只产生一圈。
		check(ring.size() == 12, "first-hit kill blooms exactly one ring")
		if not ring.is_empty():
			ring[0].attack_once(nearby)
			check(nearby.hp_component.cactus_wound_stacks == 37, "ring transfers the corpse's current wound count without adding twenty")
	await reset_field()

## 压测同一波的所有敌人都携带两种高成本状态，并在物理步内触发满连锁。
func _stress() -> void:
	var plant: Plant027Cactus = plant_at(Vector2i(1, 0), [0, 3]) # 制造一个合法的共享战斗快照。
	if plant == null:
		return
	var shot: RepeaterShotContext = RepeaterShotContext.from_plant(plant) # 共享同一发射身份。
	var runtime: Runtime = ensure_runtime(plant) # 真实场景容器的结算器。
	var targets: Array[Zombie000Base] = [] # 四条陆路集中测试。
	for lane: int in [0, 1, 4, 5]: # 每条路放24只实际僵尸。
		for index: int in range(24): # 以重叠列考验位置索引和渲染量。
			var target: Zombie000Base = spawn(Vector2i(lane, 2 + index % 6)) # 再用小偏移打散候选距离。
			target.global_position.x += float(index / 6) * 7.0
			targets.append(target)
	await wait_frames(4)
	for target: Zombie000Base in targets: # 满栈或超可见栈不改变实际创伤。
		apply_status(target, Status.CACTUS_WOUND, 300, runtime, shot)
		apply_status(target, Status.CACTUS_SHOCK, 1, runtime, shot)
	if DisplayServer.get_name() != "headless":
		var quills: Node = targets[0].get_node_or_null(^"CactusWoundQuills") # 真实台面上实际分配的绘制项。
		check(quills != null and quills._shown == 12 and quills._anchors.size() <= 4
			and not quills.is_processing(), "wounds preserve a static visual budget")
	plant.be_shovel_kill()
	var samples := PackedInt64Array() # 只记录真正执行链的帧。
	for _wave: int in range(4): # 4组各96道三跳。
		for target: Zombie000Base in targets: # 所有触发都在同一物理步到达。
			target.be_attacked_bullet(1, BulletRegistry.AttackMode.Norm, false, false)
		for _frame: int in range(24): # 窗口留足时间回完三段并重新武装。
			await wait_frames(1)
			if runtime.last_resolution_usec > 20:
				samples.append(runtime.last_resolution_usec)
	var loss: int = 0 # 创伤让本次伤害变为301，跳跃则为310。
	for target: Zombie000Base in targets: # 总损失给出完整的无丢弃结果。
		loss += 30000 - target.hp_component.curr_hp
	check(loss == 96 * 4 * (301 + 3 * 310), "dense marks retain every jump and all 300 wound stacks")
	samples.sort()
	if not samples.is_empty():
		print("CACTUS_STRESS targets=", targets.size(), " hops=", 96 * 4 * 3, " p95_ms=", samples[floori(samples.size() * 0.95)] / 1000.0)
	await reset_field()

## 借 [param plant] 的真实攻击首帧确保运行时存在。
func ensure_runtime(plant: Plant027Cactus) -> Runtime:
	plant.attack_component._shoot_bullet()
	return game.bullets.get_node(^"CactusBattleEffects") as Runtime

## 用正式状态门面为 [param target] 施加 [param kind] 的 [param amount] 层，原 [param shot] 属于 [param runtime]。
func apply_status(target: Zombie000Base, kind: Status, amount: int, runtime: Runtime, shot: RepeaterShotContext) -> bool:
	return AdventurePlantNegativeEffects.apply(target, kind, 0, amount, 0.0, {"cactus_runtime": runtime, "shot": shot})

## 返回本场当前所有没有排队离开的仙人掌实弹。
func projectiles() -> Array[BulletLinear007Cactus]:
	var darts: Array[BulletLinear007Cactus] = [] # 其他特效节点不计入射击结果。
	for node: Node in game.bullets.get_children(): # 检查正式父容器。
		if node is BulletLinear007Cactus and not node.is_queued_for_deletion():
			darts.append(node)
	return darts

## 回收现有测试场面，保留物理时钟及共享结算器。
func reset_field() -> void:
	for target: Zombie000Base in game.zombie_manager.all_zombies_1d.duplicate(): # 退场不会误报亡语。
		if is_instance_valid(target) and not target.is_death:
			target.retire_from_battle()
	for cell: PlantCell in game.board.cells(): # 只撤除本测试已种下的原生植株。
		for plant: Plant000Base in cell.living_plants():
			plant.be_shovel_kill()
	for bullet: BulletLinear007Cactus in projectiles(): # 避免在下个用例路径上残留弹体。
		bullet.queue_free()
	await wait_frames(7)

## 推进 [param count] 帧实际物理时间。
func wait_frames(count: int) -> void:
	for _frame: int in range(count): # 有界等待物理同步。
		await get_tree().physics_frame
