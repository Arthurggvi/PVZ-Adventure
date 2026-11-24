## 在真实泳池战场回归海草书目、种植费用、目标范围和击杀奖励。
extends Node

## 测试卡使用注册表的海草物种。
const KELP := CharacterRegistry.PlantType.P020TangleKelp
## 使用图书馆的真实候选入口校验书目接入。
const LibraryRules = preload("res://scripts/adventure/library/library_rules.gd")
## 两个候选按实际阶数排序，供快照和目录断言共用。
const BOOKS := [
	["cheap_crop", "siren"],
	["slots", "parasite"],
	["spread", "evil_spirit"],
	["envy_vine", "greed_vine"],
]

## 当前验证使用的真实泳池场景。
var _game: MainGameManager
## 本次仍使用原生扣费和冷却结算的预选卡。
var _card: Card
## 同一场内真实成功用卡信号次数。
var _commits: int = 0
## 不立即停止独立案例，便于一次验收定位多处回归。
var _failures: int = 0

## 测试节点独立存活，换场和暂停期间仍能控制退出。
func _ready() -> void:
	get_tree().current_scene = null
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

## [param ok] 为可观察契约，[param message] 描述失败；返回原结果供前置检查使用。
func _check(ok: bool, message: String) -> bool:
	if not ok:
		_failures += 1
		printerr("KELP_FAIL ", message)
	return ok

## 运行有界的场景验证，只访问临时用户目录。
func _run() -> void:
	if not _check(OS.get_user_data_dir().contains("kelp-audit"), "isolated user directory"):
		get_tree().quit(1)
		return
	Global.save_service.stop_autosave()
	_catalog()
	if await _open_pool():
		await _spread()
		await _parasite()
		await _replaced_host()
		await _edge_bite(false)
		await _edge_bite(true)
		await _evil()
		await _water_entry()
		await _paused_grab()
		await _interrupted_grab()
	print("KELP_RESULT=", "PASS" if _failures == 0 else "FAIL", " failures=", _failures)
	get_tree().quit(0 if _failures == 0 else 1)

## 目录、库存和图书馆按四阶提供同一份候选，非法断阶不会取得战斗效果。
func _catalog() -> void:
	var card := PlantCardInstance.new() # 从未转职开始逐阶校验合法选项。
	card.plant_type = KELP
	card.stars = 10
	card.uid = "PC000020"
	for tier: int in range(1, 5): # 玩家每次只应看到实际下一阶。
		var ids: Array[String] = [] # 研究室当前显示的候选 ID。
		for book: Dictionary in AdventurePromotionCatalog.options(card): # 从权威查询读取。
			ids.append(book.id)
		var expected: Array[String] = [] # 测试规格中的两本书。
		for suffix: String in BOOKS[tier - 1]: # 复用稳定 ID 的物种前缀。
			var id := "promotion_tanglekelp_" + suffix # 对照真实道具注册。
			expected.append(id)
			_check(ItemRegistry.has_item(id), "inventory recognizes " + id)
		_check(ids == expected and LibraryRules.pool(tier, KELP) == expected, "tier %d catalog and library" % tier)
		card.set_promotion(tier, expected[0])
	_check(AdventurePromotionCatalog.next_tier(card) == 0, "four changes complete the chain")
	card.promotion_2 = ""
	_check(not AdventurePromotionCatalog.is_valid_chain(card)
		and AdventurePromotionCatalog.effects(card).events.is_empty(), "gapped snapshot grants no powers")

