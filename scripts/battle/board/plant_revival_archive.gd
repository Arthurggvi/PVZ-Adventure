## 植物最近死亡账本与复生的唯一入口；复生仍交给标准放置事务提交真实实体。
extends RefCounted
class_name PlantRevivalArchive

## 在 [param plant] 的死亡信号清理占用和永久状态之前记录；工具、铲除、替换和清场均由来源排除。
static func record_death(plant: Plant000Base) -> void:
	if not is_instance_valid(plant) or not plant.death_recording_enabled or plant.is_death \
			or plant.is_zombie_mode or plant.character_init_type != Character000Base.E_CharacterInitType.IsNorm \
			or plant.spawn_species_id() == CharacterRegistry.PlantType.P036CoffeeBean \
			or not _active_cell(plant.plant_cell):
		return
	var cells: Array[PlantCell] = plant.battle_placement_cells.duplicate() # 只接受实际提交过的完整占用声明。
	if cells.is_empty():
		return
	for cell: PlantCell in cells: # 多格任一部分离开当前空间都不能制造不完整尸体。
		if not _active_cell(cell) or not cell.plant_entities().has(plant):
			return
	var record := PlantDeathRecord.new() # 每次真实死亡产生新身份，复生植物以后正常死亡也可再记录。
	record.capture(plant, cells, Global.main_game)
	for cell: PlantCell in cells:
		cell.latest_plant_death = record

## 返回 [param cell] 的当前有效记录；扣血前冻结此身份，null 也由同次使用上下文缓存。
static func snapshot_record(cell: PlantCell) -> PlantDeathRecord:
	if not _active_cell(cell):
		return null
	var record: PlantDeathRecord = cell.latest_plant_death # 每格只保存最近一条，不回溯旧尸体。
	return record if _current_record(cell, record) else null

## 查询 [param cell]，可用 [param expected] 锁定使用前的尸体；不构造植物、不消费令牌。
static func can_revive(cell: PlantCell, expected: PlantDeathRecord = null) -> bool:
	var record: PlantDeathRecord = expected if expected != null else snapshot_record(cell) # 未传令牌时查询当前记录。
	if not _current_record(cell, record):
		return false
	var origin: PlantCell = record.origin_ref.get_ref() as PlantCell # 多格始终从原点恢复，不能从半格平移生成。
	var condition: ResourcePlantCondition = Global.character_registry.get_plant_info(
		record.species, CharacterRegistry.PlantInfoAttribute.PlantConditionResource) # 原物种的结构资格。
	return condition != null and condition.placement_cells(origin) == record.footprint() \
		and condition.judge_revival_allowed(origin, record.species as CharacterRegistry.PlantType)

## 在 [param cell] 触发复生，正常配方最终上限乘 [param ratio] 并满血；仅成功消费 [param expected]。
static func revive(cell: PlantCell, ratio: float = 0.5, expected: PlantDeathRecord = null) -> Plant000Base:
	var record: PlantDeathRecord = expected if expected != null else snapshot_record(cell) # 同次使用不得临时换成新死者。
	if not is_finite(ratio) or ratio <= 0.0 or ratio > 1.0 or not can_revive(cell, record):
		return null
	var game: MainGameManager = Global.main_game # 同步事务也复核阶段与轮次，拒绝回调切换后的旧计划。
	var round_index: int = game.curr_game_round # 普通波次间记录可保留，但一次提交不能跨轮执行。
	var origin: PlantCell = record.origin_ref.get_ref() as PlantCell # 唯一来源格。
	var state: Dictionary = record.state() # 永久唤醒、原材质和物种阶段都走已有恢复协议。
	var plan: PlantPlacement = PlantPlacement.prepare(origin, record.species as CharacterRegistry.PlantType,
		false, true, bool(state.get("is_imitater_material", false)), false, record.profile,
		PlantCell.PlacementOrigin.Revival) # 配方只应用一次，不把旧最终数值再次乘星级。
	if plan == null:
		return null
	var health: HpComponent = plan.plant.get_node_or_null("HpComponent") as HpComponent # 离树组件尚未写当前生命。
	if health == null or health.max_hp <= 0:
		return null
	state["revival_health_scale"] = ratio
	state.erase("revival_max_health") # 忽略死者旧上限，当前复生总是重新应用正常配方后折半。
	state["curr_hp"] = maxi(1, roundi(float(health.max_hp) * ratio)) # 离树恢复统一设置新上限，再按该上限满血入树。
	if not plan.prepare_saved_state(state) or not _current_record(cell, record) \
			or game != Global.main_game or game.curr_game_round != round_index:
		return null
	record.committing = true
	var plant: Plant000Base = plan.commit(false) # 先完成实体提交，消费令牌后才公布创建事件。
	record.committing = false
	if plant == null:
		return null
	record.consumed = true
	for target: PlantCell in record.footprint(): # 回调中新产生的死亡记录不被旧令牌清除。
		if target.latest_plant_death == record:
			target.latest_plant_death = null
	if _active_cell(origin):
		origin.signal_plant_create.emit(origin, plant.plant_type)
	return plant

## 清理 [param cell] 时使共享多格记录整体失效，不把离场操作变成新死亡。
static func clear(cell: PlantCell) -> void:
	var record: PlantDeathRecord = cell.latest_plant_death # 其他覆盖格仍持有同对象时也会观察到失效。
	if record != null:
		record.consumed = true
	cell.latest_plant_death = null

## 检查 [param cell] 仍指向 [param record] 的原战场、阶段及完整 footprint，不依赖尸体节点。
static func _current_record(cell: PlantCell, record: PlantDeathRecord) -> bool:
	if record == null or record.consumed or record.committing or not _active_cell(cell) \
			or cell.latest_plant_death != record or record.game_ref.get_ref() != Global.main_game \
			or record.board != cell.board \
			or record.phase != AdventureSession.get_active_phase(Global.main_game.game_para):
		return false
	var origin: PlantCell = record.origin_ref.get_ref() as PlantCell # 原点可与触发格不同，但必须仍属于同一空间。
	var cells: Array[PlantCell] = record.footprint() # 任一弱引用失效时整体返回空。
	if not _active_cell(origin) or cells.is_empty() or not cells.has(origin) or not cells.has(cell):
		return false
	for target: PlantCell in cells:
		if not _active_cell(target) or target.board != record.board:
			return false
	return true

## 校验 [param cell] 属于当前正式战斗与空间索引；结算、续战和退场时拒绝记录或复生。
static func _active_cell(cell: PlantCell) -> bool:
	var game: MainGameManager = Global.main_game # 始终读取当前战场，不能借用旧场景引用。
	return is_instance_valid(cell) and cell.is_inside_tree() and not cell.is_queued_for_deletion() \
		and is_instance_valid(game) and game.is_inside_tree() and not game.is_queued_for_deletion() \
		and game.get_tree().current_scene == game and game.is_ancestor_of(cell) \
		and game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME \
		and game.board != null and cell.board == game.board and game.board.cell_by_id(cell.cell_id) == cell \
		and game.board.allows_mutation() \
		and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.GameOver, false) \
		and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.AdventureContinue, false)
