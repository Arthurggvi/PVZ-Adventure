## 三线射手四阶转职的目录、事务与实际战场回归。
extends Node

## 本套回归的真实卡片与四阶候选。
const PLANT := CharacterRegistry.PlantType.P019ThreePeater
const HIGH := "promotion_threepeater_high_energy"
const FLOOD := "promotion_threepeater_flood"
const ASSAULT := "promotion_threepeater_assault"
const KINETIC := "promotion_threepeater_kinetic"
## 三转鏖战的研究与战场标识。
const SIEGE := "promotion_threepeater_siege"
## 三转催折的研究与战场标识。
const SUNDER := "promotion_threepeater_sunder"
## 四转封锁的研究与战场标识。
const LOCKDOWN := "promotion_threepeater_lockdown"
## 四转终结的研究与战场标识。
const FINISHER := "promotion_threepeater_finisher"
## 图书馆的真实候选查询。
const LibraryRules = preload("res://scripts/adventure/library/library_rules.gd")
## 实际战场和由卡槽创建的手持卡。
var _game: MainGameManager
var _card: Card
## 单次套件的断言数量。
var _failures: int = 0

## 独立运行节点可跨场景等待。
func _ready() -> void:
	get_tree().current_scene = null
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

## 记录 [param description] 失败后继续其他独立案例。
func _check(ok: bool, description: String) -> bool:
	if not ok:
		_failures += 1
		printerr("THREEPEA_FAIL ", description)
	return ok

## 静态注册和真实草坪共用同一隔离进程。
func _run() -> void:
	if not _check(OS.get_user_data_dir().contains("threepeater-promotions"), "isolated user data"):
		get_tree().quit(1)
		return
	Global.save_service.stop_autosave()
	_catalog()
	_research()
	if await _open():
		_flood()
		await _laser()
		await _laser_entry_hits()
		await _laser_edge()
		await _kinetic()
		await _advanced_laser()
		await _sunder()
		await _laser_sunder()
		await _finisher()
		if OS.get_cmdline_user_args().has("--stress"):
			await _stress(false)
			await _stress(true)
		if OS.get_cmdline_user_args().has("--laser-stress"):
			await _laser_stress(false)
		if OS.get_cmdline_user_args().has("--late-stress"):
			await _stress(false, true)
			await _stress(true, true)
			await _laser_stress(true)
	if await _open(true):
		await _snow_wall()
	if is_instance_valid(_game):
		_game.queue_free() # 让动画、天气及战局快照在测试退出前按正常流程释放。
		await _wait(4)
	print("THREEPEA_RESULT=", "PASS" if _failures == 0 else "FAIL", " failures=", _failures)
	get_tree().quit(0 if _failures == 0 else 1)

## 注册、互斥与所有合法路线均从生产目录读取。
func _catalog() -> void:
	for id: String in [HIGH, FLOOD, ASSAULT, KINETIC, SIEGE, SUNDER, LOCKDOWN, FINISHER]: # 四阶都必须进物品目录。
		_check(ItemRegistry.has_item(id), "inventory book " + id)
	var card: PlantCardInstance = _record("", "") # 未转职时一转有两项。
	_check(AdventurePromotionCatalog.options(card).map(func(b: Dictionary): return b.id) == [HIGH, FLOOD], "first tier options")
	_check(LibraryRules.pool(1, PLANT) == [HIGH, FLOOD] and LibraryRules.pool(2, PLANT) == [ASSAULT, KINETIC], "library has both tiers")
	card.promotion_1 = HIGH
	_check(AdventurePromotionCatalog.options(card).map(func(b: Dictionary): return b.id) == [ASSAULT], "high energy hides kinetic")
	card.promotion_2 = KINETIC
	_check(not AdventurePromotionCatalog.is_valid_chain(card), "forged incompatible chain rejected")
	_check(AdventurePromotionCatalog.effects(card).events.is_empty(), "incompatible chain grants no attack effects")
	card.promotion_1 = FLOOD
	card.promotion_2 = ""
	_check(AdventurePromotionCatalog.options(card).map(func(b: Dictionary): return b.id) == [ASSAULT, KINETIC], "flood supports both choices")
	_check(LibraryRules.pool(3, PLANT) == [SIEGE, SUNDER] and LibraryRules.pool(4, PLANT) == [LOCKDOWN, FINISHER], "late books enter the library")
	card = _advanced_card(HIGH, ASSAULT, SUNDER, "")
	_check(AdventurePromotionCatalog.options(card).map(func(b: Dictionary): return b.id) == [LOCKDOWN], "high energy hides finisher")
	card.promotion_4 = FINISHER
	_check(not AdventurePromotionCatalog.is_valid_chain(card) and AdventurePromotionCatalog.effects(card).events.is_empty(),
		"forged high energy and finisher grant no battle powers")
	card.promotion_1 = FLOOD
	card.promotion_2 = KINETIC
	_check(AdventurePromotionCatalog.is_valid_chain(card), "finisher can follow kinetic")