## 加载项目的正式泳池、原生卡栏和棋盘；只关闭自然波次及天降阳光以消除测试噪声。
func _open_pool() -> bool:
	var level: ResourceLevelData = load("res://resources/level_date_resource/mode_adventure/adventure_03_pool.tres").duplicate(true) # 不改共享关卡配置。
	level.look_show_zombie = false
	level.can_choosed_card = false
	level.monster_mode = ConstLevelData.E_MonsterMode.Null
	level.is_day_sun = false
	level.start_sun = 150
	level.prechosen_cards = [ResourceCardReference.create(ResourceCardReference.CardType.Plant, KELP)]
	Global.game_para = level
	if not _check(get_tree().change_scene_to_file("res://scenes/main/MainGame02Back.tscn") == OK, "open real pool"):
		return false
	for frame: int in range(360): # 按物理帧等待实卡开始收费用，避免无头进程的渲染帧率影响时限。
		await get_tree().physics_frame
		_game = Global.main_game
		if is_instance_valid(_game) and _game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME:
			var slots: CardSlotBattle = _game.card_manager.card_slot_battle # 正式战斗卡槽。
			if slots != null and not slots.curr_cards.is_empty() and slots.curr_cards[0].card_context == Card.CardContext.Battle:
				_card = slots.curr_cards[0]
				_card.signal_card_use_end.connect(_on_card_used)
				return true
	return _check(false, "battle card did not become ready")

## 只计入本张实卡的成功使用，[param card] 为触发者。
func _on_card_used(card: Card) -> void:
	if card == _card:
		_commits += 1

## 将顺序指定的 [param suffixes] 按现有转职前缀冻结为真实出战配置。
func _profile(suffixes: Array[String]) -> PlantSpawnProfile:
	var record := PlantCardInstance.new() # 测试专用 UID 不写入用户库存。
	record.uid = "PC000020"
	record.plant_type = KELP
	record.stars = 10
	for index: int in range(suffixes.size()): # 一至四转按路径选择。
		record.set_promotion(index + 1, "promotion_tanglekelp_" + suffixes[index])
	return PlantSpawnProfile.create(record.to_dict(), AdventureResearchBattleEffects.new())

## 返回 [param row]、[param column] 的真实格子，行列从零开始。
func _at(row: int, column: int) -> PlantCell:
	return _game.board.cell_at(Vector2i(row, column))

## 用 [param profile] 在 [param cell] 按原生手持结算一次；测试之间显式复位冷却。
func _plant_card(cell: PlantCell, profile: PlantSpawnProfile) -> bool:
	_card.plant_spawn_profile = profile
	_card.set_card_cool_end()
	_card.judge_card_ready()
	_game.hand_manager._click_card(_card)
	var planted: bool = _game.hand_manager.hm_character.click_cell(cell) # 经虚影预检、提交和卡槽信号。
	_game.hand_manager._cancel_selection()
	return planted

## [param condition] 有界等待物理回调，最多 [param frames] 帧。
func _until(condition: Callable, frames: int = 95) -> bool:
	for frame: int in range(frames): # 避免碰撞或动画未触发时悬挂进程。
		if condition.call():
			return true
		await get_tree().physics_frame
	return condition.call()

## 两个物理帧后检查已提交的释放和重挂。
func _flush() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame

## 清空本用例创建的实体和掉落，使用原生战场清理入口。
func _clear() -> void:
	for zombie: Zombie000Base in _game.zombie_manager.all_zombies_1d.duplicate(): # 退场会更新原登记集合。
		if is_instance_valid(zombie):
			zombie.retire_from_battle()
	for cell: PlantCell in _game.board.cells(): # 清除本用例的封格和真实占用。
		cell.set_planting_block(&"kelp_audit", false)
		for plant: Plant000Base in cell.living_plants(): # 正常清理阶段不触发测试用的亡语。
			plant.be_shovel_kill()
	for layer: Node in [_game.suns, _game.drop_item_manager.dim_coin.all_drop_coin_parent]: # 防止带着旧奖励进入下一例。
		for pickup: Node in layer.get_children(): # 两个容器只保存战场掉落物。
			pickup.queue_free()
	await _flush()

