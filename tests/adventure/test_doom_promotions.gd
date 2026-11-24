## 回归毁灭菇转职书目、真实卡片和战场爆炸。
extends Node

## 毁灭菇在图书馆和出战卡上的物种标识。
const DOOM := CharacterRegistry.PlantType.P016DoomShroom
## 读取图书馆与研究室实际使用的候选。
const LibraryRules = preload("res://scripts/adventure/library/library_rules.gd")
## 每转两本，焚和涤只在三转，荡只在四转。
const BOOKS := [["day", "screen"], ["fear", "might"], ["cross", "purge"], ["burst", "final"]]
## 当前已记录的失败数。
var _failures: int = 0
## 正式测试战局，由每次场景启动设置。
var _game: MainGameManager
## 当前用于实际种植的卡栏槽位。
var _card: Card

## 测试节点独立于实际战场，换场后也能收集结果。
func _ready() -> void:
	get_tree().current_scene = null
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

## 报告 [param ok] 未成立的验收项 [param message]。
func _check(ok: bool, message: String) -> bool:
	if not ok:
		_failures += 1
		printerr("DOOM_FAIL ", message)
	return ok

## 使用隔离用户目录，不触碰正式玩家档案。
func _run() -> void:
	if not _check(OS.get_user_data_dir().contains("doom-audit"), "isolated user directory"):
		get_tree().quit(1)
		return
	Global.save_service.stop_autosave()
	_catalog()
	if await _open_board():
		await _day_and_crater()
		await _full_screen()
		await _fear()
		await _damage_and_boss()
		await _chains()
		await _chain_propagates()
		await _redirected_casualty()
		if OS.get_cmdline_user_args().has("--profile-doom"):
			await _profile()
	print("DOOM_RESULT=", "PASS" if _failures == 0 else "FAIL", " failures=", _failures)
	get_tree().quit(0 if _failures == 0 else 1)

## 按真实转职顺序查询，验证研究、图书馆、库存共用八本书。
func _catalog() -> void:
	var card := PlantCardInstance.new() # 只用于查询下一转，不保存到玩家库存。
	card.uid = "PC000016"
	card.plant_type = DOOM
	card.stars = 10
	for tier: int in range(1, 5): # 按四阶发展路径验证全部候选。
		var ids: Array[String] = [] # 实际从研究室选项读取的稳定 ID。
		var expected: Array[String] = [] # 按本阶规格建立期望清单。
		for suffix: String in BOOKS[tier - 1]: # 每个后缀固定归属于同一阶段。
			var id: String = "promotion_doom_" + suffix
			expected.append(id)
		for entry: Dictionary in AdventurePromotionCatalog.options(card): # 研究室实际候选。
			if ItemRegistry.has_item(str(entry.id)):
				ids.append(entry.id)
		_check(ids == expected and LibraryRules.pool(tier, DOOM) == expected, "tier %d books" % tier)
		card.set_promotion(tier, expected[0])
	_check(AdventurePromotionCatalog.is_valid_chain(card) and AdventurePromotionCatalog.next_tier(card) == 0,
		"four independent selections finish a legal chain")

## 使用同一张正式战斗卡验证独立出战快照。
func _open_board() -> bool:
	var level: ResourceLevelData = load("res://resources/level_date_resource/mode_adventure/adventure_03_pool.tres").duplicate(true) # 禁止无关的天降资源和自动出怪。
	level.is_day = true
	level.look_show_zombie = false
	level.can_choosed_card = false
	level.monster_mode = ConstLevelData.E_MonsterMode.Null
	level.is_day_sun = false
	level.start_sun = 5000
	level.prechosen_cards = [ResourceCardReference.create(ResourceCardReference.CardType.Plant, DOOM)]
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

