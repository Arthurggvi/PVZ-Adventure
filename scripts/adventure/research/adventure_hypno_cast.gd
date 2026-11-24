## 共享原生魅惑资格。范围与距离只在实际种植、唤醒或亡语时查询一次。
extends RefCounted
class_name AdventureHypnoCast

## 对 [param target] 应用原生转阵营；[param battle] 和 [param rules] 保留实际出战来源。
## 仅成功转阵营的单位获得后续效果，天然免魅惑者不会占用名额。
static func charm(target: Zombie000Base, battle: RepeaterShotContext, rules: Dictionary[String, Dictionary]) -> bool:
	if not _eligible(target, battle):
		return false
	target.be_hypno()
	if not is_instance_valid(target) or not target.is_hypno or target.is_death:
		return false
	if rules.has("hypno_release"):
		AdventureZombieTierBinding.promote_hypnotized(target)
	if rules.has("hypno_release") or rules.has("hypno_remodel") or rules.has("hypno_madness") \
			or rules.has("hypno_malice") or rules.has("hypno_infection"):
		AdventureHypnoAlly.install(target, battle, rules)
	return true

## [param center] 是实际种植格。[param battle] 和 [param rules] 由本株在发动前冻结。
static func spread_in_area(center: PlantCell, battle: RepeaterShotContext, rules: Dictionary[String, Dictionary]) -> void:
	for target: Zombie000Base in enemies_in_cells(local_cells(center, battle.board), battle): # 从真实敌方快照逐个转阵营。
		charm(target, battle, rules)

## 取得 [param center] 同一平台上拓扑相邻的九宫格；空洞和跨平台连接不进入范围。
static func local_cells(center: PlantCell, board: BoardRuntime) -> Array[PlantCell]:
	var result: Array[PlantCell] = [] # 只返回逻辑九宫格内的真实地块。
	for cell: PlantCell in board.neighbors(center, 1): # 显式拓扑允许跳格，仍校验九宫格坐标。
		if cell.board_definition.surface_id == center.board_definition.surface_id \
				and absi(cell.row_col.x - center.row_col.x) <= 1 and absi(cell.row_col.y - center.row_col.y) <= 1:
			result.append(cell)
	return result

## 仅枚举 [param cells] 对应行的敌人，用实际脚点确定候选；调用方在快照上逐项结算。
static func enemies_in_cells(cells: Array[PlantCell], battle: RepeaterShotContext) -> Array[Zombie000Base]:
	var result: Array[Zombie000Base] = [] # 只收集真正命中的敌人，后续效果回调可安全改变原登记。
	var cells_by_lane: Dictionary[int, Array] = {} # 同行格组可重用，避免逐僵尸扫描整块棋盘。
	for cell: PlantCell in cells: # 预先聚合同一个攻防行内的有效地块。
		if not cells_by_lane.has(cell.combat_lane):
			cells_by_lane[cell.combat_lane] = [] as Array[PlantCell]
		cells_by_lane[cell.combat_lane].append(cell)
	var enemy_rows: Array[Array] = battle.game.zombie_manager.all_zombies_2d # 已魅惑和退场对象不进入敌方行索引。
	for lane: int in cells_by_lane: # 其他行的敌人无需读取脚点。
		if lane < 0 or lane >= enemy_rows.size():
			continue
		for zombie: Zombie000Base in enemy_rows[lane]: # 同行仅按本次涉及的地块命中。
			if is_instance_valid(zombie) and not zombie.is_death and not zombie.is_hypno \
					and BoardQueries.ground_cell_from(battle.board, zombie.global_position, lane, cells_by_lane[lane]) != null:
				result.append(zombie)
	return result

## 从 [param origin] 世界位置选最近的 [param maximum] 个成功目标。[param battle] 和 [param rules] 仍属于同一次亡语。
static func spread_to_nearest(origin: Vector2, maximum: int, battle: RepeaterShotContext,
		rules: Dictionary[String, Dictionary]) -> void:
	if maximum <= 0 or not battle.is_active():
		return
	var candidates: Array[Dictionary] = [] # 距离逐人只计算一次，排序有固定同距顺序。
	for zombie: Zombie000Base in battle.game.zombie_manager.all_zombies_1d: # 先冻结候选，再逐个改变阵营。
		if _eligible(zombie, battle):
			candidates.append({"zombie": zombie, "distance": origin.distance_squared_to(zombie.global_position), "id": zombie.get_instance_id()})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: # 同距按出生实例稳定排序。
		return a.id < b.id if a.distance == b.distance else a.distance < b.distance)
	var remaining: int = maximum # 不计入宣告免疫或未发生阵营变化的个体。
	for candidate: Dictionary in candidates: # 回调期间旧引用可能已被释放。
		var target: Variant = candidate.zombie # 先验证弱生命周期再转为强类型。
		if is_instance_valid(target) and charm(target, battle, rules):
			remaining -= 1
			if remaining <= 0:
				break

## [param target] 必须仍是 [param battle] 的敌方普通僵尸。
static func _eligible(target: Zombie000Base, battle: RepeaterShotContext) -> bool:
	return battle.is_active() and is_instance_valid(target) and not target.is_hypno and not target.is_death \
		and not target.is_queued_for_deletion() and target.is_inside_tree() and battle.game.is_ancestor_of(target) \
		and target.character_init_type == Character000Base.E_CharacterInitType.IsNorm \
		and target.curr_be_attack_status != Zombie000Base.E_BeAttackStatusZombie.IsDraggedUnder \
		and target.can_receive_control_effects()