## 使用 [param cell] 的真实脚点生成 [param kind]；[param dx] 为水平方向的像素偏移。
## [param friendly] 走原生魅惑登记，[param tier] 指定可选的实际难度修饰。
func _spawn(cell: PlantCell, kind: CharacterRegistry.ZombieType, dx: float = 0.0,
		friendly: bool = false, tier: StringName = &"") -> Zombie000Base:
	var row: ZombieRow = _game.zombie_manager.all_zombie_rows[cell.combat_lane] # 和关卡相同的真实僵尸行。
	var parameters: Dictionary = {
		Zombie000Base.E_ZInitAttr.Lane: cell.combat_lane,
		Zombie000Base.E_ZInitAttr.CurrZombieRowType: cell.get_spawn_terrain_type(),
		Zombie000Base.E_ZInitAttr.ParticipatesNaturalRefresh: false,
		Zombie000Base.E_ZInitAttr.StartsHypnotized: friendly,
	} # 无自然波次，减少与测试无关的计数。
	var modifier: ZombieSpawnModifier = null if tier.is_empty() else AdventureZombieTierBinding.new(tier) # 走正式等阶绑定。
	var zombie: Zombie000Base = _game.zombie_manager.create_norm_zombie(kind, row, parameters,
		cell.get_spawn_global_position() + Vector2(dx, 0.0), Callable(), modifier) # 实际生成并登记。
	if zombie != null:
		zombie.move_component.update_move_factor(true, MoveComponent.E_MoveFactor.IsDisable)
		zombie.drop_item_component.drop_coin_rate = 0.0
	return zombie

## [param cell] 正常层的真实物种用于确认扩种、拒绝及释放结果。
func _has_kelp(cell: PlantCell) -> bool:
	return cell.plant_in_cell[CharacterRegistry.PlacePlantInCell.Norm] is Plant020Tanglekelp

## 低价和扩种走一次成功用卡，封格、承托占位及陆路继续遵守原生条件。
func _spread() -> void:
	var profile: PlantSpawnProfile = _profile(["cheap_crop", "slots", "spread"]) # 三转廉价扩种。
	var center: PlantCell = _at(2, 4) # 泳池边，九宫格横跨陆路。
	var blocked: PlantCell = _at(2, 3) # 能种水面叠加独立禁种。
	var supported: PlantCell = _at(3, 5) # 有承托的水面仍遵守本路径的空水种植规则。
	blocked.set_planting_block(&"kelp_audit", true)
	supported.create_plant(CharacterRegistry.PlantType.P017LilyPad, false, false)
	var before: int = _commits # 子株不得发卡牌使用信号。
	var sun: int = _game.card_manager.card_slot_battle.sun_value # 下种前实际余额。
	_check(_plant_card(center, profile), "spread main card is usable")
	_check(_commits == before + 1 and _game.card_manager.card_slot_battle.sun_value == sun
		and _card._is_cooling, "free planting starts one cooldown")
	for cell: PlantCell in _game.board.cells(): # 确认恰好四个合法位置，中心外不递归。
		var expected: bool = cell.row_col in [Vector2i(2, 4), Vector2i(2, 5), Vector2i(3, 3), Vector2i(3, 4)]
		_check(_has_kelp(cell) == expected, "spread occupancy at %s" % cell.row_col)
	await _clear()

