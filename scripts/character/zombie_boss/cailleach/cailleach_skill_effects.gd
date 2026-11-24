## 妇人与凯莱赫共用的技能结算，只作用到本阶段、本场的实际棋盘和出战卡槽。
extends Node

## 登场为所有当时在场的植株施加原生寒冷减速。
const ENTRANCE_SLOW_SECONDS: float = 6.0

## 「沉眠吧」的冰壳目标数量上限。
const SLEEP_TARGETS: int = 8
## 每枚极光对植物造成的最大生命值比例。
const AURORA_HP_FRACTION: float = 0.15
## 凯莱赫死亡时逐个召来的极光数。
const DEATH_AURORAS: int = 20
## 死亡落星首发立即起飞，后续相邻起飞间隔在该游戏秒区间内独立取样。
const DEATH_LAUNCH_GAPS := Vector2(0.085, 0.38)
## 飞行和凝冰复用伊芙原演出，只在施放「仰望」时载入。
const AURORA_PATH := "res://scripts/adventure/skills/eve_aurora_starfall.gd"
## CC0 掠过声源为 Freesound 的 877980（Qvantor）。
const AURORA_FALL_PATH := "res://resources/adventure/audio/cailleach_aurora_fall.ogg"
## CC0 撞击声源为 Freesound 的 562298（colorsCrimsonTears）与 428574（vykroft）。
const AURORA_IMPACT_PATH := "res://resources/adventure/audio/cailleach_aurora_impact.ogg"
## 「安息吧」至处决时才加载残像的色彩材质。
const DISSOLVE_PATH := "res://scripts/character/zombie_boss/cailleach/cailleach_plant_dissolve.gd"
## 施放「呼啸」时才加载雪暴的碰撞与渲染。
const HOWL_PATH := "res://scripts/character/zombie_boss/cailleach/cailleach_howl_blizzard.gd"
## 完全悲寒和普通冻结分开读取。
const Grief = preload("res://scripts/character/zombie_boss/cailleach/cailleach_plant_grief.gd")

## 与远程落星、雪弹共用的战场、棋盘与轮次快照。
var _battle: RepeaterShotContext
## 极光和雪暴共用的原始攻击归因。
var _plant_hit: CombatHitScope
## 此阶段的冻结名单、落点及风雪使用私有随机流。
var _rng := RandomNumberGenerator.new()

## 根据 [param game] 捕获施法的棋盘和轮次；[param caster] 提供实际伤害归属。
func _init(game: MainGameManager, caster: ZB000Base = null) -> void:
	name = "CailleachSkillEffects"
	_plant_hit = CombatHitScope.for_plant_attack(caster)
	_battle = RepeaterShotContext.new()
	_battle.game = game
	_battle.board = game.board
	_battle.round_index = game.curr_game_round
	_battle.phase = AdventureSession.get_active_phase(game.game_para)
	_rng.randomize()

## 一阶段开场使所有当前植物减速，随机冰封半场。
func entrance() -> void:
	if not is_active():
		return
	var plants: Array[Plant000Base] = _plants(_battle.board.cells()) # 只处理实际在场株。
	for plant: Plant000Base in plants: # 普通减速可以与猎人冰壳及悲寒同时存在。
		AdventurePlantNegativeEffects.apply(plant, AdventurePlantNegativeEffects.Kind.ICE_SLOW, 0, ENTRANCE_SLOW_SECONDS)
	_freeze_random(plants, ceili(plants.size() * 0.5))

## 随机给至多八株当前可冰封的植物套上猎人冰壳。
func sleep() -> void:
	if is_active():
		_freeze_random(_plants(_battle.board.cells()), SLEEP_TARGETS)

## 只根据抽取时在场的活体植物判定「安息吧」是否能入池。
func can_rest() -> bool:
	return is_active() and _can_rest(_plants(_battle.board.cells()))

## 在命中帧重新采集所有满悲寒或冻结的活株，直接消散并追加冷却。
func rest() -> void:
	if is_active():
		_disperse(_plants(_battle.board.cells()))

## 向至多 [param lane_limit] 路各发射 [param shots_per_lane] 枚雪弹，返回仍在出弹的演出节点。
func howl(lane_limit: int = 2, shots_per_lane: int = 120) -> Node2D:
	if not is_active():
		return null
	var bullets: Node2D = _battle.game.bullets # 与本战场其他投射物共享世界画布。
	if not is_instance_valid(bullets) or bullets.is_queued_for_deletion():
		return null
	var script: Script = load(HOWL_PATH) as Script # 只在实际发动时加载。
	var barrage: Node2D = script.new(_battle, _rng.randi(), is_active, lane_limit, shots_per_lane, _plant_hit) # 发射节奏使用本次独立随机流。
	tree_exiting.connect(barrage.queue_free, CONNECT_ONE_SHOT)
	bullets.add_child(barrage)
	return barrage

