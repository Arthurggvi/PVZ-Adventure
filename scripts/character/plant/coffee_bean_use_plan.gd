## 一杯咖啡的冻结作用计划；预览只收集对象，放置成功后同步支付和施效。
extends RefCounted
class_name CoffeeBeanUsePlan

## 所有咖啡机制共用目标身份，范围和列种植不能重复付血。
const TARGET_FAMILY: StringName = &"coffee_effect"
## 复生格子的独立提交身份；同一个多格记录还受死亡档案令牌保护。
const REVIVE_FAMILY: StringName = &"coffee_revive"
## 本杯所属战场，防止原生动画晚到时跨场景施效。
var _game: MainGameManager
## 当次空间身份，移动平台不变而换棋盘失效。
var _board: BoardRuntime
## 当次冒险阶段身份，切换后不重新选择目标。
var _phase: StagePhaseDefinition
## 当次轮次，卡片点击的同步结算不得跨轮。
var _round_index: int = -1
## 独立复制的转职机制。
var _rules: Dictionary = {}
## 同一点击的范围及列种植共享去重上下文。
var _context: PlantPlacementUseContext
## 对象弱引用与施效前清醒状态，不能先唤醒再触发三阶。
var _targets: Array[Dictionary] = []
## 所有候选死亡记录在付血前冻结，null 由共享上下文永久保留。
var _revivals: Array[Dictionary] = []
## 仅成功施效后的原对象可进入原生唤醒动画。
var _wake_targets: Array[WeakRef] = []
## 同步执行门禁，重复动画或回调不能再次结算。
var _committed: bool = false
## 原生动画回调至多兑现一次。
var _wake_finished: bool = false

## 为 [param center] 和 [param rules] 准备纯查询计划，使用 [param context] 共享本次点击。
static func prepare(center: PlantCell, rules: Dictionary, context: PlantPlacementUseContext = null) -> CoffeeBeanUsePlan:
	var plan: CoffeeBeanUsePlan = CoffeeBeanUsePlan.new() # 即使失败也返回可查询的空计划。
	plan._game = Global.main_game
	plan._rules = rules.duplicate(true)
	plan._context = context if context != null else PlantPlacementUseContext.new()
	if not plan._active_cell(center):
		return plan
	plan._board = center.board
	plan._phase = AdventureSession.get_active_phase(plan._game.game_para)
	plan._round_index = plan._game.curr_game_round
	var area: Dictionary = rules.get("coffee_area", {}) # 无扩散时只处理中心格。
	var radius: int = maxi(0, int(area.get("radius", 0))) # 合法书目为一格九宫范围。
	var seen: Dictionary[int, bool] = {} # 多格植物或层级引用在本杯内只收集一次。
	for cell: PlantCell in center.board.neighbors(center, radius): # 地块拓扑保留平台与边界规则。
		if not plan._active_cell(cell) or not plan._within_area(center, cell, radius):
			continue
		if rules.has("coffee_revive"):
			var record: PlantDeathRecord = plan._context.snapshot_death_record(cell) # 先冻结整块棋盘，再开始任何付血。
			if record != null and not plan._context.has_target(REVIVE_FAMILY, cell) \
					and PlantRevivalArchive.can_revive(cell, record):
				plan._revivals.append({"cell": weakref(cell), "record": record})
		for target: Plant000Base in cell.living_plants(): # 每层和非占位伴生均按真实实体判断。
			if seen.has(target.get_instance_id()) or plan._context.has_target(TARGET_FAMILY, target):
				continue
			seen[target.get_instance_id()] = true
			if MushroomPlantQuery.is_active(target, plan._game) \
					and AdventureCoffeePromotionRules.has_target_effect(target, rules):
				plan._targets.append({"target": weakref(target), "awake": not target.is_sleeping})
	return plan

