## 西瓜投手四阶在正式卡栏、原生动画和真实抛物线弹体上的回归。
extends "res://tests/adventure/test_starfruit_promotions.gd"

## 正式卡栏和图书馆使用的西瓜投手编号。
const MELON := CharacterRegistry.PlantType.P040MelonPult
## 四阶各两个书目，按图书馆的显示顺序排列。
const MELON_BOOKS: Array[String] = ["promotion_melon_scatter", "promotion_melon_heavy",
	"promotion_melon_shatter", "promotion_melon_knockback", "promotion_melon_burst",
	"promotion_melon_stun", "promotion_melon_kratos", "promotion_melon_formation"]
## 出战卡栏中的实物卡，用于完整种植事务。
var _card: Card

## 在隔离存档中逐项核对实战行为。录像模式用相同战场及真实发动流程。
func _run() -> void:
	if not check(OS.get_user_data_dir().contains("melon-promotion"), "isolated user data"):
		get_tree().quit(2)
		return
	Global.save_service.stop_autosave()
	seed(40024)
	if await open_battle():
		if OS.get_cmdline_user_args().has("--record-preview"):
			await _record_preview()
		else:
			_melon_catalog()
			await _scatter_and_charge()
			await _heavy_and_formation()
			await _impact([1, 2], 104, 104)
			await _impact([1, 2, 4], 208, 208)
			await _impact([1, 3, 5], 80, 26, true)
			if OS.get_cmdline_user_args().has("--stress"):
				await _stress_melons()
	if is_instance_valid(game):
		game.queue_free()
		await wait_frames(4)
	print("MELON_RESULT=", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

## 增记 [param label] 对应的 [param valid] 失败。返回检查结果以保护后续访问。
func check(valid: bool, label: String) -> bool:
	if not valid:
		failures += 1
		printerr("MELON_FAIL ", label)
	return valid

## 进入无自动波次的正式五行草地。干燥地形保证三行重磅落点均可使用。
func open_battle() -> bool:
	var level: ResourceLevelData = load("res://resources/level_date_resource/mode_adventure/adventure_01_day.tres").duplicate(true) # 临时关卡设置。
	level.look_show_zombie = false
	level.can_choosed_card = false
	level.monster_mode = ConstLevelData.E_MonsterMode.Null
	level.is_day_sun = false
	level.start_sun = 5000
	level.prechosen_cards = [ResourceCardReference.create(ResourceCardReference.CardType.Plant, MELON)]
	Global.game_para = level
	if not check(get_tree().change_scene_to_file("res://scenes/main/MainGame01Front.tscn") == OK, "open native lawn"):
		return false
	for _frame: int in range(420): # 只在卡栏真正允许交互后开始。
		await get_tree().physics_frame
		game = Global.main_game
		if is_instance_valid(game) and game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME:
			var slots: CardSlotBattle = game.card_manager.card_slot_battle # 实际完成出战准备的卡栏。
			if slots != null and not slots.curr_cards.is_empty() and slots.curr_cards[0].card_context == Card.CardContext.Battle:
				_card = slots.curr_cards[0]
				return true
	return check(false, "battle card became ready")

## 通过图书馆、背包和研究选择的实际入口核对四阶编号。
func _melon_catalog() -> void:
	var card := PlantCardInstance.new() # 从空成长逐阶申请可选书单。
	card.plant_type = MELON
	card.stars = 10
	for tier: int in range(1, 5): # 每阶的两个稳定编号。
		var expected: Array[String] = MELON_BOOKS.slice(2 * (tier - 1), 2 * tier) # 当前正式书单。
		check(Library.pool(tier, MELON) == expected, "library tier %d" % tier)
		check(AdventurePromotionCatalog.options(card).map(func(entry: Dictionary): return entry.id) == expected,
			"research tier %d" % tier)
		for id: String in expected: # 图书馆交付的书应能进入背包。
			check(ItemRegistry.has_item(id), "registered item " + id)
		card.set_promotion(tier, expected[0])
	check(AdventurePromotionCatalog.is_valid_chain(card), "saved four-tier chain")
	check(is_equal_approx(_card.cool_time, 15.0) and is_equal_approx(float(Global.character_registry.get_plant_info(
		CharacterRegistry.PlantType.P045WinterMelon, CharacterRegistry.PlantInfoAttribute.CoolTime)), 50.0),
		"only Melon-pult placement changes to 15 seconds")

## 从实际手持卡栏用 [param choices] 在 [param address] 完成种植、扣费与冷却。暂时停止原生攻击供各段独立控制。
func _plant_melon(address: Vector2i, choices: Array[int]) -> Plant040MelonPult:
	var card := PlantCardInstance.new() # 与正式出战相同的十星快照。
	card.uid = "PC000040"
	card.plant_type = MELON
	card.stars = 10
	for index: int in choices.size(): # 每个下标指定对应阶的书目。
		card.set_promotion(index + 1, MELON_BOOKS[choices[index]])
	_card.plant_spawn_profile = PlantSpawnProfile.create(card.to_dict(), AdventureResearchBattleEffects.new())
	_card.set_card_cool_end()
	_card.judge_card_ready()
	game.hand_manager._click_card(_card)
	var cell: PlantCell = game.board.cell_at(address) # 正式占格及其真实地形。
	var placed: bool = game.hand_manager.hm_character.click_cell(cell) # 同正式点击结算。
	game.hand_manager._cancel_selection()
	var plant := cell.plant_in_cell[CharacterRegistry.PlacePlantInCell.Norm] as Plant040MelonPult # 读取实际种下的植物。
	if check(placed and is_instance_valid(plant), "place melon at %s" % [address]):
		plant.attack_component.disable_component(ComponentNormBase.E_IsEnableFactor.Character)
	return plant

## 从战场弹体容器记录 [param child] 的真实投掷行、落点快照和直击伤害到 [param log]。
func _observe_melon(child: Node, log: Array[Dictionary]) -> void:
	if child is Bullet012Melon:
		log.append({"lane": child.lane, "point": child.target_enemy_glo_pos_init,
			"target": child.target_enemy, "damage": child.attack_value})

## 核对 [param plant] 的单独转职倍率 [param expected]，并确认原生时钟合成其余因素。
func _check_attack_rate(plant: Plant040MelonPult, expected: float) -> void:
	var promotion: float = plant.influence_speed_factors.get(
		Character000Base.E_Influence_Speed_Factor.AdventurePromotionAttackRate, 1.0) # 排除角色出生时随机获得的速度因素。
	check(is_equal_approx(promotion, expected) and is_equal_approx(
		plant.attack_component.bullet_attack_cd_timer.speed_scale, plant.speed_factor_product()),
		"native timer applies the %.2f promotion attack rate" % expected)

## 核对原生时钟从邻行索敌，蓄力一秒再开始正常挥篮，以及三行弹和双倍幻影伤害。
func _scatter_and_charge() -> void:
	var plant: Plant040MelonPult = _plant_melon(Vector2i(2, 2), [0, 2, 4, 6]) # 散射、爆碎、爆射、克拉托斯同一实体。
	var zombie: Zombie000Base = spawn(Vector2i(3, 6)) # 本行和另一侧无敌。
	if not is_instance_valid(plant) or not is_instance_valid(zombie):
		return
	var component: AttackComponentBulletBase = plant.attack_component # 这里仅观察自然攻击组件。
	check(is_equal_approx(_card._cool_timer, 15.0) and is_equal_approx(component.attack_cd, 3.0),
		"real placement cooldown is 15 while native attack interval remains 3")
	_check_attack_rate(plant, 0.8)
	var log: Array[Dictionary] = [] # 已实例化并进入战斗的三行弹。
	var track := _observe_melon.bind(log) # 退出本段时移除观察器。
	game.bullets.child_entered_tree.connect(track)
	var cooled: Array[int] = [] # 原生计时器实际超时的物理帧。
	component.bullet_attack_cd_timer.timeout.connect(func() -> void: cooled.append(Engine.get_physics_frames()), CONNECT_ONE_SHOT)
	component.enable_component(ComponentNormBase.E_IsEnableFactor.Character)
	var animation_started: int = -1 # 原生攻击动画播放的首帧。
	for _frame: int in range(220): # 有界等候自然索敌、蓄力以及扔出整组。
		await wait_frames(1)
		if animation_started < 0 and component.animation_tree.get("parameters/OneShot/active"):
			animation_started = Engine.get_physics_frames()
		if log.size() >= 3:
			break
	component.disable_component(ComponentNormBase.E_IsEnableFactor.Character)
	game.bullets.child_entered_tree.disconnect(track)
	if check(not cooled.is_empty() and animation_started >= 0, "only an adjacent zombie can start a native attack"):
		var elapsed: int = animation_started - cooled[0] # 从冷却完成到开始摆篮，允许物理和动画调度交接。
		check(absi(elapsed - Engine.physics_ticks_per_second) <= 6, "Kratos charges for one game second (%d frames)" % elapsed)
	var lanes: Array = log.map(func(throw: Dictionary): return throw.lane) # 落空行也要生成真实弹体。
	lanes.sort()
	check(lanes == [1, 2, 3] and log.any(func(throw: Dictionary) -> bool: return throw.target == zombie),
		"one scatter volley covers each valid lane and locks the real target")
	var damage: int = roundi(320.0 * plant.battle_damage_multiplier) # 爆射和幻影各乘两倍，共用出战成长倍率。
	check(not log.is_empty() and log.all(func(throw: Dictionary) -> bool: return throw.damage == damage),
		"Kratos and Burst each double each real projectile")
	await _retire([plant], [zombie])

## 将 [param plant] 瞄准 [param enemy]，固定随机种子 [param rng_seed]，沿用实际动画的发射回调和弹体工厂。
func _release(plant: Plant040MelonPult, enemy: Zombie000Base, rng_seed: int) -> void:
	var component := plant.attack_component as AttackComponentBulletPultBase # 使用原生抛投组件的瞄准快照。
	component.last_target_enemy = enemy
	component.last_target_enemy_global_pos = enemy.hurt_box_component.global_position
	component._aimed_lane = enemy.lane
	seed(rng_seed)
	component._shoot_bullet()

## 返回首个全局随机数可产生 [param heavy] 结果的固定种子。
func _heavy_seed(heavy: bool) -> int:
	var rng := RandomNumberGenerator.new() # 搜索不改变战场全局随机序列。
	for choice: int in range(1, 64): # 固定小样本内同时存在两种结果。
		rng.seed = choice
		if (rng.randf() < 0.5) == heavy:
			return choice
	return 1

## 重磅只做一次判定，六颗弹分散在真实3×3；列阵按含本株的同列存活西瓜重复完整散射。
func _heavy_and_formation() -> void:
	var heavy: Plant040MelonPult = _plant_melon(Vector2i(1, 1), [1]) # 重磅独立观察通过和未通过的两轮。
	var formation: Plant040MelonPult = _plant_melon(Vector2i(2, 2), [0, 3, 4, 7]) # 散射的完整三弹批次可数。
	var upper: Plant040MelonPult = _plant_melon(Vector2i(0, 2), []) # 同列但相隔两行也计数。
	var lower: Plant040MelonPult = _plant_melon(Vector2i(4, 2), []) # 第二个同列来源，可移除复测。
	var unrelated: Plant040MelonPult = _plant_melon(Vector2i(2, 3), []) # 同行不同列不能增加次数。
	var target: Zombie000Base = spawn(Vector2i(2, 6)) # 3×3内有九个可用格。
	if [heavy, formation, upper, lower, unrelated, target].has(null):
		return
	await wait_frames(4)
	var log: Array[Dictionary] = [] # 直接记录原生弹体落点与行。
	var track := _observe_melon.bind(log) # 各轮后复用同一个记录数组。
	game.bullets.child_entered_tree.connect(track)
	_release(heavy, target, _heavy_seed(false))
	await wait_frames(22)
	check(log.size() == 1, "failed heavy roll keeps a single throw")
	log.clear()
	_release(heavy, target, _heavy_seed(true))
	await wait_frames(30)
	var cells: Dictionary[Vector2i, bool] = {} # 每次抛投必须落向唯一的真实格。
	for throw: Dictionary in log: # 映射至本行最接近的真实种植点。
		var cell: PlantCell = game.board.nearest_cell(throw.point, throw.lane) # 以实际战场几何判定列。
		if cell != null:
			cells[cell.row_col] = true
	check(log.size() == 6 and cells.size() == 6 and cells.keys().all(func(address: Vector2i) -> bool:
		return absi(address.x - 2) <= 1 and absi(address.y - 6) <= 1), "one heavy roll creates six unique trajectories around the target")
	log.clear()
	_release(formation, target, 409)
	await wait_frames(65)
	var lanes: Array = log.map(func(throw: Dictionary): return throw.lane) # 本株和两株队友各追加一整轮。
	check(lanes.size() == 12 and lanes.count(1) == 4 and lanes.count(2) == 4 and lanes.count(3) == 4,
		"all three melons in the same column add three complete volleys")
	lower.character_death_disappear()
	await wait_frames(4)
	log.clear()
	_release(formation, target, 409)
	await wait_frames(48)
	check(log.size() == 9, "removed column member stops adding a full volley")
	upper.character_death_disappear()
	await wait_frames(4)
	log.clear()
	_release(formation, target, 409)
	await wait_frames(32)
	check(log.size() == 6, "a lone melon still adds a complete Formation volley")
	game.bullets.child_entered_tree.disconnect(track)
	await _retire([heavy, formation, unrelated], [target])

## 用自然落地的原生弹验证 [param choices] 在无星倍率下的单次 [param direct_damage] 与 [param splash_damage]。
## 当 [param control] 为真，还检查位移及两只僵尸各自已有眩晕的剩余时间。
func _impact(choices: Array[int], direct_damage: int, splash_damage: int, control: bool = false) -> void:
	var plant: Plant040MelonPult = _plant_melon(Vector2i(2, 2), choices) # 各测试沿用同一个弹道起点。
	var direct: Zombie000Base = spawn(Vector2i(2, 6)) # 瞄准行的唯一敌人。
	var splash: Zombie000Base = spawn(Vector2i(3, 6)) # 相邻行受击框进入原生溅射。
	var outside: Zombie000Base = spawn(Vector2i(0, 6)) # 超出相邻行限制。
	if [plant, direct, splash, outside].has(null):
		return
	await wait_frames(4)
	var direct_x: float = direct.global_position.x # 击退以静止目标的物理脚点为基准。
	var direct_stun: Timer # 可选的原生眩晕计时器，保持测试起始余量固定。
	var splash_stun: Timer # 使用另一余量检查加法的上限。
	if control:
		_check_attack_rate(plant, 1.4)
		direct.be_stunned(0.5)
		splash.be_stunned(2.5)
		direct_stun = direct.all_timer[Character000Base.E_TimerType.Stun]
		splash_stun = splash.all_timer[Character000Base.E_TimerType.Stun]
		direct_stun.paused = true
		splash_stun.paused = true
	var flat_damage_multiplier: float = 1.3 if choices[1] == 2 else 1.0 # 爆碎与星级的伤害百分比相加。
	var full_damage_multiplier: float = pow(AdventurePlantGrowthCatalog.ATTACK_PER_STAR, 10) + flat_damage_multiplier - 1.0 # 正式十星卡倍率。
	_release(plant, direct, _heavy_seed(false))
	await wait_frames(106)
	var actual_damage := Vector2i(30000 - direct.hp_component.curr_hp, 30000 - splash.hp_component.curr_hp) # 读取真正的生命损失。
	var expected_damage := Vector2i(roundi(direct_damage / flat_damage_multiplier * full_damage_multiplier),
		roundi(splash_damage / flat_damage_multiplier * full_damage_multiplier)) # 以未成长的基准还原出战时的伤害。
	check(actual_damage == expected_damage and outside.hp_component.curr_hp == 30000,
		"direct and splash damage for %s is %s, expected %s" % [choices, actual_damage, expected_damage])
	if control:
		check(absf(direct.global_position.x - direct_x - 20.0) <= 2.0, "direct hit knocks its target back about 20 pixels")
		check(direct.all_timer[Character000Base.E_TimerType.Stun] == direct_stun
			and splash.all_timer[Character000Base.E_TimerType.Stun] == splash_stun
			and absf(direct_stun.time_left - 1.5) < 0.05 and absf(splash_stun.time_left - 3.0) < 0.05
			and not outside.is_stunned(), "real direct and splash hits extend existing stun by one second with a 3-second cap")
	await _retire([plant], [direct, splash, outside])

## 三列共十五株同时发动重磅和列阵。逐物理步记录实际发射并确认密集弹幕仍正常命中。
func _stress_melons() -> void:
	game.card_manager.card_slot_battle.sun_value += 4500
	var formation: Array[Plant040MelonPult] = [] # 三列同步释放的真实投手。
	for column: int in range(1, 4): # 三个独立列阵同一帧争用战场发射配额。
		for row: int in range(5): # 每列五株，包括当次投手自身。
			formation.append(_plant_melon(Vector2i(row, column), [1, 2, 4, 7]))
	var central: Zombie000Base = spawn(Vector2i(2, 6)) # 重磅每组的第一弹锁定此对象。
	var adjacent: Zombie000Base = spawn(Vector2i(3, 6)) # 对相邻行继续结算真实落点。
	if formation.has(null) or not is_instance_valid(central) or not is_instance_valid(adjacent):
		return
	central.hp_component.set_spawn_max_health(1000000)
	adjacent.hp_component.set_spawn_max_health(1000000)
	await wait_frames(4)
	var first_frame: int = Engine.get_physics_frames() # 全部投手从同一帧开始计数。
	var hits: Array[int] = [] # 首次真实落点的物理步，和发射调度分开。
	central.hp_component.received_attack.connect(func(_damage: int) -> void:
		hits.append(Engine.get_physics_frames() - first_frame), CONNECT_ONE_SHOT)
	var launches: Array[Dictionary] = [] # 每颗真实子弹的行、锁定和伤害。
	var per_frame: Dictionary[int, int] = {} # 每物理帧进入正式子弹容器的数量。
	var track := func(child: Node) -> void: # 以真实入树事件记账，避免飞行和命中后漏计。
		if child is Bullet012Melon:
			var offset: int = Engine.get_physics_frames() - first_frame # 从本批首帧计算。
			per_frame[offset] = per_frame.get(offset, 0) + 1
			_observe_melon(child, launches)
	game.bullets.child_entered_tree.connect(track)
	var time_samples: Array[int] = [] # 包含调度、帧间等待和其他战场工作，单位为微秒。
	var previous_tick: int = Time.get_ticks_usec() # 首段也包含提交十五株的同步开销。
	for plant: Plant040MelonPult in formation: # 每株只触发一次发射回调，并固定为成功重磅。
		_release(plant, central, _heavy_seed(true))
	for _frame: int in range(155): # 覆盖六轮排程以及配额满时的顺延。
		await get_tree().physics_frame
		var now: int = Time.get_ticks_usec() # 与上一物理帧通知的实际墙钟间隔。
		time_samples.append(now - previous_tick)
		previous_tick = now
	game.bullets.child_entered_tree.disconnect(track)
	var final_frame: int = 0 # 最后一颗实弹应在发射窗口内到场。
	for frame: int in per_frame: # 第零帧有第一批同步弹体。
		final_frame = maxi(final_frame, frame)
	var samples: Array[int] = [] # 保留批次内无发射帧，计算整段每步负载。
	for frame: int in range(final_frame + 1): # 从整批首帧到末帧等权采样。
		samples.append(per_frame.get(frame, 0))
	samples.sort()
	time_samples.sort()
	check(launches.size() == 540 and launches.filter(func(throw: Dictionary) -> bool: return throw.target == central).size() == 90,
		"fifteen heavy formations emit all 540 physical projectiles in 90 full volleys")
	check(final_frame <= 140 and samples[-1] == 12, "per-frame cap of twelve is reached and defers all excess heavy launches")
	await wait_frames(108)
	check(not hits.is_empty() and central.hp_component.curr_hp < 1000000 and adjacent.hp_component.curr_hp < 1000000,
		"heavy formation lands real damage in both lanes")
	print("MELON_STRESS plants=15 projectiles=", launches.size(), " last_release_frame=", final_frame,
		" first_damage_frame=", hits[0] if not hits.is_empty() else -1,
		" spawn_p95_per_frame=", samples[ceili(samples.size() * 0.95) - 1], " spawn_peak_per_frame=", samples[-1],
		" physics_wall_p95_us=", time_samples[ceili(time_samples.size() * 0.95) - 1])
	await _retire(formation, [central, adjacent])

## 回收本段 [param plants]、[param zombies] 和仍在空中的原生西瓜。
func _retire(plants: Array[Plant040MelonPult], zombies: Array[Zombie000Base]) -> void:
	for plant: Plant040MelonPult in plants: # 经过真实退场，不残留列阵成员。
		if is_instance_valid(plant):
			plant.character_death_disappear()
	for zombie: Zombie000Base in zombies: # 清理本段独立的索敌状态。
		if is_instance_valid(zombie):
			zombie.retire_from_battle()
	for bullet: Node in game.bullets.get_children(): # 防止上一个用例的飞行伤害污染后续用例。
		if bullet is Bullet012Melon:
			bullet.queue_free()
	await wait_frames(4)

## 用真实攻击时钟同时展示蓄力幻影和散射列阵，由外部 Movie Maker 录制。
func _record_preview() -> void:
	var kratos: Plant040MelonPult = _plant_melon(Vector2i(1, 2), [0, 2, 5, 6]) # 本行无敌，实际向两邻行投出幻影。
	var formation: Plant040MelonPult = _plant_melon(Vector2i(3, 3), [0, 3, 4, 7]) # 与下一行的原生西瓜构成同列。
	var partner: Plant040MelonPult = _plant_melon(Vector2i(4, 3), []) # 提供真实列阵成员。
	if [kratos, formation, partner].has(null):
		return
	for address: Vector2i in [Vector2i(0, 6), Vector2i(2, 7), Vector2i(3, 7), Vector2i(4, 6)]: # 蓄力、扔瓜与实际受击均在画面内。
		spawn(address)
	await wait_frames(6)
	kratos.attack_component.enable_component(ComponentNormBase.E_IsEnableFactor.Character)
	formation.attack_component.enable_component(ComponentNormBase.E_IsEnableFactor.Character)
	await wait_frames(360)