## 走研究服务的扣费与存档事务；互斥项的报价及提交都必须拒绝。
func _research() -> void:
	var state := AdventureState.new() # 独立内存状态，不读取用户卡库。
	AdventureQuestService.record_event(state, "stage_cleared", "zombie_island.lawn/normal", "2026-11-24")
	state.quests.records["first_expedition"].status = "claimed"
	var inventory := AdventureInventoryService.new(state) # 使用正式库存接口。
	var wallet := GlobalGameState.new() # 不连接实际的全局存档钱包。
	wallet.adventure_state = state
	wallet.coin_value = 20000
	var service := AdventureResearchService.new(state, inventory, wallet, func() -> bool: return true) # 在隔离内存中提交。
	var uid: String = inventory.add_card(PLANT, 10) # 星级满足四个转职阶数。
	for id: String in [HIGH, ASSAULT, KINETIC, SIEGE, LOCKDOWN, FINISHER]: # 充足库存不能越过互斥条件。
		inventory.add_item(id, 1)
	_check(service.execute("promotion", {"uid": uid, "book_id": HIGH}).ok, "official first-tier transaction")
	var blocked := {"uid": uid, "book_id": KINETIC} # 模拟UI或数据绕开候选后仍试图提交。
	_check(not service.quote("promotion", blocked).ready and not service.execute("promotion", blocked).ok
		and wallet.coin_value == 15000 and inventory.get_item_count(KINETIC) == 1, "excluded branch makes no inventory or wallet changes")
	_check(service.execute("promotion", {"uid": uid, "book_id": ASSAULT}).ok
		and wallet.coin_value == 10000 and inventory.get_item_count(ASSAULT) == 0, "legal second tier consumes once")
	_check(service.execute("promotion", {"uid": uid, "book_id": SIEGE}).ok and wallet.coin_value == 5000, "official third-tier transaction")
	var fourth := {"uid": uid, "book_id": FINISHER} # 高能已冻结，终结不能偷偷成交。
	_check(not service.quote("promotion", fourth).ready and not service.execute("promotion", fourth).ok
		and wallet.coin_value == 5000 and inventory.get_item_count(FINISHER) == 1, "late conflict leaves money and book in place")
	_check(service.execute("promotion", {"uid": uid, "book_id": LOCKDOWN}).ok and wallet.coin_value == 0, "official fourth-tier transaction")
	wallet.free()

## 按 [param first] 和 [param second] 建立可冻结的研究卡记录。
func _record(first: String, second: String, uid: String = "PC000019") -> PlantCardInstance:
	var card := PlantCardInstance.new() # 测试记录不写正式档案。
	card.uid = uid
	card.plant_type = PLANT
	card.stars = 7
	card.promotion_1 = first
	card.promotion_2 = second
	return card

## 为 [param first]、[param second]、[param third] 和 [param fourth] 建立后两阶测试资料。
func _advanced_card(first: String, second: String, third: String, fourth: String) -> PlantCardInstance:
	var card: PlantCardInstance = _record(first, second) # 接续同一份前两阶冻结资料。
	card.stars = 10
	card.promotion_3 = third
	card.promotion_4 = fourth
	return card

## 复用正式泳池、原生卡槽与购物结算。
func _open(snow: bool = false) -> bool:
	var level_name: String = "adventure_01_day" if snow else "adventure_03_pool" # 雪山没有泳池背景节点。
	var level: ResourceLevelData = load("res://resources/level_date_resource/mode_adventure/%s.tres" % level_name).duplicate(true) # 本次隔离配置。
	level.look_show_zombie = false
	level.can_choosed_card = false
	level.monster_mode = ConstLevelData.E_MonsterMode.Null
	level.is_day_sun = false
	level.start_sun = 99999
	level.prechosen_cards = [ResourceCardReference.create(ResourceCardReference.CardType.Plant, PLANT)]
	Global.game_para = level
	var path: String = "res://scenes/main/MainGame02Back.tscn" # 默认实测泳池。
	if snow:
		path = "res://scenes/adventure/snow_mountains_battle.tscn"
		level.board_definition = load("res://resources/adventure/stages/boards/wonderland_snow_mountains.tres")
		level.terrain_rows.clear()
		level.look_show_zombie = false
		level.can_choosed_card = false
	if not _check(get_tree().change_scene_to_file(path) == OK, "load battle"):
		return false
	for _frame: int in range(360): # 按仿真帧有界等待。
		await get_tree().physics_frame
		_game = Global.main_game
		if is_instance_valid(_game) and _game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME:
			var slots: CardSlotBattle = _game.card_manager.card_slot_battle # 真实出战卡栏。
			if slots != null and not slots.curr_cards.is_empty() and slots.curr_cards[0].card_context == Card.CardContext.Battle:
				_card = slots.curr_cards[0]
				return true
	return _check(false, "battle card ready")

## 经正常手持、预检、扣费和冷却使用 [param record]，返回点击结果。
func _buy(cell: PlantCell, record: PlantCardInstance) -> bool:
	_card.plant_spawn_profile = PlantSpawnProfile.create(record.to_dict(), AdventureResearchBattleEffects.new())
	_card.set_card_cool_end()
	_card.judge_card_ready()
	_game.hand_manager._click_card(_card)
	var result: bool = _game.hand_manager.hm_character.click_cell(cell) # 原生玩家种植入口。
	_game.hand_manager._cancel_selection()
	return result

## 验证原实例、同卡检查、封顶、扣费、满血及净化。
func _flood() -> void:
	var cell: PlantCell = _game.board.cell_at(Vector2i(1, 2)) # 泳池中的陆地格。
	var record: PlantCardInstance = _record(FLOOD, ASSAULT) # 陷阵自带一发，洪流计入总上限。
	if not _check(_buy(cell, record), "initial flood placement"):
		return
	var plant: Plant019ThreePeater = cell.plant_in_cell[CharacterRegistry.PlacePlantInCell.Norm] # 之后所有叠种必须保留此实例。
	var original_max: int = plant.hp_component.max_hp # 包含冻结星级修正。
	var slots: CardSlotBattle = _game.card_manager.card_slot_battle # 核对失败不扣阳光。
	var before: int = slots.sun_value # 叠种前真实余额。
	plant.hp_component.curr_hp -= 50
	(plant.hp_component as HpComponentPlant).grant_bonus_armor(37)
	plant.hp_component.apply_degradation(0.35)
	_check(plant.apply_hunter_ice_shell(), "actual persistent ice shell")
	_check(AdventurePlantNegativeEffects.apply(plant, AdventurePlantNegativeEffects.Kind.STUN, 0, 8.0), "actual stun")
	_check(AdventurePlantNegativeEffects.apply(plant, AdventurePlantNegativeEffects.Kind.BURN, 0, 8.0), "actual burn")
	_check(not _buy(cell, _record(FLOOD, ASSAULT, "PC000020")) and slots.sun_value == before, "different card consumes nothing")
	_check(not _buy(cell, _record(HIGH, ASSAULT)) and slots.sun_value == before, "card lacking flood consumes nothing")
	if not _check(_buy(cell, record), "same card reinforcements"):
		return
	_check(cell.plant_in_cell[CharacterRegistry.PlacePlantInCell.Norm] == plant and cell.living_plants().size() == 1, "same entity and occupancy")
	_check(slots.sun_value == before - _card.sun_cost and _card._is_cooling,
		"stack fee=%d expected=%d cooling=%s" % [before - slots.sun_value, _card.sun_cost, _card._is_cooling])
	_check(plant.hp_component.max_hp == roundi(original_max * 1.5) and plant.hp_component.curr_hp == plant.hp_component.max_hp, "50 percent base health and full heal")
	_check(plant.hp_component.degradation_fraction == 0.0 and not plant.has_ice_shell() and not plant.is_cold_frozen(), "cold and degradation purged")
	_check(plant.action_rate() > 0.0 and (plant.hp_component as HpComponentPlant).bonus_armor == 37, "stun purged, positive armor retained")
	_check(not plant.get_children().any(func(child: Node) -> bool: return child is AdventurePeriodicDamageEffect and child.is_effect_active()), "periodic damage purged")
	for _stack: int in range(9): # 初始两发加十次洪流，恰好达到十二发。
		_check(_buy(cell, record), "stack before maximum")
	before = slots.sun_value
	_check(not _buy(cell, record) and slots.sun_value == before and not _card._is_cooling, "cap rejects without payment")
	_check(plant.hp_component.curr_hp == original_max * 6 and plant.hp_component.max_hp == original_max * 6, "health grows from the base, not exponentially")
	_check(plant.has_method("shots_per_ray") and plant.call("shots_per_ray") == 12, "twelve actual shots per ray")
	plant.be_shovel_kill()