## 全批恢复或预置结束后，仅收集 [param center] 的原生睡眠目标。
## [param game]、[param board]、[param phase] 是调度时身份；不重放跨格书籍、生命支付或冷却。
static func prepare_native_wakeup(center: PlantCell, game: MainGameManager,
		board: BoardRuntime, phase: StagePhaseDefinition) -> CoffeeBeanUsePlan:
	var plan: CoffeeBeanUsePlan = CoffeeBeanUsePlan.new() # 原生恢复计划没有任何转职规则或支付目标。
	plan._game = game
	plan._board = board
	plan._phase = phase
	if not plan._wakeup_current() or not is_instance_valid(center) \
			or not center.is_inside_tree() or center.is_queued_for_deletion() \
			or center.board != board or board.cell_by_id(center.cell_id) != center \
			or not game.is_ancestor_of(center):
		return plan
	var target: Plant000Base = center.sleeping_plant() # 旧存档只恢复中心原资格，不推测已经丢失的跨格对象。
	if MushroomPlantQuery.is_active(target, game) and MushroomPlantQuery.is_mushroom(target):
		plan._wake_targets.append(weakref(target))
	plan._committed = true
	return plan

## 表示本次准备至少具有一个有效作用；不消费目标、死亡记录或任何游戏资源。
func has_effect() -> bool:
	return not _targets.is_empty() or not _revivals.is_empty()

## 放置占位完成后同步执行一次；返回本杯实际四阶成功带来的额外冷却。
func commit() -> float:
	if _committed or not _current():
		return 0.0
	_committed = true
	var extra: float = 0.0 # 所有目标只取最大成功附加值，不能按命中数累加。
	for entry: Dictionary in _targets: # 全批对象和尸体已经冻结，此后不重新查询目标。
		if not _current():
			break
		extra = maxf(extra, _apply_target(entry))
	var revival: Dictionary = _rules.get("coffee_revive", {}) # 无四阶复生时保留空候选。
	for entry: Dictionary in _revivals: # 同杯死亡不会替换冻结令牌。
		var cell: PlantCell = entry.cell.get_ref() as PlantCell # 地格可能在回调中退场。
		var record: PlantDeathRecord = entry.record as PlantDeathRecord # 只认使用开始前的具体死亡。
		if not _current() or not _active_cell(cell) or not _context.claim_target(REVIVE_FAMILY, cell):
			continue
		var revived: Plant000Base = PlantRevivalArchive.revive(cell, float(revival.get("health_ratio", 0.5)), record) # 档案入口负责普通占位和最大生命缩减。
		if revived != null:
			_context.claim_target(TARGET_FAMILY, revived)
			extra = maxf(extra, maxf(0.0, float(revival.get("cooldown_extra", 5.0))))
	return extra

## 对 [param entry] 冻结的原对象支付代价；致死不授予任何正面效果或额外冷却。
func _apply_target(entry: Dictionary) -> float:
	var target: Plant000Base = entry.target.get_ref() as Plant000Base # 弱引用不能在目标消失后替换成新占用者。
	if not MushroomPlantQuery.is_active(target, _game) or not _context.claim_target(TARGET_FAMILY, target):
		return 0.0
	var awake: bool = bool(entry.awake) # 以本次任何唤醒之前的状态决定三阶资格。
	var armor: Dictionary = _rules.get("coffee_armor", {}) # 独立四阶代价可以与一个三阶相加。
	var fraction: float = maxf(0.0, float(armor.get("hp_cost_fraction", 0.0))) # 汇总同次支付，避免中间受击回调重复扣血。
	if awake:
		for kind: String in ["coffee_haste", "coffee_damage"]: # 不同三阶族分别保留自己的租约。
			fraction += maxf(0.0, float(_rules.get(kind, {}).get("hp_cost_fraction", 0.0)))
	if fraction > 0.0:
		target.hp_component.apply_unblocked_loss(roundi(float(target.hp_component.max_hp) * fraction),
			BulletRegistry.AttackMode.Norm, true, false)
	if not _current() or not MushroomPlantQuery.is_active(target, _game) or target.hp_component.curr_hp <= 0:
		return 0.0
	var solar: Dictionary = _rules.get("coffee_solar", {}) # 永久产值只登记独立来源，不改成熟阶段原始数值。
	var sun: CreateSunComponent = AdventureCoffeePromotionRules.producer(target) # 不按固定物种名单猜测生产能力。
	if sun != null and not solar.is_empty():
		sun.coffee_solar_bonus = maxf(sun.coffee_solar_bonus, maxf(0.0, float(solar.get("bonus", 0.0))))
	if awake:
		for kind: String in ["coffee_haste", "coffee_damage"]: # 续时不增加第二份来源。
			var effect: Dictionary = _rules.get(kind, {}) # 不存在的分支不授予或收费。
			if not effect.is_empty():
				CoffeePlantBoost.grant(target, kind, float(effect.get("bonus", 0.5)), float(effect.get("seconds", 10.0)))
	if MushroomPlantQuery.is_mushroom(target) and not target.sleep_component.is_permanently_awake:
		_wake_targets.append(weakref(target))
	var health: HpComponentPlant = target.hp_component as HpComponentPlant # 护甲统一进入原生可消耗护甲池。
	if not armor.is_empty() and health != null \
			and health.grant_bonus_armor(maxi(0, int(armor.get("armor", 2000)))) > 0:
		return maxf(0.0, float(armor.get("cooldown_extra", 5.0)))
	return 0.0