## 真实啃食导致宿主死亡时抓住当前的两名啃食者；同场其余敌人和陆地宿主均不受作用。
func _parasite() -> void:
	var profile: PlantSpawnProfile = _profile(["cheap_crop", "parasite", "spread", "envy_vine"]) # 跨四阶组合。
	var water: PlantCell = _at(2, 4) # 中心可叠种，旁边扩种正常海草。
	var land: PlantCell = _at(1, 4) # 与中心相邻的陆地。
	var lily: Plant000Base = water.create_plant(CharacterRegistry.PlantType.P017LilyPad, false, false) # 下层承托。
	var host: Plant000Base = water.create_plant(CharacterRegistry.PlantType.P004WallNut, false, false) # 实际受啃目标。
	var beneficiary: Plant000Base = land.create_plant(CharacterRegistry.PlantType.P004WallNut, false, false) # 岸上受益者。
	if not _check(lily != null and host != null and beneficiary != null, "host and armor fixtures"):
		await _clear()
		return
	(lily.hp_component as HpComponentPlant).grant_bonus_armor(3000)
	var armor: HpComponentPlant = beneficiary.hp_component as HpComponentPlant # 唯一近邻受益者的护甲组件。
	armor.grant_bonus_armor(2800)
	var awards: Array[int] = [] # 每次授甲后记录受益者的真实护甲。
	armor.bonus_armor_changed.connect(func(total: int) -> void: awards.append(total))
	_check(not _plant_card(land, profile) and not _card._is_cooling, "land parasite does not use card or cooldown")
	# 隔离本例的啃食目标：额外海草只验证扩种后即正常清除。
	_check(_plant_card(water, profile) and _has_kelp(_at(3, 5)), "parasite and spread both commit")
	await _flush()
	_check(water.plant_in_cell[CharacterRegistry.PlacePlantInCell.Norm] == host
		and water.plant_in_cell[CharacterRegistry.PlacePlantInCell.Float] == null, "host slot survives and temporary slot releases")
	var mover: Plant000Base = _at(3, 5).plant_in_cell[CharacterRegistry.PlacePlantInCell.Norm] # 本路径的普通子株。
	_check(not _at(3, 5).relocate_plant(mover, water), "moving a kelp cannot overwrite a host")
	for cell: PlantCell in _game.board.cells(): # 清除扩种株，不影响已经寄生的中心。
		if _has_kelp(cell):
			cell.plant_in_cell[CharacterRegistry.PlacePlantInCell.Norm].be_shovel_kill()
	await _flush()
	var first: Zombie000Base = _spawn(water, CharacterRegistry.ZombieType.Z011Duckytube, 6.0) # 目标右侧第一位啃食者。
	var second: Zombie000Base = _spawn(water, CharacterRegistry.ZombieType.Z011Duckytube, 12.0) # 同一宿主的另一位啃食者。
	var bystander: Zombie000Base = _spawn(_at(3, 4), CharacterRegistry.ZombieType.Z011Duckytube) # 真正水中但在别行。
	if not _check(first != null and second != null and bystander != null, "parasite enemies spawned"):
		await _clear()
		return
	var biters: bool = await _until(func() -> bool:
		return first.attack_component.detect_component.enemy_can_be_attacked == host \
			and second.attack_component.detect_component.enemy_can_be_attacked == host)
	if _check(biters, "both enemies legitimately chew the host"):
		first.hp_component.curr_hp = 125
		second.hp_component.curr_hp = 100
		host.hp_component.curr_hp = 1
		var first_ref: WeakRef = weakref(first) # 处决后闭包只保留可安全解包的弱引用。
		var second_ref: WeakRef = weakref(second) # 第二个啃食者也必须真实退场。
		_check(await _until(func() -> bool: return first_ref.get_ref() == null and second_ref.get_ref() == null, 150),
			"lethal native bite triggers one drowning per biter")
		_check(is_instance_valid(bystander) and not bystander.is_death, "nearby water bystander is not chewing")
		_check(awards.size() == 2 and awards[0] in [2900, 2925] and armor.bonus_armor == 3000,
			"envy vine transfers exact remaining life and caps the second award at 3000")
	await _clear()