## 共用实际僵尸与普通伤害协议测试贯穿和连续脉冲。
func _laser() -> void:
	var cell: PlantCell = _game.board.cell_at(Vector2i(1, 0)) # 障碍以外的长射区。
	if not _check(_buy(cell, _record(HIGH, ASSAULT)), "plant high energy"):
		return
	var plant: Plant019ThreePeater = cell.plant_in_cell[CharacterRegistry.PlacePlantInCell.Norm] # 保留真实攻击动画入口。
	plant.attack_component.detect_component.disable_component(ComponentNormBase.E_IsEnableFactor.Character)
	_check(is_equal_approx(plant.speed_factor_product(), 1.5), "assault grants fifty percent attack speed")
	var near: Zombie000Base = _zombie(1, 3) # 正中路前排。
	var far: Zombie000Base = _zombie(1, 6) # 同一条光束的后排。
	var flank: Zombie000Base = _zombie(0, 5) # 支线上的靶位。
	if near != null and far != null and flank != null:
		var near_hp: int = near.hp_component.curr_hp # 三个目标保留实际本体血量。
		var far_hp: int = far.hp_component.curr_hp
		var flank_hp: int = flank.hp_component.curr_hp
		await _wait(3)
		plant.attack_component._shoot_bullet()
		_check_laser_routes(plant)
		await _wait(4)
		var first_damage: int = near_hp - near.hp_component.curr_hp # 第一脉冲需在时序上独立。
		_check(first_damage > 0 and far_hp - far.hp_component.curr_hp == first_damage and flank_hp - flank.hp_component.curr_hp == first_damage, "first pulse pierces and follows both rows")
		_check(is_equal_approx(near.move_component._move_rate, 0.7), "assault affects only movement by thirty percent")
		await _wait(28)
		_check(near_hp - near.hp_component.curr_hp == first_damage * 2, "assault adds a delayed laser pulse")
		await _wait(60)
		_check(is_equal_approx(near.move_component._move_rate, 1.0), "slow expires after last impact")
		for zombie: Zombie000Base in [near, far, flank]: # 清除测试目标。
			zombie.retire_from_battle()
	plant.be_shovel_kill()
	await _wait(3)

## 复核 [param plant] 的每路实际出光点、入行方向以及演出随动画贴住炮口。
func _check_laser_routes(plant: Plant019ThreePeater) -> void:
	var muzzle_paths: Array[NodePath] = [
		^"Body/BodyCorrect/Anim_head3/Node2D/ThreePeater_mouth3/LaserMuzzle",
		^"Body/BodyCorrect/Anim_head2/Node2D/ThreePeater_mouth2/LaserMuzzle",
		^"Body/BodyCorrect/Anim_head1/Node2D/ThreePeater_mouth1/LaserMuzzle",
	] # 植物现有三个可动口型，按画面从上往下对应攻击行。
	var count: int = 0 # 记录本脉冲真实出现的路线。
	for node: Node in _game.bullets.get_children(): # 已由原生组件实际发射。
		if node.get_script() == null or node.get_script().resource_path != "res://scripts/bullet/three_pea_laser.gd":
			continue
		count += 1
		var beam := node as Bullet000NormBase # 同时验证一次真实命中所用的路径。
		var ray: int = beam.lane - plant.lane + 1 # 上、本、下分别为0、1、2。
		var muzzle := plant.get_node_or_null(muzzle_paths[ray]) as Marker2D # 口型内部锚点。
		var path_value: Variant = beam.get("_path") # 已冻结并用于命中的真实路线。
		if not _check(muzzle != null and path_value is PackedVector2Array,
				"laser ray %d uses the matching animated muzzle and one route" % ray):
			continue
		var path: PackedVector2Array = path_value # 局部路线从炮口出发。
		if not _check(path.size() >= 2 and beam.to_global(path[0]).is_equal_approx(muzzle.global_position), "path starts inside its own bore"):
			continue
		var ordered: bool = true # 逐段不能反向，也不能从炮口后方多画一截。
		for index: int in range(1, path.size()): # 路线与最终演出共用这个前进顺序。
			ordered = ordered and path[index].x > path[index - 1].x
		_check(ordered and is_equal_approx(path[-1].y, path[-2].y), "continuous forward-only route joins its horizontal lane")
		_check(ray == 1 or (path.size() > 4 and not is_equal_approx(path[0].y, path[-1].y)), "outer rays bend into their own lanes")
		var original: Vector2 = muzzle.position # 模拟开火后炮口的真实动画位移。
		muzzle.position += Vector2(3.0, -4.0)
		var drawn: PackedVector2Array = beam.call("_visual_path") # 只变换开头的显示，命中与终点已冻结。
		_check(beam.to_global(drawn[0]).is_equal_approx(muzzle.global_position)
			and drawn[-1].is_equal_approx(path[-1]), "recoil stays attached without moving the resolved endpoint")
		muzzle.position = original
	_check(count == 3, "one real beam per open lane")

