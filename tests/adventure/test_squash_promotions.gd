## 核对窝瓜书目及真实出战的压砸、续种、召唤和落地效果。
extends Node

## 窝瓜在正常卡槽和图书馆中的物种标识。
const SQUASH := CharacterRegistry.PlantType.P018Squash
## 图书馆读取实际转换池。
const LibraryRules = preload("res://scripts/adventure/library/library_rules.gd")
## 按四阶依次读取统一目录的两个候选。
const BOOKS := [["cheap", "rapid"], ["shock", "resentment"], ["king", "training"], ["quake", "leader"]]
## 独立场景累积的失败次数。
var _failures: int = 0
## 正式测试战局，由每次开局建立。
var _game: MainGameManager
## 实测用卡的普通卡槽卡片。
var _card: Card

## 测试控制节点在暂停和换场时仍存活。
func _ready() -> void:
	get_tree().current_scene = null
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

## 报告 [param ok] 未满足的验收项 [param message]。
func _check(ok: bool, message: String) -> bool:
	if not ok:
		_failures += 1
		printerr("SQUASH_FAIL ", message)
	return ok

## 验证只访问临时测试用户目录。
func _run() -> void:
	if not _check(OS.get_user_data_dir().contains("squash-audit"), "isolated user directory"):
		get_tree().quit(1)
		return
	Global.save_service.stop_autosave()
	_catalog()
	if await _open_board():
		await _cheap_and_rapid()
		await _control()
		await _retry_training()
		await _training_cap()
		await _occupied_retry()
		await _leader()
		await _king()
		await _king_without_targets()
		if OS.get_cmdline_user_args().has("--profile-squash"):
			await _profile()
	print("SQUASH_RESULT=", "PASS" if _failures == 0 else "FAIL", " failures=", _failures)
	get_tree().quit(0 if _failures == 0 else 1)

## 正式研究与图书馆、库存识别同样的四阶八本书。
func _catalog() -> void:
	var record := PlantCardInstance.new() # 查询用的独立测试卡。
	record.uid = "PC000018"
	record.plant_type = SQUASH
	record.stars = 10
	for tier: int in range(1, 5): # 验证上一阶使用后发布正确下一阶。
		var expected: Array[String] = [] # 所有候选都能进入实际图书馆池。
		for suffix: String in BOOKS[tier - 1]: # 稳定技能书后缀。
			expected.append("promotion_squash_" + suffix)
		var ids: Array[String] = [] # 从研究系统读取，库存必须认可。
		for book: Dictionary in AdventurePromotionCatalog.options(record):
			if ItemRegistry.has_item(book.id):
				ids.append(book.id)
		_check(ids == expected and LibraryRules.pool(tier, SQUASH) == expected, "tier %d books" % tier)
		record.set_promotion(tier, expected[0])
	_check(AdventurePromotionCatalog.is_valid_chain(record) and AdventurePromotionCatalog.next_tier(record) == 0, "valid four-tier chain")

## 使用同一张正式战斗卡验证独立出战快照。
func _open_board() -> bool:
	var level: ResourceLevelData = load("res://resources/level_date_resource/mode_adventure/adventure_03_pool.tres").duplicate(true) # 禁止无关的天降资源和自动出怪。
	level.is_day = true
	level.look_show_zombie = false
	level.can_choosed_card = false
	level.monster_mode = ConstLevelData.E_MonsterMode.Null
	level.is_day_sun = false
	level.start_sun = 5000
	level.prechosen_cards = [ResourceCardReference.create(ResourceCardReference.CardType.Plant, SQUASH)]
	Global.game_para = level
	if not _check(get_tree().change_scene_to_file("res://scenes/main/MainGame02Back.tscn") == OK, "open the actual board"):
		return false
	for _frame: int in range(360): # 有界等待正式卡片准备。
		await get_tree().physics_frame
		_game = Global.main_game
		if is_instance_valid(_game) and _game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME:
			var slots: CardSlotBattle = _game.card_manager.card_slot_battle # 原生卡栏与当前原生交易状态。
			if slots != null and not slots.curr_cards.is_empty() and slots.curr_cards[0].card_context == Card.CardContext.Battle:
				_card = slots.curr_cards[0]
				return true
	return _check(false, "battle card became ready")