## 用实际卡槽在 [param cell] 种下选择了 [param suffixes] 的毁灭菇。
func _plant(cell: PlantCell, suffixes: Array[String]) -> Plant016DoomShroom:
	var record := PlantCardInstance.new() # 仅供当前战斗使用的牌组实例。
	record.uid = "PC000016"
	record.plant_type = DOOM
	record.stars = 10
	for index: int in range(suffixes.size()): # 各技能必须通过完整前序转职。
		record.set_promotion(index + 1, "promotion_doom_" + suffixes[index])
	_card.plant_spawn_profile = PlantSpawnProfile.create(record.to_dict(), AdventureResearchBattleEffects.new())
	_card.set_card_cool_end()
	_card.judge_card_ready()
	_game.hand_manager._click_card(_card)
	var planted: bool = _game.hand_manager.hm_character.click_cell(cell) # 走真实占格、扣费和冷却。
	_game.hand_manager._cancel_selection()
	_check(planted, "place doom " + str(suffixes))
	return cell.plant_in_cell[CharacterRegistry.PlacePlantInCell.Norm] as Plant016DoomShroom

## 在 [param cell] 生成 [param kind]。[param health] 为测试血池，[param friendly] 走正常魅惑登记。
func _spawn(cell: PlantCell, health: int = 0, friendly: bool = false,
		kind: CharacterRegistry.ZombieType = CharacterRegistry.ZombieType.Z001Norm) -> Zombie000Base:
	var manager: ZombieManager = _game.zombie_manager # 真实分行登记及伤害入口。
	var lane: int = cell.combat_lane # 保持当前战场几何。
	var zombie: Zombie000Base = manager.create_norm_zombie(kind, manager.all_zombie_rows[lane], {
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

## 仅撤除本用例生成的实体及坑洞。
func _clear() -> void:
	for boss: ZB000Base in _game.zombie_manager.get_living_bosses(): # 测试间不沿用 Boss 伤害或行为。
		boss.queue_free()
	for zombie: Zombie000Base in _game.zombie_manager.all_zombies_1d.duplicate(): # 退场会改变原登记列表。
		if is_instance_valid(zombie):
			zombie.retire_from_battle()
	for cell: PlantCell in _game.board.cells(): # 原生铲除和弹坑撤销避免再次引爆。
		for plant: Plant000Base in cell.living_plants():
			plant.be_shovel_kill()
		if is_instance_valid(cell.crater):
			cell.crater.queue_free()
			cell.delete_crater_update_plant_cell_data()
	await _frames(3)

## [param plant] 真正清醒时从原生亡语引爆，留出物理监听更新时间。
func _explode(plant: Plant016DoomShroom) -> void:
	plant.sleep_component.wake_permanently()
	await _frames(3)
	plant.character_death()
	await _frames(4)

## 昼经自然引信消耗但无坑。无转职白天等待原生唤醒后保留弹坑。
func _day_and_crater() -> void:
	var cell: PlantCell = _at(0, 3) # 两种分支依次使用同一可种植位置。
	var target: Zombie000Base = _spawn(_at(0, 4)) # 落在原生首爆范围。
	var plant: Plant016DoomShroom = _plant(cell, ["day"])
	if is_instance_valid(plant):
		_check(not plant.is_sleeping and is_equal_approx(_card.cool_time, _card._registry_cooldown - 2.0), "daytime wake and -2 cooldown")
		await _frames(68)
		_check(not is_instance_valid(target) or target.is_death, "day naturally explodes")
		_check(not is_instance_valid(cell.crater), "day does not create crater")
	await _clear()
	target = _spawn(_at(0, 4))
	plant = _plant(cell, [])
	if is_instance_valid(plant):
		await _frames(60)
		_check(is_instance_valid(plant) and plant.is_sleeping and not target.is_death, "vanilla remains asleep during day")
		await _explode(plant)
		_check(is_instance_valid(cell.crater), "vanilla creates native crater after wake")
	await _clear()

## 尽覆盖原生矩形之外的可见普通敌人，对友军和视口之外保留边界。
func _full_screen() -> void:
	var far: Zombie000Base = _spawn(_at(5, 8)) # 与原株相隔多行多列。
	var friend: Zombie000Base = _spawn(_at(1, 4), 10000, true) # 友军仍可见，但不属可击中的阵营。
	var offscreen: Zombie000Base = _spawn(_at(0, 8), 10000) # 真实战场内的待入场敌人。
	var view: Rect2 = _game.get_viewport_rect() # 用实际视口坐标置于最右边之外。
	offscreen.global_position.x = (_game.get_canvas_transform().affine_inverse() * Vector2(view.end.x + 250.0, 0.0)).x
	var plant: Plant016DoomShroom = _plant(_at(0, 1), ["screen"])
	if is_instance_valid(plant):
		await _explode(plant)
		_check(not is_instance_valid(far) or far.is_death, "screen reaches far visible lane and column")
		_check(friend.hp_component.curr_hp == 10000 and offscreen.hp_component.curr_hp == 10000, "screen excludes allies and offscreen unit")
	await _clear()

## 惧从正常命中启动四种公共状态，五秒后只保留永久效果。
func _fear() -> void:
	var target: Zombie000Base = _spawn(_at(0, 4), 12000) # 确保承受首爆和五秒灼烧后仍存活。
	var plant: Plant016DoomShroom = _plant(_at(0, 3), ["day", "fear"])
	if is_instance_valid(plant):
		var direct: int = plant.bomb_component.resolved_damage() # 惧的脆弱在首爆计算之后施加。
		_check(is_equal_approx(_card.cool_time, _card._registry_cooldown), "day and fear cooldown offsets combine")
		await _explode(plant)
		var hp: HpComponent = target.hp_component # 后续持续伤害也走真实生命组件。
		var fear := target.get_node_or_null(NodePath(AdventureFearEffect.NODE_NAME)) as AdventureFearEffect
		var burn := target.get_node_or_null(NodePath(AdventureBurnEffect.NODE_NAME)) as AdventureBurnEffect
		_check(hp.curr_hp == 12000 - direct, "fear effects do not multiply their own first hit")
		_check(hp.brittleness_stacks == 100 and is_equal_approx(hp.total_degradation_fraction(), 0.3), "fear gives 100 brittleness and 30% degradation")
		_check(fear != null and burn != null and fear._remaining > 4.8 and burn._remaining > 4.8
			and target.move_component.is_fleeing(), "fear and burn both begin at five seconds")
		await _frames(306)
		_check(not target.move_component.is_fleeing() and burn != null and burn._remaining <= 0.0
			and hp.brittleness_stacks == 100, "only the two timed effects expire")
	await _clear()

## 灭、涤先加算，四转荡最后乘到各自的普通和僵王伤害。
func _damage_and_boss() -> void:
	var enemy: Zombie000Base = _spawn(_at(0, 4), 100000) # 停在爆心附近核对扣血。
	var boss: ZB002BlackGeneral = await _boss(_at(1, 4)) # 不借用普通僵尸模拟 Boss 抗性。
	var plant: Plant016DoomShroom = _plant(_at(0, 3), ["day", "might", "purge", "final"])
	if is_instance_valid(plant) and is_instance_valid(boss):
		var base: int = plant.bomb_component.bomb_value # 标准数值由正式场景读取。
		var ordinary: int = plant.battle_damage(base * 3) * 2 # +100% 与 +100% 为基础加算。
		var boss_damage: int = roundi(plant.battle_damage(roundi(base * 1.4)) * 1.3) # Boss 独立 +20% +20%，再乘 1.3。
		var before: int = boss.hp_component.curr_hp # 实际 Boss 在各次攻击中固定位置。
		var boss_areas: Array[Area2D] = [boss.hurt_box_component.hurt_box_real] # 共用爆炸入口仍遵守调用者传入的原有上限。
		CombatExplosion.resolve_plant_blast(boss_areas, 0, -1, 63, 1800, true, null, 360)
		_check(boss.hp_component.curr_hp == before - 360, "existing capped blast retains its pre-resistance cap")
		before = boss.hp_component.curr_hp
		_check(is_equal_approx(_card.cool_time, _card._registry_cooldown + 2.0), "might and purge cooldown stack")
		await _explode(plant)
		_check(is_instance_valid(enemy) and enemy.hp_component.curr_hp == 100000 - ordinary, "ordinary base additions and final double")
		_check(boss.hp_component.curr_hp == before - boss_damage, "boss base additions and final 30%")
	await _clear()

## 缩小本用例 [param plant] 的物理首爆到种植格，只让预期的第一只尸体启动连锁。
func _narrow_main(plant: Plant016DoomShroom) -> void:
	var collider := plant.bomb_component.area_2d_bomb.get_node(^"CollisionShape2D") as CollisionShape2D # 与生产环境共用同一个首爆入口。
	var shape := RectangleShape2D.new() # 独立测试形状，防止污染同资源的其他实例。
	shape.size = Vector2(22.0, 70.0)
	collider.shape = shape

## 焚和空共用首爆来源，但具有不同几何且各自命中一次，同一 Boss 可分别承伤。
func _chains() -> void:
	var cell: PlantCell = _at(0, 4) # 首爆、首个尸体和两种连锁的中心位置。
	var seed_enemy: Zombie000Base = _spawn(cell) # 只有这一普通僵尸在首爆里。
	var horizontal: Zombie000Base = _spawn(_at(0, 7), 25000) # 只有横臂能触及。
	var vertical: Zombie000Base = _spawn(_at(5, 4), 25000) # 只有纵臂能触及。
	var both: Zombie000Base = _spawn(_at(0, 5), 25000) # 横臂与九宫格各伤一次。
	var diagonal: Zombie000Base = _spawn(_at(1, 5), 25000) # 九宫格内而十字外。
	var outside: Zombie000Base = _spawn(_at(1, 6), 25000) # 两种范围都在其外。
	var boss: ZB002BlackGeneral = await _boss(_at(0, 5))
	var plant: Plant016DoomShroom = _plant(cell, ["day", "might", "cross", "burst"])
	if is_instance_valid(plant) and is_instance_valid(boss):
		_narrow_main(plant)
		var base: int = plant.bomb_component.bomb_value # 灭已选，派生按毁灭菇完整主爆的比例。
		var half: int = roundi(plant.battle_damage(base * 2) * 0.5)
		var each_boss: int = roundi(plant.battle_damage(roundi(base * 1.2)) * 0.05)
		var boss_before: int = boss.hp_component.curr_hp # 该位置同时在两个派生几何内。
		_check(is_equal_approx(_card.cool_time, _card._registry_cooldown + 4.0), "three +2 cooldown branches sum with day")
		await _explode(plant)
		await _frames(8)
		_check(not is_instance_valid(seed_enemy) or seed_enemy.is_death, "seed dies to the primary hit")
		_check(horizontal.hp_component.curr_hp == 25000 - half and vertical.hp_component.curr_hp == 25000 - half, "cross independently reaches both arms")
		_check(diagonal.hp_component.curr_hp == 25000 - half and outside.hp_component.curr_hp == 25000, "3x3 has exact diagonal and edge")
		_check(both.hp_component.curr_hp == 25000 - 2 * half and boss.hp_component.curr_hp == boss_before - 2 * each_boss,
			"both effects hit once, boss takes only five percent per hit")
	await _clear()

## 次级爆炸的真实新死者也能传递，但每名死者只生成各自的一次效果。
func _chain_propagates() -> void:
	var cell: PlantCell = _at(0, 4) # 只对子测试的起点使用首爆。
	_spawn(cell)
	var next: Zombie000Base = _spawn(_at(0, 7)) # 远处低血量僵尸能被第一条横臂击杀。
	var final_target: Zombie000Base = _spawn(_at(1, 8), 100000) # 只由第二名死者的九宫格触及。
	var plant: Plant016DoomShroom = _plant(cell, ["day", "might", "cross", "burst"])
	if is_instance_valid(plant):
		_narrow_main(plant)
		var half: int = plant.bomb_component.resolved_damage() # 灭双倍乘以派生一半。
		await _explode(plant)
		await _frames(6)
		_check(not is_instance_valid(next) or next.is_death, "secondary reaches the next casualty")
		_check(is_instance_valid(final_target) and final_target.hp_component.curr_hp == 100000 - half, "true secondary casualty propagates exactly once")
	await _clear()

## 由原生保护者代伤致死时，火焰纵臂从真实死者的位置开始。
func _redirected_casualty() -> void:
	var cell: PlantCell = _at(0, 4) # 首爆碰到的是保护对象。
	var protected: Zombie000Base = _spawn(cell, 100000) # 必须在连锁横臂后仍存活。
	var protector: Zombie000Base = _spawn(_at(0, 5), 0, false, CharacterRegistry.ZombieType.Z003Cone)
	var other_column: Zombie000Base = _spawn(_at(5, 4), 100000) # 原碰撞对象所在列没有死亡。
	var real_column: Zombie000Base = _spawn(_at(5, 5), 100000) # 真正死亡者所在列应烧到这里。
	var health := protected.hp_component as HpComponentZombie # 走原生可接管的保护关系。
	health.damage_transfer.set_source(protector.get_instance_id(), protector, 120.0)
	var plant: Plant016DoomShroom = _plant(cell, ["day", "might", "cross"])
	if is_instance_valid(plant):
		_narrow_main(plant)
		var half: int = plant.bomb_component.resolved_damage() # 灭翻倍后的一半为未加算值。
		await _explode(plant)
		_check(not is_instance_valid(protector) or protector.is_death, "protector is the true primary casualty")
		_check(health.curr_hp == 100000 - half and other_column.hp_component.curr_hp == 100000
			and real_column.hp_component.curr_hp == 100000 - half, "chain uses redirected casualty's true column")
	await _clear()

## 同一画幅的一批真实死亡验证分帧及所有派生伤害，耗时仅用于诊断。
func _profile() -> void:
	const KILLS: int = 120 # 仅在明确启动性能用例时使用固定高密度。
	var cell: PlantCell = _at(0, 4) # 相同爆心可揭示重叠的物理查询和表现。
	for _index: int in range(KILLS):
		_spawn(cell)
	var health: int = 10000000 # 十星按 1.2 的十次方成长，计数者必须能接收全部连锁。
	var target: Zombie000Base = _spawn(cell, health)
	var hp := target.hp_component as HpComponentZombie # 统计真实生命入口收到的每一击。
	var per_frame: Dictionary[int, int] = {} # 同时观察重复和实际分帧。
	hp.received_attack.connect(func(_amount: int) -> void:
		var frame: int = Engine.get_physics_frames() # 选择当前物理帧。
		per_frame[frame] = per_frame.get(frame, 0) + 1)
	var plant: Plant016DoomShroom = _plant(cell, ["screen", "might", "cross", "burst"])
	if is_instance_valid(plant):
		plant.sleep_component.wake_permanently()
		await _frames(4)
		var direct: int = plant.battle_damage(plant.bomb_component.bomb_value * 2) # 首爆加两份半伤的精确期望。
		var expected: int = health - direct - 2 * KILLS * roundi(direct * 0.5)
		var started: int = Time.get_ticks_usec() # 从原生死亡触发计算首段耗时。
		plant.character_death()
		var first: int = Time.get_ticks_usec() - started
		var pause_hp: int = hp.curr_hp # 开始首批之后仍有确认待处理的伤害。
		_check(pause_hp > expected, "dense chain is pending before menu pause")
		TreePauseManager.start_tree_pause(TreePauseManager.E_PauseFactor.Menu)
		await get_tree().create_timer(0.15, true).timeout
		_check(hp.curr_hp == pause_hp, "menu pause freezes pending damage")
		TreePauseManager.end_tree_pause(TreePauseManager.E_PauseFactor.Menu)
		for _frame: int in range(240): # 不超出四秒游戏时间。
			if not is_instance_valid(hp) or hp.curr_hp <= expected:
				break
			await get_tree().physics_frame
		var count: int = 0 # 总承伤次数必须等于主爆和每名死者的两次连锁。
		for hits: int in per_frame.values():
			count += hits
		_check(count == 2 * KILLS + 1 and is_instance_valid(hp) and hp.curr_hp == expected, "dense chain credits every casualty exactly once per effect")
		_check(per_frame.size() > 1, "dense chain distributes work across frames")
		print("DOOM_LOAD casualties=", KILLS, " received_hits=", count, " frames=", per_frame.size(),
			" first_us=", first, " finished_us=", Time.get_ticks_usec() - started)
	await _clear()