## 原生索敌一次触发多目标，陆地、盘外和友军均保留；每份奖励对应一次真实击杀。
func _evil() -> void:
	var profile: PlantSpawnProfile = _profile(["siren", "slots", "evil_spirit", "greed_vine"]) # 一次覆盖魅惑、掉光和金币。
	var center: PlantCell = _at(2, 4) # 接收原生近身索敌。
	var dry: PlantCell = _at(3, 3) # 同一攻击行内的动态陆地格。
	_check(_game.board.set_cell_terrain(dry.cell_id, &"grass"), "set mixed terrain in same pool row")
	var new_allies: Array[Dictionary] = [] # 记录生成时脚点，不受友军后续行走影响。
	var record: Callable = func(zombie: Zombie000Base) -> void: # 捕获正式管理器发布的初始阵营和位置。
		if zombie.is_hypno:
			new_allies.append({"type": zombie.zombie_type, "point": zombie.global_position, "tier": zombie.adventure_tier_id})
	var friend: Zombie000Base = _spawn(_at(3, 4), CharacterRegistry.ZombieType.Z011Duckytube, 0.0, true) # 自带魅惑的范围内友军。
	var wrong_terrain: Zombie000Base = _spawn(dry, CharacterRegistry.ZombieType.Z001Norm) # 实际脚点位于动态陆地。
	var far: Zombie000Base = _spawn(_at(3, 6), CharacterRegistry.ZombieType.Z011Duckytube) # 两列之外。
	var above: Zombie000Base = _spawn(_at(1, 4), CharacterRegistry.ZombieType.Z001Norm) # 九宫格内的陆地行。
	var diagonal: Zombie000Base = _spawn(_at(3, 5), CharacterRegistry.ZombieType.Z012Snorkle, 0.0, false, &"elite") # 九宫格对角的潜水僵尸。
	var primary: Zombie000Base = _spawn(center, CharacterRegistry.ZombieType.Z011Duckytube) # 首个原生可索敌目标。
	if not _check(friend != null and wrong_terrain != null and far != null and above != null and diagonal != null
			and primary != null, "mixed range fixture spawned"):
		await _clear()
		return
	await _flush()
	var diagonal_point: Vector2 = diagonal.global_position # 预期复活在死亡脚点。
	var primary_x: float = primary.global_position.x # 阳光抛物线只改变 Y，足以识别掉落归属。
	var sun_before: int = _game.card_manager.card_slot_battle.sun_value # 费用为原生25。
	_game.zombie_manager.signal_zombie_created.connect(record)
	_check(_plant_card(center, profile) and _game.card_manager.card_slot_battle.sun_value == sun_before - 25,
		"offensive card pays original cost once")
	var primary_ref: WeakRef = weakref(primary) # 只观察真实生命周期。
	var diagonal_ref: WeakRef = weakref(diagonal) # 倒地的潜水者也须释放登记。
	_check(await _until(func() -> bool: return primary_ref.get_ref() == null and diagonal_ref.get_ref() == null),
		"evil spirit drowns primary and diagonal enemies")
	_game.zombie_manager.signal_zombie_created.disconnect(record)
	for survivor: Zombie000Base in [friend, wrong_terrain, far, above]: # 比较正例与不同拒绝原因的对照组。
		_check(is_instance_valid(survivor) and not survivor.is_death, "wrong terrain, distant or friendly target survives")
	_check(new_allies.size() == 2, "siren yields two allied clones")
	_check(new_allies.any(func(recorded: Dictionary) -> bool: # 潜水者保留出生水路和可继承等阶。
		return recorded.type == CharacterRegistry.ZombieType.Z012Snorkle and recorded.tier == &"elite" \
			and recorded.point.distance_to(diagonal_point) < 1.0), "siren preserves species, tier and ground position")
	var sun_by_victim: Array[int] = [0, 0] # 两个不同横坐标的击杀各自取得一档完整掉落。
	for sun: Sun in _game.suns.get_children(): # 只检查老虎机实际创建的掉落。
		_check(sun.sun_value in [25, 50], "slot drop pieces are multiples of 25")
		var index: int = 0 if absf(sun.global_position.x - primary_x) < 1.0 else 1 # 使用原生掉落物实际坐标。
		sun_by_victim[index] += sun.sun_value
	_check(sun_by_victim[0] in [25, 50, 75, 100] and sun_by_victim[1] in [25, 50, 75, 100],
		"slots pay a legal tier separately for each kill")
	var coins: Node2D = _game.drop_item_manager.dim_coin.all_drop_coin_parent # 原生掉落容器。
	_check(coins.get_child_count() == 2, "greed drops exactly two gold coins")
	for coin: Coin in coins.get_children(): # 已关闭原生随机掉币，逐枚检查面额。
		_check(coin.scene_file_path.ends_with("coin_gold.tscn"), "greed uses native gold denomination")
	await _clear()
	_game.board.set_cell_terrain(dry.cell_id, &"pool")