## [param row] 和 [param column] 都使用从零开始的真实棋盘地址。
func _at(row: int, column: int) -> PlantCell:
	return _game.board.cell_at(Vector2i(row, column))

## 用实际卡槽在 [param cell] 种下 [param uid] 选择了 [param suffixes] 的窝瓜。
func _plant(cell: PlantCell, suffixes: Array[String], uid: String = "PC000018") -> Plant018Squash:
	var record := PlantCardInstance.new() # 仅供当前战斗使用的牌组实例。
	record.uid = uid
	record.plant_type = SQUASH
	record.stars = 10
	for index: int in range(suffixes.size()): # 各技能必须通过完整前序转职。
		record.set_promotion(index + 1, "promotion_squash_" + suffixes[index])
	_card.plant_spawn_profile = PlantSpawnProfile.create(record.to_dict(), AdventureResearchBattleEffects.new())
	_card.set_card_cool_end()
	_card.judge_card_ready()
	_game.hand_manager._click_card(_card)
	var planted: bool = _game.hand_manager.hm_character.click_cell(cell) # 走真实占格、扣费和冷却。
	_game.hand_manager._cancel_selection()
	_check(planted, "place squash " + str(suffixes))
	return cell.plant_in_cell[CharacterRegistry.PlacePlantInCell.Norm] as Plant018Squash

## 在 [param cell] 生成普通僵尸。[param health] 为测试血池，[param friendly] 走正常魅惑登记。
func _spawn(cell: PlantCell, health: int = 0, friendly: bool = false) -> Zombie000Base:
	var manager: ZombieManager = _game.zombie_manager # 真实分行登记及伤害入口。
	var lane: int = cell.combat_lane # 保持当前战场几何。
	var zombie: Zombie000Base = manager.create_norm_zombie(CharacterRegistry.ZombieType.Z001Norm, manager.all_zombie_rows[lane], {
		Zombie000Base.E_ZInitAttr.Lane: lane,
		Zombie000Base.E_ZInitAttr.CurrZombieRowType: cell.get_spawn_terrain_type(),
		Zombie000Base.E_ZInitAttr.ParticipatesNaturalRefresh: false,
		Zombie000Base.E_ZInitAttr.StartsHypnotized: friendly,
	}, cell.get_spawn_global_position())
	if _check(is_instance_valid(zombie), "spawn real zombie"):
		zombie.move_component.update_move_factor(true, MoveComponent.E_MoveFactor.IsDisable)
		zombie.drop_item_component.disable_component(ComponentNormBase.E_IsEnableFactor.Death)
		if health > 0:
			zombie.hp_component.max_hp = health
			zombie.hp_component.curr_hp = health
	return zombie

## 在 [param cell] 放置并打开真实黑将军的受击窗口，冻结夹具的演出与移动。
func _boss(cell: PlantCell) -> ZB002BlackGeneral:
	var manager: ZombieManager = _game.zombie_manager # 通过常规 Boss 生成及注册。
	var at: Vector2 = manager.zombie_boss_root.to_local(cell.get_spawn_global_position()) # 该入口需要容器内坐标。
	var boss: ZB002BlackGeneral = manager.try_create_boss_from_card(CharacterRegistry.ZombieBossType.ZB002BlackGeneral, at)
	await _frames(3)
	if _check(is_instance_valid(boss), "spawn real boss"):
		boss.set_physics_process(false)
		boss.visual.player.pause()
		boss._set_invulnerable(false)
		boss.global_position = cell.get_spawn_global_position()
	return boss

## 等待固定物理帧数 [param count]，所有用例都有外层进程超时。
func _frames(count: int) -> void:
	for _frame: int in range(count): # 固定物理帧与游戏定时器遵守同一战斗时钟。
		await get_tree().physics_frame