## 真实命中跟随入行曲线，凸包遮住但光束没有经过的位置不能受击。
func _laser_entry_hits() -> void:
	var cell: PlantCell = _game.board.cell_at(Vector2i(1, 0)) # 给邻行完整的入行距离。
	if not _check(_buy(cell, _record(HIGH, "")), "place plant for entry contact"):
		return
	var plant: Plant019ThreePeater = cell.plant_in_cell[CharacterRegistry.PlacePlantInCell.Norm] # 真正的激光原株。
	plant.attack_component.detect_component.disable_component(ComponentNormBase.E_IsEnableFactor.Character)
	plant.attack_component.animation_tree.active = false
	var struck: Zombie000Base = _zombie(0, 2) # 两个真实角色各持有一个独立受击轮廓。
	var decoy: Zombie000Base = _zombie(0, 3) # 位于斜向光束的下方。
	if struck != null and decoy != null:
		await _wait(3)
		var origin: Vector2 = plant.attack_component.laser_muzzles[0].global_position # 上炮口。
		var rows: Array[ZombieRow] = _game.zombie_manager.all_zombie_rows # 邻行实际像素高差。
		var lane_shift: float = rows[0].zombie_create_position.global_position.y \
			- rows[1].zombie_create_position.global_position.y # 上行相对本行的偏移。
		var rise: float = plant.attack_component.laser_muzzles[1].global_position.y + lane_shift - origin.y # 光束要抵达的轨道高度。
		var middle_x: float = origin.x + maxf(54.0, absf(rise) * 1.24) * 0.5 # 入行弯道的中点横坐标。
		var outline := RectangleShape2D.new() # 缩小轮廓，使两目标与路线的关系明确。
		outline.size = Vector2(6.0, 6.0)
		var direct: CollisionShape2D = struck.hurt_box_component.hurt_box_real.get_node(^"CollisionShape2D") # 曲线上。
		var gap: CollisionShape2D = decoy.hurt_box_component.hurt_box_real.get_node(^"CollisionShape2D") # 凸包内的空白处。
		direct.shape = outline
		gap.shape = outline
		direct.global_position = Vector2(middle_x, origin.y + rise * 0.50)
		gap.global_position = Vector2(middle_x, origin.y + rise * 0.16)
		var before_direct: int = struck.hp_component.curr_hp # 真正扣除的本体生命。
		var before_gap: int = decoy.hp_component.curr_hp # 空白处不会被当成横向残段命中。
		await _wait(3)
		plant.attack_component._shoot_bullet()
		_check(struck.hp_component.curr_hp < before_direct and decoy.hp_component.curr_hp == before_gap,
			"curved beam hits the real strip and excludes the broadphase corner")
		struck.retire_from_battle()
		decoy.retire_from_battle()
	plant.be_shovel_kill()
	await _wait(15)

## 边路每发跟随自身路径；两条合流脉冲与邻行配额互不重复。
func _laser_edge() -> void:
	var cell: PlantCell = _game.board.cell_at(Vector2i(0, 0)) # 首行无上方路径。
	if not _check(_buy(cell, _record(HIGH, ASSAULT)), "place edge laser"):
		return
	var plant: Plant019ThreePeater = cell.plant_in_cell[CharacterRegistry.PlacePlantInCell.Norm] # 原株的真实攻击组件。
	plant.attack_component.detect_component.disable_component(ComponentNormBase.E_IsEnableFactor.Character)
	var main: Zombie000Base = _zombie(0, 7) # 同路四次脉冲。
	var side: Zombie000Base = _zombie(1, 7) # 有效邻路两次。
	if main != null and side != null:
		main.hp_component.set_spawn_max_health(2000)
		side.hp_component.set_spawn_max_health(2000)
		await _wait(3)
		plant.attack_component._shoot_bullet()
		await _wait(49)
		var main_damage: int = 2000 - main.hp_component.curr_hp # 原生伤害透过真实命中。
		var side_damage: int = 2000 - side.hp_component.curr_hp # 对照相邻路线。
		_check(side_damage > 0 and main_damage == side_damage * 2, "edge folds pulses without extra adjacent damage")
		main.retire_from_battle()
		side.retire_from_battle()
	plant.be_shovel_kill()
	await _wait(3)

## 动能距离成长由远近两个真实命中比较，并确认飞行效果组件实际出现。
func _kinetic() -> void:
	var cell: PlantCell = _game.board.cell_at(Vector2i(1, 0)) # 保持直线有足够的加速距离。
	if not _check(_buy(cell, _record(FLOOD, KINETIC)), "plant kinetic"):
		return
	var plant: Plant019ThreePeater = cell.plant_in_cell[CharacterRegistry.PlacePlantInCell.Norm] # 同样从原手持入口种下。
	plant.attack_component.detect_component.disable_component(ComponentNormBase.E_IsEnableFactor.Character)
	var near: Zombie000Base = _zombie(0, 2) # 邻行近点，弹道已经入行。
	var far: Zombie000Base = _zombie(1, 8) # 本行远点，可达到速度上限。
	if near != null and far != null:
		var near_hp: int = near.hp_component.curr_hp # 本体比较不会混入不同护甲。
		var far_hp: int = far.hp_component.curr_hp
		await _wait(3)
		plant.attack_component._shoot_bullet()
		await _wait(3)
		var free_lane: BulletLinear000Base # 无目标的第三条弹道用于测速度上限。
		for node: Node in _game.bullets.get_children(): # 同次实际发出的动能弹。
			if node.has_method("kinetic_progress") and node.lane == 2:
				free_lane = node
				break
		_check(is_instance_valid(free_lane) and free_lane.speed > 300.0 and free_lane.speed < 600.0, "kinetic accelerates on the real battle")
		await _wait(92)
		_check(is_instance_valid(free_lane) and is_equal_approx(free_lane.speed, 600.0)
			and free_lane.call("kinetic_progress") == 1.0
			and free_lane._modify_impact_damage(100, null) == 200, "kinetic caps at 1.5 seconds and double damage")
		await _wait(38)
		var damage: int = far_hp - far.hp_component.curr_hp # 同一次齐射的远端命中。
		_check(damage > near_hp - near.hp_component.curr_hp and near.hp_component.curr_hp < near_hp, "faster long flight deals greater damage")
		for zombie: Zombie000Base in [near, far]: # 用正式退场接口清理。
			zombie.retire_from_battle()
	plant.be_shovel_kill()