## 准备后更换了宿主时，旧寄生计划不能迁就格内的新植物。
func _replaced_host() -> void:
	var water: PlantCell = _at(2, 4) # 具备稳定承托的真实水格。
	water.create_plant(CharacterRegistry.PlantType.P017LilyPad, false, false)
	var old_host: Plant000Base = water.create_plant(CharacterRegistry.PlantType.P004WallNut, false, false) # 玩家准备时所选宿主。
	var profile: PlantSpawnProfile = _profile(["cheap_crop", "parasite"]) # 无扩种，单独核对目标身份。
	var plan := PlantPlacement.prepare(water, KELP, false, false, false, false,
		profile, PlantCell.PlacementOrigin.Player) # 通过生产代码的离树预检。
	if _check(old_host != null and plan != null and plan.can_commit(), "parasite preparation binds a valid host"):
		old_host.be_shovel_kill()
		await _flush()
		var replacement: Plant000Base = water.create_plant(CharacterRegistry.PlantType.P004WallNut, false, false) # 同格、同种、不同实例。
		if _check(replacement != null, "host replacement was legal"):
			_check(plan.commit() == null and replacement.get_node_or_null(^"TanglekelpParasite") == null,
				"prepared parasite rejects a different host in the same slot")
	await _clear()

## 返回第一个泳池行的实际最右格，使用世界坐标避免依赖列号朝向。
func _pool_edge() -> PlantCell:
	var edge: PlantCell = _at(2, 0) # 从本行第一个有效候选开始。
	for cell: PlantCell in _game.board.row_cells(2): # 依次比较真实世界位置。
		if cell.global_position.x > edge.global_position.x:
			edge = cell
	return edge

## [param wet] 为真时在最后一个可种格外扩展真实水域，分别测水中和岸上啃食者。
func _edge_bite(wet: bool) -> void:
	var water: PlantCell = _pool_edge() # 宿主占用最后一个水格。
	water.create_plant(CharacterRegistry.PlantType.P017LilyPad, false, false)
	var host: Plant000Base = water.create_plant(CharacterRegistry.PlantType.P004WallNut, false, false) # 靠右仍能被水路敌人啃食。
	var outside: float = water.get_global_rect().end.x + 1.0 - water.get_spawn_global_position().x # 坐标在可种格之外。
	var enemy: Zombie000Base = _spawn(water, CharacterRegistry.ZombieType.Z011Duckytube, outside) # 冻结横移以聚焦啃食。
	var profile: PlantSpawnProfile = _profile(["siren", "parasite"]) # 以真实塞壬掉落协助确认归属。
	if not _check(host != null and enemy != null and _plant_card(water, profile), "edge parasite setup"):
		await _clear()
		return
	var extension: WaterBodyArea # 额外水域复用实际物理区域，不修改植格或伪造游泳状态。
	if wet:
		var point: Vector2 = _game.to_local(enemy.global_position) # 水体用战场局部坐标。
		extension = WaterBodyArea.from_region(Rect2(point - Vector2(8.0, 55.0), Vector2(55.0, 95.0)))
		_game.add_child(extension)
	var contact: WaterContactArea = enemy.swim_box_component.water_contact_area # 原生接触先于游泳动画。
	var can_bite: bool = await _until(func() -> bool: return contact.touching_water == wet \
		and enemy.attack_component.detect_component.enemy_can_be_attacked == host, 40)
	if _check(can_bite and _game.board.cell_at_ground_point(enemy.global_position, enemy.lane) == null,
			"real biter contacts expected terrain outside the grid: %s" % wet):
		if wet:
			_check(not enemy.is_swimming, "biter enters water just before lethal bite, before visual transition")
		host.hp_component.curr_hp = 1
		var host_ref: WeakRef = weakref(host) # 等原生致死啃食，之后才开始观察奖励。
		_check(await _until(func() -> bool: return host_ref.get_ref() == null), "native bite kills edge host")
		await get_tree().create_timer(1.2).timeout
		_check(is_instance_valid(enemy) != wet, "only a swimming edge biter can be dragged: %s" % wet)
		_check(_game.zombie_manager.all_zombies_be_hypno.size() == int(wet), "edge parasite exact Siren reward: %s" % wet)
	await _clear()
	if extension != null:
		extension.queue_free()
		await _flush()