## 仅撤除本用例生成的实体及掉落。
func _clear() -> void:
	for boss: ZB000Base in _game.zombie_manager.get_living_bosses(): # 测试间不沿用 Boss 伤害或行为。
		boss.queue_free()
	for zombie: Zombie000Base in _game.zombie_manager.all_zombies_1d.duplicate(): # 退场会改变原登记列表。
		if is_instance_valid(zombie):
			zombie.retire_from_battle()
	for cell: PlantCell in _game.board.cells(): # 清除实际占用，不触发愤恨。
		for plant: Plant000Base in cell.living_plants():
			plant.be_shovel_kill()
	for sun: Node in _game.suns.get_children(): # 各用例的掉落计数独立。
		sun.queue_free()
	await _frames(3)

## 在 [param limit] 个物理帧内检查 [param condition]，避免原生动画失效时悬挂。
func _until(condition: Callable, limit: int = 170) -> bool:
	for _frame: int in range(limit):
		if condition.call():
			return true
		await get_tree().physics_frame
	return condition.call()

## 返回本测试中当前仍在场的阳光价值。
func _sun_value() -> int:
	var total: int = 0 # 统计实际可拾取物品而非余额。
	for item: Node in _game.suns.get_children():
		if item is Sun:
			total += item.sun_value
	return total

## 廉价作物走真实扣费、原生起跳和实际击杀，急速支援只修改冷却。
func _cheap_and_rapid() -> void:
	var cell: PlantCell = _at(0, 3) # 正常陆地格，方便验证无特例的原生攻击动画。
	var target: Zombie000Base = _spawn(cell)
	var slots: CardSlotBattle = _game.card_manager.card_slot_battle # 记录成功用卡前的实际余额。
	var before: int = slots.sun_value
	var plant: Plant018Squash = _plant(cell, ["cheap"])
	if plant != null:
		_check(before - slots.sun_value == maxi(0, _card._registry_sun_cost - 25), "cheap charges 25 less")
		var observed: WeakRef = weakref(target) # 目标可在真的被压死时同帧离树。
		_check(await _until(func() -> bool:
			var enemy := observed.get_ref() as Zombie000Base
			return enemy == null or enemy.is_death), "native targeting and jump produce actual crush")
		_check(_sun_value() == 25, "one confirmed kill drops exactly 25 sun")
	await _clear()
	plant = _plant(cell, ["rapid"])
	if plant != null:
		_check(is_equal_approx(_card.cool_time, _card._registry_cooldown * 0.5), "rapid halves actual card cooldown")
	await _clear()

## 由 [param plant] 在真实碰撞范围内完成一次普通落地。
func _land(plant: Plant018Squash) -> void:
	await _frames(4)
	if is_instance_valid(plant):
		plant.squash_all_area_zombie()

## 震撼与地震叠加震幅及眩晕时间，只作用于各自真实行列范围。
func _control() -> void:
	var center: PlantCell = _at(0, 3) # 原生砸击落点。
	_spawn(center)
	var inner: Zombie000Base = _spawn(_at(1, 4), 100000) # 同时落在震撼和地震内。
	var outer: Zombie000Base = _spawn(_at(1, 5), 100000) # 只受地震。
	var far: Zombie000Base = _spawn(_at(1, 6), 100000) # 两层范围均不可触及。
	var x: Vector3 = Vector3(inner.global_position.x, outer.global_position.x, far.global_position.x)
	var width: float = _game.board.local_pitch(_at(1, 4)).x # 用真实格宽换算，避免硬编码平面坐标。
	var plant: Plant018Squash = _plant(center, ["rapid", "shock", "training", "quake"])
	if plant != null:
		await _land(plant)
		var inner_timer: Timer = inner.all_timer[Character000Base.E_TimerType.Stun] # 眩晕沿用单一原生时钟。
		var outer_timer: Timer = outer.all_timer[Character000Base.E_TimerType.Stun]
		_check(is_instance_valid(inner_timer) and inner_timer.time_left > 4.9
			and is_instance_valid(outer_timer) and outer_timer.time_left > 2.9 and outer_timer.time_left <= 3.0
			and not far.is_stunned(), "stacked 5 seconds, quake 3 seconds, exterior unaffected")
		await _frames(28)
		_check(absf(inner.global_position.x - x.x - 2.5 * width) < 1.0 and absf(outer.global_position.x - x.y - width) < 1.0
			and absf(far.global_position.x - x.z) < 0.1, "stacked 2.5 tiles and quake 1 tile")
	await _clear()