## 鏖战、封锁与陷阵共同放大真实高能齐射，并沿贯穿光束给前后两个敌人附加状态。
func _advanced_laser() -> void:
	var plant: Plant019ThreePeater = _late_plant(1, _advanced_card(HIGH, ASSAULT, SIEGE, LOCKDOWN)) # 全合法四阶激光。
	if plant == null:
		return
	_check(plant.shots_per_ray() == 4 and is_equal_approx(plant.speed_factor_product(), 2.8), "four shots and 180 percent added attack speed")
	var near: Zombie000Base = _zombie(1, 4) # 同路前排。
	var far: Zombie000Base = _zombie(1, 7) # 同路后排。
	if near != null and far != null:
		near.hp_component.set_spawn_max_health(4000)
		far.hp_component.set_spawn_max_health(4000)
		var count: Array[int] = [0] # 子弹节点观察器只计真实的中行脉冲。
		var observe := func(node: Node) -> void:
			if node is Bullet000NormBase and node.lane == 1:
				count[0] += 1
		_game.bullets.child_entered_tree.connect(observe)
		await _wait(4)
		plant.attack_component._shoot_bullet()
		var timer: Timer = near.all_timer[Character000Base.E_TimerType.Stun] # 原生状态负责有效期和其他控制通道。
		_check(near.is_stunned() and far.is_stunned() and timer != null and is_equal_approx(timer.time_left, 0.3), "lockdown stuns front and rear for 0.3 seconds")
		_check(is_equal_approx(near.hp_component.degradation_fraction, 0.3) and is_equal_approx(far.hp_component.degradation_fraction, 0.3), "siege degrades all beam hits")
		await _wait(54)
		_check(count[0] == 4 and not near.is_stunned() and not far.is_stunned(), "advanced laser launches four pulses and stun expires")
		_check(is_equal_approx(near.hp_component.degradation_fraction, 0.3), "repeated siege hits do not stack past thirty percent")
		_game.bullets.child_entered_tree.disconnect(observe)
		near.retire_from_battle()
		far.retire_from_battle()
	plant.be_shovel_kill()
	await _wait(4)

## 催折采用真实弹体命中，验证距离逐级上升、六次封顶、换目标重计、免疫和屏幕边界。
func _sunder() -> void:
	var plant: Plant019ThreePeater = _late_plant(1, _advanced_card(FLOOD, ASSAULT, SUNDER, "")) # 普通多发豌豆。
	if plant == null:
		return
	var target: Zombie000Base = _zombie(1, 4) # 主要连击目标。
	var other: Zombie000Base = _zombie(1, 5) # 同行新目标用来中断累积。
	var armor: Zombie000Base = _zombie(1, 6, 0.0, CharacterRegistry.ZombieType.Z007ScreenDoor) # 真实二类防具。
	var vehicle: Zombie000Base = _zombie(1, 7, 0.0, CharacterRegistry.ZombieType.Z013Zamboni) # 真实载具。
	if target != null and other != null and armor != null and vehicle != null:
		var pitch: float = _game.board.local_pitch(plant.plant_cell).x # 一格的实际世界长度。
		target.hp_component.set_spawn_max_health(4000)
		for hit: int in range(1, 8): # 七次同目标的首次命中。
			var origin: Vector2 = target.global_position # 每次在可用空间测试，不让前面的位移挤到屏幕边缘。
			var dx: float = _strike(plant, target) # 真正的水平移动量。
			_check(absf(dx - pitch * mini(hit, 6) / 6.0) < 0.25, "sunder strike %d reaches the expected fraction of a cell" % hit)
			target.global_position = origin
		_check(absf(_strike(plant, other) - pitch / 6.0) < 0.25 and absf(_strike(plant, target) - pitch / 6.0) < 0.25,
			"a different first target resets the lane's streak")
		var hp := armor.hp_component as HpComponentZombie # 让这次真实命中恰好打碎二类防具。
		hp.curr_hp_armor2 = 1
		_check(is_zero_approx(_strike(plant, armor)) and hp.curr_hp_armor2 <= 0, "the armor-breaking hit cannot knock back")
		_check(is_zero_approx(_strike(plant, vehicle)), "vehicle has no knockback")
		var box: CollisionShape2D = target.hurt_box_component.hurt_box_real.get_node(^"CollisionShape2D") # 实际实体轮廓。
		var right: float = BloomerangFlightQuery.screen_rect(target).end.x # 当前可见屏幕的真实世界右界。
		target.global_position.x += right - 3.0 - (box.global_transform * box.shape.get_rect()).end.x
		var limited: float = _strike(plant, target) # 剩余可见空间仅3像素。
		_check(limited >= 0.0 and limited <= 3.02 and (box.global_transform * box.shape.get_rect()).end.x <= right + 0.02,
			"sunder cannot push the combat silhouette beyond the screen")
	for zombie: Zombie000Base in [target, other, armor, vehicle]: # 统一撤走用例目标。
		if is_instance_valid(zombie):
			zombie.retire_from_battle()
	plant.be_shovel_kill()
	await _clear_test_bullets()