## 在 [param plants] 里同时找到完全悲寒和普通冻结两类目标时才允许抽取。
## 同一个植株可以同时提供两个条件，但处决只结算一次。
static func _can_rest(plants: Array[Plant000Base]) -> bool:
	var grief: bool = false # 独立的满层悲寒判定。
	var frozen: bool = false # 猎人冰壳或已有寒冷系统的真正冻结。
	for plant: Plant000Base in plants: # 检查触地前的场上快照。
		grief = grief or Grief.is_complete(plant)
		frozen = frozen or plant.is_cold_frozen()
		if grief and frozen:
			return true
	return false

## 从 [param plants] 中抽出至多 [param count] 株可冰封的植物；已有冰壳不刷新。
func _freeze_random(plants: Array[Plant000Base], count: int) -> void:
	var candidates: Array[Plant000Base] = plants.filter(func(plant: Plant000Base) -> bool:
		return is_instance_valid(plant) and plant.can_apply_hunter_ice_shell()
	)
	while count > 0 and not candidates.is_empty() and is_active():
		var index: int = _rng.randi_range(0, candidates.size() - 1) # 无放回抽取，为免疫的植株保留名额。
		var plant: Plant000Base = candidates.pop_at(index) # 冰封使用猎人的持久冰壳与原有效果。
		if is_instance_valid(plant) and plant.apply_hunter_ice_shell():
			count -= 1

## 抽取 [param count] 枚错序落星，单发加深 [param grief_layers] 层悲寒。
## 格数用尽后才重新抽取。返回飞行与星空冰节点，无合法落点时为空。
func aurora(count: int, grief_layers: int) -> Node2D:
	if not is_active():
		return null
	return _launch_aurora(count, _resolve_aurora.bind(grief_layers))

## [param validity] 仅在凯莱赫仍持有真实战场的死亡演出资格时返回真。
## 返回 20 枚错峰极光的批次，命中使用处决和冰封规则。
func death_aurora(validity: Callable) -> Node2D:
	if not _battle.is_same_battle() or not validity.is_valid() or not validity.call():
		return null
	var times := PackedFloat32Array([0.0]) # 第一枚在死亡帧开始下落。
	for index: int in range(1, DEATH_AURORAS): # 交错的短促连落和停顿保证各发能被看清。
		times.append(times[index - 1] + _rng.randf_range(DEATH_LAUNCH_GAPS.x, DEATH_LAUNCH_GAPS.y))
	return _launch_aurora(DEATH_AURORAS, _resolve_death_aurora.bind(validity), times, validity)

## 共用 [param count] 个实际落点和 [param impact] 命中接口。
## [param times] 和 [param validity] 分别供死亡演出覆写发射节奏与战斗门禁。
func _launch_aurora(count: int, impact: Callable, times: PackedFloat32Array = PackedFloat32Array(),
		validity: Callable = Callable()) -> Node2D:
	var game: MainGameManager = _battle.game # 飞行与星空冰归属于本局共用世界特效层。
	if not is_instance_valid(game.bombs) or game.bombs.is_queued_for_deletion():
		return null
	var starfall: Script = load(AURORA_PATH) as Script # 同一份下坠、拖尾、星空冰和撞击碎晶。
	var cells: Array[PlantCell] = [] # 与极光正式格索引共享合法性判定。
	for cell: PlantCell in _battle.board.cells(): # 包含空格，不追踪植物。
		if starfall.is_landing_cell(_battle.board, cell):
			cells.append(cell)
	if cells.is_empty():
		return null
	var candidates: Array[PlantCell] = cells.duplicate() # 优先在不同格子上落地。
	var targets: Array[PlantCell] = [] # 插入顺序就是本次落星入场顺序。
	for _index: int in range(count): # 即使棋盘很小也维持本次落星数量。
		if candidates.is_empty():
			candidates.assign(cells)
		targets.append(candidates.pop_at(_rng.randi_range(0, candidates.size() - 1)))
	var flight: AudioStream = load(AURORA_FALL_PATH) as AudioStream # 妇人落星独有的掠风。
	var collision: AudioStream = load(AURORA_IMPACT_PATH) as AudioStream # 妇人重砸的独立音色。
	var barrage: Node2D = starfall.new(null, _battle, targets, _rng.randi(), impact, flight, collision,
		times, validity) # 玩法与伊芙的演出使用同一组实际落点。
	tree_exiting.connect(barrage.queue_free, CONNECT_ONE_SHOT)
	game.bombs.add_child(barrage)
	return barrage

## 单枚极光对 [param cells] 的每株当前植物按生命上限计伤，存活者再加 [param grief_layers] 层悲寒。
func _resolve_aurora(cells: Array[PlantCell], grief_layers: int) -> void:
	for plant: Plant000Base in _plants(cells): # 同一发不重复伤及跨格或多层登记的同一株。
		if not is_active():
			return
		if not is_instance_valid(plant) or plant.is_death or plant.is_queued_for_deletion():
			continue
		var damage: int = maxi(1, roundi(plant.hp_component.max_hp * AURORA_HP_FRACTION)) # 先算最大生命比例，再走护甲和受击规则。
		plant.be_attacked_bullet(damage, BulletRegistry.AttackMode.Norm, false, false, 0, -1, null, _plant_hit)
		AdventurePlantNegativeEffects.apply(plant, AdventurePlantNegativeEffects.Kind.SORROW_COLD, 0, grief_layers)