## 返回 [param cell] 的正式窝瓜占用，用于区别原件与愤恨生成的多个实例。
func _at_squash(cell: PlantCell) -> Plant018Squash:
	return cell.plant_in_cell.get(CharacterRegistry.PlacePlantInCell.Norm) as Plant018Squash

## 多次实际失败可递归，复用同卡训练。实际击杀则终止递归。
func _retry_training() -> void:
	var cell: PlantCell = _at(0, 3) # 愤恨始终返回原种植格。
	var target: Zombie000Base = _spawn(_at(0, 4), 260000) # 压砸落地远离原格，仍应从原种植格重生。
	var plant: Plant018Squash = _plant(cell, ["rapid", "resentment", "training"], "PC000180")
	if plant == null:
		return
	var slots: CardSlotBattle = _game.card_manager.card_slot_battle # 复制不被计作玩家用卡。
	var sun: int = slots.sun_value
	for index: int in range(2):
		var id: int = plant.get_instance_id() # 每一轮都必须生成真实的新实例。
		plant.global_position.x = target.global_position.x # 模拟原生跳到旁边一格，保留原始占格身份。
		await _land(plant)
		_check(_at_squash(cell) == plant, "replacement waits for native removal")
		plant.character_death()
		if not _check(await _until(func() -> bool:
			var current: Plant018Squash = _at_squash(cell)
			return is_instance_valid(current) and current.get_instance_id() != id, 22), "real retry after failure"):
			await _clear()
			return
		plant = _at_squash(cell)
		var expected: int = roundi(plant.battle_damage(1000) * (1.2 + 0.2 * index)) # 原件 100%，复制品依次 120%、140%。
		_check(plant.promotion_damage(1000) == expected and slots.sun_value == sun, "recursive training and no extra card cost")
	target.hp_component.curr_hp = 250 # 下一次真的压死它，不能再触发递归。
	plant.global_position.x = target.global_position.x
	await _land(plant)
	plant.character_death()
	await _frames(9)
	_check(_at_squash(cell) == null, "ordinary kill stops resentment")
	await _clear()

## 换一张卡的 UID 独立开始训练。连续成功放置始终限制在伤害 300%。
func _training_cap() -> void:
	var cell: PlantCell = _at(0, 3) # 一个合法点足以检查按实际种植累计。
	for index: int in range(12):
		var plant: Plant018Squash = _plant(cell, ["rapid", "resentment", "training"], "PC000181")
		if plant == null:
			break
		var expected: int = roundi(plant.battle_damage(1000) * minf(3.0, 1.0 + 0.2 * index))
		_check(plant.promotion_damage(1000) == expected, "training per UID and capped placement %d" % index)
		plant.be_shovel_kill()
		await _frames(2)
	await _clear()

## 等候生成时如果玩家先占格，愤恨不覆盖已种下的新植株。
func _occupied_retry() -> void:
	var cell: PlantCell = _at(0, 3) # 原件死亡后替身才参加下一次分帧生成。
	var plant: Plant018Squash = _plant(cell, ["rapid", "resentment"])
	if plant != null:
		await _land(plant)
		plant.character_death()
		var replacement: Plant000Base = cell.create_plant(CharacterRegistry.PlantType.P001PeaShooterSingle, false, false)
		await _frames(6)
		_check(is_instance_valid(replacement) and cell.plant_in_cell[CharacterRegistry.PlacePlantInCell.Norm] == replacement,
			"retry follows normal occupancy and cannot displace another plant")
	await _clear()