## 将 [param plant] 本次齐射中的原生本行豌豆交给真实 [param target]，返回本次位移。
func _strike(plant: Plant019ThreePeater, target: Zombie000Base) -> float:
	for bullet: Node in _game.bullets.get_children(): # 每次只保留这一轮用于验收的真实弹体。
		bullet.queue_free()
	var before: float = target.global_position.x # 命中前水平坐标。
	plant.attack_component._shoot_bullet()
	for child: Node in _game.bullets.get_children(): # 原生炮口即时发出第一批。
		if child is BulletLinear000Base and child.lane == target.lane and not child.is_queued_for_deletion():
			child.attack_once(target)
			return target.global_position.x - before
	_check(false, "native bullet available for strike")
	return 0.0

## 贯穿激光按路径先命中前排，后排仍扣血但催折仅由首次命中触发。
func _laser_sunder() -> void:
	var plant: Plant019ThreePeater = _late_plant(1, _advanced_card(HIGH, ASSAULT, SUNDER, "")) # 激光也允许选催折。
	if plant == null:
		return
	var far: Zombie000Base = _zombie(1, 7) # 特意先登记后排，避免出怪顺序掩盖排序错误。
	var near: Zombie000Base = _zombie(1, 4) # 光束实际先到达的敌人。
	if near != null and far != null:
		var front_x: float = near.global_position.x # 前排移动基准。
		var rear_x: float = far.global_position.x # 后排移动基准。
		var rear_hp: int = far.hp_component.curr_hp # 后排贯穿伤害基准。
		await _wait(4)
		plant.attack_component._shoot_bullet()
		_check(near.global_position.x > front_x and is_equal_approx(far.global_position.x, rear_x)
			and far.hp_component.curr_hp < rear_hp, "only the first real laser contact pushes")
		near.retire_from_battle()
		far.retire_from_battle()
	plant.be_shovel_kill()
	await _clear_test_bullets()

## 终结按每条实际路线计数，验证边路合流、只强化末发、十二倍封顶及动能兼容。
func _finisher() -> void:
	var main: Plant019ThreePeater = _late_plant(0, _advanced_card(FLOOD, ASSAULT, SIEGE, FINISHER)) # 边路逻辑每路三发。
	if main == null:
		return
	await _check_finish_burst(main, 3, 6, 6)
	for _stack: int in range(9): # 把同一株加强至普通弹路上限。
		_check(main.reinforce("PC000019"), "reinforce finisher to the shot cap")
	await _check_finish_burst(main, 12, 24, 12)
	main.be_shovel_kill()
	await _clear_test_bullets()
	var kinetic: Plant019ThreePeater = _late_plant(0, _advanced_card(FLOOD, KINETIC, SIEGE, FINISHER)) # 动能的速度倍率独立于终结。
	if kinetic != null:
		await _check_finish_burst(kinetic, 2, 4, 4)
		kinetic.be_shovel_kill()
	await _clear_test_bullets()

## 从 [param plant] 实际齐射中获取两行发数；[param side_count] 和 [param main_count] 是实际数量，
## [param main_boost] 为本行末发应有的倍数。
func _check_finish_burst(plant: Plant019ThreePeater, side_count: int, main_count: int, main_boost: int) -> void:
	var main: Array[float] = [] # 本行各颗弹发射时冻结的倍率。
	var side: Array[float] = [] # 邻行各颗弹发射时冻结的倍率。
	var highlighted: Array[bool] = [true] # 检查普通弹与动能弹都只标出真实尾弹。
	var mark := func(node: Node) -> void:
		if node is BulletLinear000Base:
			var list: Array[float] = main if node.lane == plant.lane else side # 按实际攻击行统计。
			var factor: float = node.source_damage_multiplier / plant.battle_damage_multiplier # 此发的独立终结倍率。
			highlighted[0] = highlighted[0] and node.finisher_highlight == (factor > 1.0)
			list.append(factor)
	_game.bullets.child_entered_tree.connect(mark)
	plant.attack_component._shoot_bullet()
	await _wait(69)
	_game.bullets.child_entered_tree.disconnect(mark)
	_check(main.size() == main_count and side.size() == side_count, "finisher keeps every native and folded bullet")
	_check(main.count(1.0) == main_count - 1 and main.back() == float(main_boost)
		and side.count(1.0) == side_count - 1 and side.back() == float(side_count) and highlighted[0],
		"only the last real emission in each lane gets the capped multiplier and highlight")
	if plant.attack_component.kinetic_enabled and DisplayServer.get_name() != "headless":
		var warm_trails: int = 0 # 两条真实路径的末发动能弹应上传暖色材质参数。
		for node: Node in _game.bullets.get_children(): # 路线观察器记录发射，这里检查就绪后的实际材质。
			if node is BulletLinear000Base and node.finisher_highlight and node.has_method("kinetic_progress"):
				warm_trails += int(node.get_instance_shader_parameter(&"final_round") == true)
		_check(warm_trails == 2, "only the two terminal kinetic projectiles use warm trails")
	await _clear_test_bullets()

## 在 [param row] 用真实手持协议安置 [param card]，屏蔽自动索敌以隔离该轮发射。
func _late_plant(row: int, card: PlantCardInstance) -> Plant019ThreePeater:
	var cell: PlantCell = _game.board.cell_at(Vector2i(row, 0)) # 真正的战斗种植格。
	if not _check(_buy(cell, card), "place advanced threepeater"):
		return null
	var plant: Plant019ThreePeater = cell.plant_in_cell[CharacterRegistry.PlacePlantInCell.Norm] # 保留原生发射动画与碰撞。
	plant.attack_component.detect_component.disable_component(ComponentNormBase.E_IsEnableFactor.Character)
	return plant

## 等待真实子弹节点完成释放，为下一用例恢复干净的命中条件。
func _clear_test_bullets() -> void:
	for bullet: Node in _game.bullets.get_children(): # 只清本场用例生成的战斗弹体。
		bullet.queue_free()
	await _wait(4)