## 已在原生攻击区中的僵尸跨入格子后，恶鬼应重验水面，不依赖第二次物理入区。
func _water_entry() -> void:
	var edge: PlantCell = _pool_edge() # 使用地图实际最右边界。
	var border: float = edge.get_global_rect().end.x # 顶层格子世界右边界。
	var outside: float = border + 3.0 - edge.get_spawn_global_position().x # 仍处于碰撞器，但落脚在棋盘外。
	var victim: Zombie000Base = _spawn(edge, CharacterRegistry.ZombieType.Z011Duckytube, outside) # 保持静止，测试决定何时跨线。
	var profile: PlantSpawnProfile = _profile(["cheap_crop", "slots", "evil_spirit"]) # 增强攻击只允许合法水格。
	if not _check(victim != null and _plant_card(edge, profile), "edge entry setup"):
		await _clear()
		return
	var kelp: Plant020Tanglekelp = edge.plant_in_cell[CharacterRegistry.PlacePlantInCell.Norm] # 实际发动者。
	var events: Array[int] = [0] # 确保本例先经过一次整套原生索敌回调。
	kelp.detect_component.signal_can_attack.connect(func() -> void: events[0] += 1)
	var native_overlap: bool = await _until(func() -> bool: return events[0] > 0, 25)
	await _flush()
	if _check(native_overlap and is_instance_valid(victim) and not victim.is_action_suspended(),
			"outside enemy overlaps the native detector without being grabbed"):
		victim.global_position.x = border - 4.0
		_check(await _until(func() -> bool: return victim.curr_be_attack_status == Zombie000Base.E_BeAttackStatusZombie.IsDraggedUnder, 28),
			"an overlapping enemy that enters the water cell is rechecked")
	await _clear()

## 真正抓住后，菜单暂停冻结原生下沉与金币；恢复后只结算一次。
func _paused_grab() -> void:
	var center: PlantCell = _at(2, 4) # 可被原生检测的水域中心。
	var victim: Zombie000Base = _spawn(center, CharacterRegistry.ZombieType.Z011Duckytube) # 确定唯一敌人。
	var profile: PlantSpawnProfile = _profile(["cheap_crop", "slots", "evil_spirit", "greed_vine"]) # 一次处决产生一枚金币。
	if not _check(victim != null and _plant_card(center, profile), "menu pause fixture"):
		await _clear()
		return
	if _check(await _until(func() -> bool: return victim.curr_be_attack_status == Zombie000Base.E_BeAttackStatusZombie.IsDraggedUnder),
			"grab started before pause"):
		var coins: Node2D = _game.drop_item_manager.dim_coin.all_drop_coin_parent # 检查掉落结算次数。
		TreePauseManager.start_tree_pause(TreePauseManager.E_PauseFactor.Menu)
		await get_tree().create_timer(1.25).timeout
		_check(is_instance_valid(victim) and not victim.is_death and coins.get_child_count() == 0, "pause suspends drowning and drops")
		TreePauseManager.end_tree_pause(TreePauseManager.E_PauseFactor.Menu)
		_check(await _until(func() -> bool: return coins.get_child_count() == 1), "unpause completes exactly one kill")
	await _clear()

## 被另一来源抢先杀死的目标不产生海草击杀奖励。
func _interrupted_grab() -> void:
	var center: PlantCell = _at(2, 4) # 可正常受击的水格。
	var victim: Zombie000Base = _spawn(center, CharacterRegistry.ZombieType.Z011Duckytube) # 用真实退场事件中断。
	var profile: PlantSpawnProfile = _profile(["siren", "slots", "evil_spirit", "greed_vine"]) # 任何误归属都会在掉落层显现。
	if not _check(victim != null and _plant_card(center, profile), "interrupted action fixture"):
		return
	if _check(await _until(func() -> bool: return victim.curr_be_attack_status == Zombie000Base.E_BeAttackStatusZombie.IsDraggedUnder),
			"victim was actually bound by native grapple"):
		victim.retire_from_battle(true)
		await get_tree().create_timer(1.2).timeout
		_check(_game.suns.get_child_count() == 0 and _game.zombie_manager.all_zombies_be_hypno.is_empty()
			and _game.drop_item_manager.dim_coin.all_drop_coin_parent.get_child_count() == 0, "no claim on someone else's kill")
	await _clear()