## 领袖属于整轮攻击，星级提升普通爆炸，僵王单次封顶300，Boss 命中可结束愤恨。
func _leader() -> void:
	var cell: PlantCell = _at(0, 3) # Native 压砸区域外但在领袖 3×3 内。
	var ordinary: Zombie000Base = _spawn(_at(1, 4), 100000)
	var boss: ZB002BlackGeneral = await _boss(_at(1, 4)) # 斜对角避开原生落地的小矩形。
	var plant: Plant018Squash = _plant(cell, ["rapid", "resentment", "training", "leader"], "PC000182")
	if plant != null and is_instance_valid(boss):
		var expected: int = plant.battle_damage(1000) # 首领有很大的跨行受击框，单次爆炸限额必须区别于原生直击。
		var direct: int = plant.battle_damage(plant.attack_value)
		var boss_hits: Array[int] = [] # 原始压砸和爆炸分别经过 Boss 的承伤入口。
		boss.hp_component.combat_attack_received.connect(func(amount: int) -> void: boss_hits.append(amount))
		await _land(plant)
		_check(ordinary.hp_component.curr_hp == 100000 - expected and not boss_hits.is_empty()
			and boss_hits[-1] == 300 and (boss_hits.size() == 1 or boss_hits == [direct, 300]),
			"leader applies rank scaling and caps only the single boss explosion")
		plant.character_death()
		await _frames(8)
		_check(_at_squash(cell) == null, "a real boss hit ends resentment")
	await _clear()

## 窝瓜王每枚都有独立时点与半伤。首批优先两个实敌，Boss 每次540，最后只爆炸一次。
func _king() -> void:
	var cell: PlantCell = _at(0, 3) # 主召唤格与敌人选校验点。
	var target: Zombie000Base = _spawn(_at(1, 4)) # 首次被落地杀死后不重复索取尸体。
	var boss: ZB002BlackGeneral = await _boss(cell)
	var events: Array[Dictionary] = [] # 顺序及时间来自真实承伤事件。
	var normal_hp := target.hp_component as HpComponentZombie
	normal_hp.received_attack.connect(func(amount: int) -> void:
		events.append({"boss": false, "damage": amount, "frame": Engine.get_physics_frames()}))
	if is_instance_valid(boss):
		boss.hp_component.combat_attack_received.connect(func(amount: int) -> void:
			events.append({"boss": true, "damage": amount, "frame": Engine.get_physics_frames()}))
	var plant: Plant018Squash = _plant(cell, ["rapid", "resentment", "king", "leader"])
	if plant != null and is_instance_valid(boss):
		var half: int = roundi(plant.battle_damage(plant.attack_value) * 0.5) # 六次按实际模型一半伤害。
		var cap: int = floori(plant.attack_value * 0.3)
		if _check(await _until(func() -> bool: return not events.is_empty(), 160), "native jump cue triggers the first staggered landing"):
			var before_pause: int = events.size()
			TreePauseManager.start_tree_pause(TreePauseManager.E_PauseFactor.Menu)
			await get_tree().create_timer(0.25, true).timeout
			_check(events.size() == before_pause, "menu pause freezes falling sequence")
			TreePauseManager.end_tree_pause(TreePauseManager.E_PauseFactor.Menu)
			_check(await _until(func() -> bool: return events.size() >= 7, 150), "six landings and one post-attack blast: %s" % str(events))
			await _frames(15)
			var ordinary_hits: int = 0 # 所有直接命中都按实际接受攻击次数核对。
			var spaced: bool = true
			if events.size() == 7:
				for index: int in range(6): # 尾部第七项应为单次四转。
					var event: Dictionary = events[index]
					if index > 0 and event.frame - events[index - 1].frame < 8:
						spaced = false
					if not event.boss:
						ordinary_hits += 1
						_check(event.damage == half and index < 2, "half damage and unused live cell preferred")
					else:
						_check(event.damage == cap, "king boss damage capped on each individual smash")
				_check(events[6].boss and events[6].damage == 300, "leader resolves once after last junior squash")
			_check(events.size() == 7 and ordinary_hits == 1 and spaced and _at_squash(cell) == null, "stagger, retarget and end conditions")
	await _clear()