## 原生咖啡动画只兑现冻结目标的唤醒，不重新付血、授盾或查找当前格子的睡眠者。
func finish_wakeup() -> void:
	if not _committed or _wake_finished:
		return
	_wake_finished = true
	if not _wakeup_current():
		return
	for reference: WeakRef in _wake_targets: # 全部范围目标保留原生伸缩和永久唤醒表现。
		var target: Plant000Base = reference.get_ref() as Plant000Base # 离场、死亡或无效化后不再唤醒。
		if MushroomPlantQuery.is_active(target, _game):
			target.coffee_bean_awake_up()
	_wake_targets.clear()

## 生命支付和四阶结果必须在原轮次的正式战斗中同步完成。
func _current() -> bool:
	return _wakeup_current() and _game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME \
		and _game.curr_game_round == _round_index

## 已付费目标的原生唤醒可以跨普通轮次，不能跨战场、空间或冒险阶段。
func _wakeup_current() -> bool:
	return wakeup_context_current(_game, _board, _phase)

## 校验 [param game]、[param board]、[param phase]；原生选卡、准备和同场重选仍可兑现唤醒。
static func wakeup_context_current(game: MainGameManager, board: BoardRuntime, phase: StagePhaseDefinition) -> bool:
	return is_instance_valid(game) and game.is_inside_tree() and not game.is_queued_for_deletion() \
		and game == Global.main_game and game.get_tree().current_scene == game \
		and game.main_game_progress not in [MainGameManager.E_MainGameProgress.NONE, MainGameManager.E_MainGameProgress.GAME_OVER] \
		and game.board == board and board != null and board.allows_mutation() \
		and AdventureSession.get_active_phase(game.game_para) == phase \
		and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.GameOver, false) \
		and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.AdventureContinue, false)

## [param cell] 必须属于当前可操作棋盘；预览不借用旧场景或已退出的地格。
func _active_cell(cell: PlantCell) -> bool:
	return is_instance_valid(cell) and cell.is_inside_tree() and not cell.is_queued_for_deletion() \
		and is_instance_valid(_game) and _game.is_inside_tree() and not _game.is_queued_for_deletion() \
		and _game == Global.main_game and _game.get_tree().current_scene == _game \
		and _game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME \
		and _game.board != null and cell.board == _game.board and _game.is_ancestor_of(cell) \
		and cell.board.cell_by_id(cell.cell_id) == cell and cell.board.allows_mutation() \
		and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.GameOver, false) \
		and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.AdventureContinue, false)

## [param center] 与 [param cell] 必须同平台且在 [param radius] 的方形格距内。
## 显式邻接可以跨平台或远距，不能借其连接扩大九宫范围。
func _within_area(center: PlantCell, cell: PlantCell, radius: int) -> bool:
	return center.board_definition != null and cell.board_definition != null \
		and center.board_definition.surface_id == cell.board_definition.surface_id \
		and absi(center.row_col.x - cell.row_col.x) <= radius \
		and absi(center.row_col.y - cell.row_col.y) <= radius