## 死亡极光命中 [param cells] 时，按脚点精确处决僵尸并冰封植物。
## [param validity] 在死亡回调可能同步改变战斗状态时重新检查。
func _resolve_death_aurora(cells: Array[PlantCell], validity: Callable) -> void:
	if not validity.is_valid() or not validity.call():
		return
	var manager: ZombieManager = _battle.game.zombie_manager # 包含本局登记的敌方及魅惑僵尸。
	for zombie: Zombie000Base in manager.all_zombies_1d.duplicate(): # 同步死亡会从登记中移除，遍历快照。
		if not is_instance_valid(zombie) or zombie.is_death or zombie.is_queued_for_deletion():
			continue
		var cell: PlantCell = _battle.board.cell_at_ground_point(zombie.global_position, zombie.lane) # 斜坡按真正的脚下格判定。
		if cells.has(cell):
			zombie.retire_from_battle(true)
			if not validity.is_valid() or not validity.call():
				return
	for plant: Plant000Base in _plants(cells): # 同株多格覆盖只尝试一次，已有冰封不刷新。
		plant.apply_hunter_ice_shell()

## 处决 [param plants] 中所有冻住或悲寒满层的原株，按真实死亡株数增加当前出战卡冷却。
func _disperse(plants: Array[Plant000Base]) -> void:
	var victims: Array[Plant000Base] = plants.filter(func(plant: Plant000Base) -> bool:
		return Grief.is_complete(plant) or plant.is_cold_frozen()
	)
	if victims.is_empty():
		return
	# 先结算承托物上方的目标，再处决底座，避免承托释放间接吞掉独立目标。
	victims.sort_custom(func(a: Plant000Base, b: Plant000Base) -> bool:
		return not (a is Plant000DownBase) and b is Plant000DownBase
	)
	var script: Script = load(DISSOLVE_PATH) as Script # 用死前的真实轮廓组成同一次雾化。
	var remains: Node2D = script.new() # 整次处决的残像共用一个寿命。
	_battle.game.bombs.add_child(remains)
	var losses: Dictionary[int, int] = {} # 按出战植物种类统计实际击杀。
	for plant: Plant000Base in victims: # 悲寒与冰冻同时存在的植株在快照中已去重。
		if not is_active():
			return
		if not is_instance_valid(plant) or plant.is_death or plant.is_queued_for_deletion():
			continue
		var species: int = plant.spawn_species_id() # 记录原种类，死亡回调可能释放该实例。
		remains.capture(plant)
		plant.is_can_death_language = false
		plant.death_recording_enabled = false
		plant.character_death_disappear()
		if is_instance_valid(plant) and plant.is_death:
			losses[species] = losses.get(species, 0) + 1
	_add_card_penalties(losses)

## 当前出战栏中同种的卡分别增加 [param losses] 中对应的秒数。
func _add_card_penalties(losses: Dictionary[int, int]) -> void:
	var game: MainGameManager = _battle.game # 不写卡牌库或战斗基础时长。
	var fixed_cards: CardSlotBattle = game.card_manager.card_slot_battle # 无冷却调试保留原有优先级。
	if is_instance_valid(fixed_cards) and fixed_cards.cheat_no_cooldown_enabled:
		return
	for card: Card in game.card_slot_root.curr_cards: # 冷却中的卡延长剩余时间，已就绪卡从零开始。
		if not is_instance_valid(card) or card.is_queued_for_deletion() or card.card_reference == null \
				or card.card_reference.card_type != ResourceCardReference.CardType.Plant:
			continue
		card.add_cooldown_penalty(float(losses.get(card.card_reference.content_id, 0)))

## 有效 [param cells] 的各层活体植物，每个实际实例只出现一次。
static func _plants(cells: Array[PlantCell]) -> Array[Plant000Base]:
	var found: Dictionary[Plant000Base, bool] = {} # 带多格占用的植物也按真实实例登记。
	for cell: PlantCell in cells: # 将底座、壳层和不占位伴生都纳入本地范围。
		if is_instance_valid(cell) and not cell.is_queued_for_deletion():
			for plant: Plant000Base in cell.living_plants(): # 格子统一处理死亡、释放及隐藏占位。
				found[plant] = true
	var plants: Array[Plant000Base] = [] # 字典的键数组显式转成植物数组。
	plants.assign(found.keys())
	return plants

## 阶段来源退场、切关或重开时禁止在途结算，真正暂停期间保留已有演出。
func is_active() -> bool:
	return (is_inside_tree() and not is_queued_for_deletion() and not get_parent().is_queued_for_deletion()
		and _battle.is_active() and not get_tree().paused and not PVZCheat.is_open())