## 发招后目标消失时仍按真实棋盘随机选择六次落点，空场的落点优先不重复。
func _king_without_targets() -> void:
	var cell: PlantCell = _at(0, 3) # 角行只有六个合法格，验证候选不越界。
	var plant: Plant018Squash = _plant(cell, ["rapid", "shock", "king"])
	if plant != null:
		plant.jump_up_start()
		var observed: WeakRef # 结算完毕后允许该节点正常释放。
		for child: Node in _game.bombs.get_children():
			if child is AdventureSquashAttack:
				observed = weakref(child)
		if _check(observed != null, "empty sequence creates actual falling views"):
			_check(await _until(func() -> bool:
				var runtime := observed.get_ref() as AdventureSquashAttack
				return runtime != null and runtime._used_cells.size() == 6, 120), "no enemy still generates six distinct random valid landings")
			await _frames(30)
	await _clear()

## 覆盖高密度同格压砸。运行结果用于比较同步批次和阳光生成的预算。
func _profile() -> void:
	const COUNT: int = 120 # 固定规模，防止测试损耗本机日常战斗环境。
	var cell: PlantCell = _at(0, 4) # 集中命中是单次视觉热点。
	var kills_by_frame: Dictionary[int, int] = {} # 统计每个批次真实死亡数，不把加载场景时间算进受击。
	for _index: int in range(COUNT):
		var victim: Zombie000Base = _spawn(cell)
		victim.signal_character_death.connect(func() -> void:
			var frame: int = Engine.get_physics_frames()
			kills_by_frame[frame] = kills_by_frame.get(frame, 0) + 1)
		if (_index + 1) % 12 == 0:
			await _frames(1) # 夹具生成也分帧，避免十几种场景资源初始化被误记成落地耗时。
	await _frames(8) # 先稳定实体与碰撞，再测同格爆发。
	var target: Zombie000Base = _spawn(cell, 2000000) # 重点接收六次独立伤害而不会死亡。
	var hp := target.hp_component as HpComponentZombie
	var frames: Array[int] = []
	hp.received_attack.connect(func(_amount: int) -> void: frames.append(Engine.get_physics_frames()))
	var plant: Plant018Squash = _plant(cell, ["cheap", "resentment", "king"])
	if plant != null:
		plant.jump_up_start()
		var peak_frame_us: int = 0 # 只采样开始召唤后的实际帧间隔，包含同帧引擎开销。
		var frame_start: int = Time.get_ticks_usec()
		var checked_pause: bool = false # 在实际伤害批次进行中额外验证暂停边界。
		for _frame: int in range(185):
			if frames.size() >= 6 and _sun_value() == 25 * COUNT:
				break
			await get_tree().physics_frame
			var now: int = Time.get_ticks_usec()
			peak_frame_us = maxi(peak_frame_us, now - frame_start)
			frame_start = now
			if not checked_pause and not kills_by_frame.is_empty():
				checked_pause = true
				var partial: int = _sun_value() # 暂停前已经兑换的实际阳光值。
				TreePauseManager.start_tree_pause(TreePauseManager.E_PauseFactor.Menu)
				await get_tree().create_timer(0.14, true).timeout
				_check(partial > 0 and partial < COUNT * 25 and _sun_value() == partial,
					"menu suspends already queued dense crush and sun creation")
				TreePauseManager.end_tree_pause(TreePauseManager.E_PauseFactor.Menu)
				frame_start = Time.get_ticks_usec()
		_check(frames.size() == 6 and frames[5] - frames[0] >= 50 and _sun_value() == 25 * COUNT,
			"dense squash keeps six staggered hits and every kill's loot")
		var peak_kills: int = int(kills_by_frame.values().max()) if not kills_by_frame.is_empty() else 0
		_check(kills_by_frame.size() > 1 and peak_kills <= AdventureSquashAttack.WORK_ITEMS_PER_FRAME,
			"dense impact batches casualty and sun creation")
		print("SQUASH_LOAD victims=", COUNT, " drops_value=", _sun_value(), " landings=", frames.size(),
			" kill_frames=", kills_by_frame.size(), " peak_kills_per_frame=", peak_kills, " peak_frame_us=", peak_frame_us)
	await _clear()