## 正式雪山的三条光束必须在真实坡面前终止，近敌正常受击，后排留在截断范围外。
func _snow_wall() -> void:
	var plant_cell: PlantCell = _game.board.cell_at(Vector2i(2, 0)) # 第一段长坡左侧。
	if not _check(plant_cell != null and _game.main_game_slope != null, "snow board with authored slopes") \
			or not _check(_buy(plant_cell, _record(HIGH, ASSAULT)), "plant on the snow ramp"):
		return
	var plant: Plant019ThreePeater = plant_cell.plant_in_cell[CharacterRegistry.PlacePlantInCell.Norm] # 正常种下的实际炮口。
	plant.attack_component.detect_component.disable_component(ComponentNormBase.E_IsEnableFactor.Character)
	var near: Zombie000Base = _zombie(2, 0, 42.0) # 在实测交点前的同格前半段，仍有暴露受击轮廓。
	var beyond: Zombie000Base = _zombie(2, 9) # 第二段坡之后的高台。
	if near == null or beyond == null:
		return
	var before_near: int = near.hp_component.curr_hp # 墙前本体值。
	var before_beyond: int = beyond.hp_component.curr_hp # 墙后本体值。
	await _wait(4)
	plant.attack_component._shoot_bullet()
	var row_beams: int = 0 # 几何与真实伤害应使用同样的裁切。
	for node: Node in _game.bullets.get_children(): # 只取当前实际放出的三道。
		var beam := node as Bullet000NormBase # 真实攻击对象，而非测试绘图。
		if beam == null or beam.get_script().resource_path != "res://scripts/bullet/three_pea_laser.gd":
			continue
		row_beams += 1
		var path: PackedVector2Array = beam.get("_path") # 同时用于绘制和判伤的冻结路线。
		if not _check(path.size() >= 2 and bool(beam.get("_blocked")), "snow beam is clipped"):
			continue
		var endpoint: Vector2 = beam.to_global(path[-1]) # 实际绘制的终点。
		_check(_laser_tip_hits_slope(plant, beam, endpoint) and endpoint.x < beyond.global_position.x,
			"snow beam lane %d ends on real wall at %s" % [beam.lane, endpoint])
	_check(row_beams == 3, "three independently clipped beams")
	await _wait(28)
	_check(near.hp_component.curr_hp < before_near and beyond.hp_component.curr_hp == before_beyond,
		"wall near=%d far=%d positions=%s,%s" % [before_near - near.hp_component.curr_hp, before_beyond - beyond.hp_component.curr_hp, near.hurt_box_component.hurt_box_real.global_position, beyond.hurt_box_component.hurt_box_real.global_position])

## 确认 [param endpoint] 位于 [param beam] 对应的真实坡面；弯段按 [param plant] 的行差还原。
func _laser_tip_hits_slope(plant: Plant019ThreePeater, beam: Bullet000NormBase, endpoint: Vector2) -> bool:
	var rows: Array[ZombieRow] = _game.zombie_manager.all_zombie_rows # 原生各行的地面基准。
	var baseline: float = rows[beam.lane].zombie_create_position.global_position.y \
		- rows[plant.lane].zombie_create_position.global_position.y # 目标行的真实行差。
	var middle: Marker2D = plant.attack_component.laser_muzzles[1] # 事件发生帧的中间口型。
	var rise: float = middle.global_position.y + baseline - beam.global_position.y # 完成入行后的总高差。
	var progression: float = (endpoint.y - beam.global_position.y) / rise if not is_zero_approx(rise) else 1.0 # 弯道进度。
	var reference: int = beam.lane # 已入行则直接取目标行碰撞线。
	var projected: Vector2 = endpoint # 只在弯道上把世界交点还原到原行的原生坡面。
	if beam.lane != plant.lane and progression < 0.999:
		reference = plant.lane
		projected.y -= baseline * progression
	for part: Slope in _game.main_game_slope.all_slopes: # 直接验收真正定义的各个地形线段。
		var area: Area2D = part.all_slope_area_real[reference] # 地块行对应的原生世界变换。
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(projected,
			area.to_global(part.start_pos_slope), area.to_global(part.end_pos_slope)) # 同一物理线上的最近点。
		if closest.distance_to(projected) <= 0.15:
			return true
	return false

## 压测用真实弹体和动画，在固定物理步下观察满叠齐射。
## [param kinetic] 选择实体弹形式，[param late] 为真时启用四阶路径。
func _stress(kinetic: bool, late: bool = false) -> void:
	for bullet: Node in _game.bullets.get_children(): # 保留正式场景，先清退此前案例零散弹体。
		bullet.queue_free()
	await _wait(4)
	var plants: Array[Plant019ThreePeater] = [] # 四条陆路，每条布置四株满叠。
	var second: String = KINETIC if kinetic else ASSAULT # 分别测实弹与拖影。
	var record: PlantCardInstance = _advanced_card(FLOOD, second, SIEGE if kinetic else SUNDER,
		FINISHER if kinetic else LOCKDOWN) if late else _record(FLOOD, second) # 四阶测试替换为真实合法路线。
	var profile: PlantSpawnProfile = PlantSpawnProfile.create(record.to_dict(), AdventureResearchBattleEffects.new()) # 与实卡相同配方。
	for row: int in [0, 1, 4, 5]: # 端行同时覆盖两路合流。
		for col: int in range(4): # 16个独立原株，每次齐射实际释放36颗。
			var cell: PlantCell = _game.board.cell_at(Vector2i(row, col)) # 正式地块。
			var plant := cell.create_plant(PLANT, false, false, false, false, profile) as Plant019ThreePeater # 真实种植。
			if not _check(plant != null, "place stress plant"):
				continue
			for _stack: int in range(12 - plant.shots_per_ray()): # 两种路线都达到每路12发，沿用生产提交。
				_check(plant.reinforce(record.uid), "stress reinforcement")
			plants.append(plant)
	for row: int in [0, 1, 4, 5]: # 正常受击且保留高耐久，以持续触发攻击。
		var zombie: Zombie000Base = _zombie(row, 8) # 每种攻击行设置一只不移动的真实敌人。
		if zombie != null:
			zombie.hp_component.set_spawn_max_health(100000)
	var peak: int = 0 # 观察带场外回收策略的峰值节点数。
	var effects_at_peak: int = 0 # 区分飞行中的弹体和已经分离的命中特效。
	var begin: int = Time.get_ticks_usec() # 扣除加载、换场与准备。
	var step_times := PackedFloat64Array() # 有界采样，避免大日志。
	for _frame: int in range(360): # 6游戏秒平稳发射。
		var start: int = Time.get_ticks_usec() # 本步真实耗时，受宿主和截帧策略影响。
		await get_tree().physics_frame
		step_times.append((Time.get_ticks_usec() - start) / 1000.0)
		if _game.bullets.get_child_count() > peak:
			peak = _game.bullets.get_child_count()
			effects_at_peak = 0
			for child: Node in _game.bullets.get_children(): # 数出峰值帧中独立播放的命中特效。
				effects_at_peak += int(child is BulletEffect000Base)
	step_times.sort()
	print("THREEPEA_STRESS variant=%s late=%s plants=%d peak=%d effects=%d p95_ms=%.2f wall_ms=%.1f" % [
		"kinetic" if kinetic else "pea", late, plants.size(), peak, effects_at_peak,
		step_times[341], (Time.get_ticks_usec() - begin) / 1000.0])
	_check(peak > 200 and peak < (3100 if late else 1800), "stress reaches real volleys and releases offboard bullets")
	if late and not kinetic:
		_check(effects_at_peak > 0 and effects_at_peak < 100, "dense pea hits share splats while leaving visible impact feedback")
	await _retire_stress_actors(plants)

## 以同帧齐射放大宽相和窄相负载。[param late] 为真时启用四阶路径及首中求解。
func _laser_stress(late: bool) -> void:
	await _clear_test_bullets() # 清理上一组动能弹，不让它们混入光束峰值。
	var sources: Array[Plant019ThreePeater] = [] # 四条陆路各放四个高能来源。
	var card: PlantCardInstance = _advanced_card(HIGH, ASSAULT, SUNDER, LOCKDOWN) if late else _record(HIGH, ASSAULT) # 四阶会启用真实首中排序。
	var profile: PlantSpawnProfile = PlantSpawnProfile.create(card.to_dict(), AdventureResearchBattleEffects.new()) # 真实词条配方。
	for row: int in [0, 1, 4, 5]: # 两条边路同时覆盖合流。
		for column: int in range(4): # 不借助临时节点替代出战植物。
			var cell: PlantCell = _game.board.cell_at(Vector2i(row, column)) # 正式棋盘位置。
			var plant := cell.create_plant(PLANT, false, false, false, false, profile) as Plant019ThreePeater # 真实攻击来源。
			if not _check(plant != null, "place beam stress plant"):
				continue
			plant.attack_component.detect_component.disable_component(ComponentNormBase.E_IsEnableFactor.Character)
			sources.append(plant)
		for column: int in range(3, 9): # 近点与远点分别覆盖弯段、宽相空隙及长轨道。
			var enemy: Zombie000Base = _zombie(row, column) # 保留原生实体与受击区。
			if enemy != null:
				enemy.hp_component.set_spawn_max_health(100000)
	var timings := PackedFloat64Array() # 只保留有限的帧间耗时。
	var peak: int = 0 # 记录真实弹体对象峰值。
	for frame: int in range(240): # 每隔90帧让所有植株在同一物理帧触发。
		var start: int = Time.get_ticks_usec() # 包含当帧发射和后续物理步。
		if frame % 90 == 1:
			for plant: Plant019ThreePeater in sources: # 强制同时触发已验收的角色出射入口。
				plant.attack_component._shoot_bullet()
		await get_tree().physics_frame
		peak = maxi(peak, _game.bullets.get_child_count())
		timings.append((Time.get_ticks_usec() - start) / 1000.0)
	timings.sort()
	print("THREEPEA_ROUTE_STRESS late=%s plants=%d peak=%d p95_ms=%.2f max_ms=%.2f" % [
		late, sources.size(), peak, timings[227], timings[-1]])
	_check(sources.size() == 16 and peak >= 32 and peak <= 48, "same-frame route stress remains bounded")
	await _retire_stress_actors(sources)

## 清退本组 [param plants]、靶标和弹体，允许同一测试进程连续压测不同配置。
func _retire_stress_actors(plants: Array[Plant019ThreePeater]) -> void:
	for plant: Plant019ThreePeater in plants: # 释放实际种植格供下一配置复用。
		if is_instance_valid(plant):
			plant.be_shovel_kill()
	for zombie: Zombie000Base in _game.zombie_manager.all_zombies_1d.duplicate(): # 正常退场，不生成新的伤害和表现。
		zombie.retire_from_battle()
	await _clear_test_bullets()

## 将 [param species] 放到 [param row]、[param column] 的基线。[param offset_x] 调整格内横坐标。
func _zombie(row: int, column: int, offset_x: float = 0.0,
		species: CharacterRegistry.ZombieType = CharacterRegistry.ZombieType.Z001Norm) -> Zombie000Base:
	var cell: PlantCell = _game.board.cell_at(Vector2i(row, column)) # 实际战场坐标和地形。
	var manager: ZombieManager = _game.zombie_manager # 保持行登记及受击形状。
	var zombie: Zombie000Base = manager.create_norm_zombie(species,
		manager.all_zombie_rows[row], {
			Zombie000Base.E_ZInitAttr.Lane: row,
			Zombie000Base.E_ZInitAttr.CurrZombieRowType: cell.get_spawn_terrain_type(),
			Zombie000Base.E_ZInitAttr.ParticipatesNaturalRefresh: false,
		}, cell.get_spawn_global_position() + Vector2(offset_x, 0.0))
	if _check(zombie != null, "spawn real victim"):
		zombie.move_component.update_move_factor(true, MoveComponent.E_MoveFactor.IsDisable)
	return zombie

## 向前等待 [param frames] 个实际仿真步。
func _wait(frames: int) -> void:
	for _frame: int in range(frames): # 所有观察点都有固定时限。
		await get_tree().physics_frame
