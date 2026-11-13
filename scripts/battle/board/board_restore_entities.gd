## 整体恢复的实体准备阶段；只拥有离树对象及临时占用声明，不写活格子。
extends RefCounted
class_name BoardRestoreEntities

## 本次恢复的唯一空间。
var board: BoardRuntime
## 所有物种共用的植物放置计划。
var plants: Array[PlantPlacement] = []
## 已构造墓碑和其冻结状态。
var graves: Array[Dictionary] = []
## 已构造梯子和其冻结状态。
var ladders: Array[Dictionary] = []
## 按稳定地块 ID 建立的临时占用声明，仅用于一次预检。
var _claims: Dictionary = {}

## 编译 [param saved] 的全部实体；格式、资源、跨格/结构冲突任一失败即弃置计划。
static func prepare(manager: PlantCellManager, saved: ResourceSaveGamePlantCellManager) -> BoardRestoreEntities:
	if not manager.tomb_stone_manager.accepts_save(saved.tomb_stone_manager_data):
		return null
	var plan := BoardRestoreEntities.new() # 离树资源的唯一所有者。
	plan.board = manager.board
	var seen: Dictionary[StringName, bool] = {} # 拒绝重复的格子记录。
	for record: ResourceSaveGamePlantCell in saved.all_plant_cells_datas: # 不按记录顺序提交。
		if record == null:
			return null
		var cell: PlantCell = manager.saved_cell(record.cell_id, record.row_col) # ID 优先且必须存在。
		if cell == null or seen.has(cell.cell_id) or (record.cell_id != &"" and record.row_col != cell.row_col):
			return null
		seen[cell.cell_id] = true
		for slot: int in record.plant_type_in_cell: # 字典可能含非法枚举值，必须显式检查。
			if not CharacterRegistry.PlacePlantInCell.values().has(slot):
				return null
			var data: Dictionary = record.plant_type_in_cell[slot] # 后续准备复制，不能借用可变输入。
			if not data.get("plant_type") is int or not data.get("is_imitater_material") is bool:
				return null
			var plant: PlantPlacement = PlantPlacement.prepare(cell, data["plant_type"], false, false,
				data["is_imitater_material"], manager.game_para.is_zombie_mode if manager.game_para != null else false,
				null, PlantCell.PlacementOrigin.SaveRestore) # 构造与正常种植完全共用。
			if plant == null or plant.condition.place_plant_in_cell != slot or not plant.prepare_saved_state(data):
				return null
			plan.plants.append(plant)
			for target: PlantCell in plant.footprint: # 多格植物按真实占用声明检测重叠。
				if not plan._claims.has(target.cell_id):
					plan._claims[target.cell_id] = {}
				if plan._claims[target.cell_id].has(slot):
					return null
				plan._claims[target.cell_id][slot] = plant
		if record.is_ladder:
			if record.ladder_tier_id != &"" and not AdventureZombieTierCatalog.tier_ids().has(record.ladder_tier_id):
				return null
			var ladder: Ladder = cell.prepare_ladder() # 负面效果仅在最后提交时生效。
			if ladder == null:
				return null
			plan.ladders.append({"cell": cell, "node": ladder, "tier": record.ladder_tier_id})
	for data: Dictionary in manager.tomb_stone_manager.decode_save_records(saved.tomb_stone_manager_data):
		var cell: PlantCell = manager.saved_cell(StringName(data.get("cell_id", "")),
			Vector2i(data.get("row", -1), data.get("col", -1))) # 先前已验证的目标。
		var source: PackedScene = load(TombStoneManager.PVZ2_TOMBSTONE_PATH) as PackedScene \
			if data.get("kind", "legacy") == "pvz2" else SceneRegistry.TOMBSTONE # 唯一正式资源。
		var grave: TombStone = cell.prepare_tombstone(source) # 所有实体先构造，不能临到提交才发现资源坏了。
		if grave == null:
			return null
		plan.graves.append({"cell": cell, "node": grave, "hp": int(data.get("hp", 0))})
	if not plan._compatible_claims():
		return null
	plan.plants.sort_custom(func(left: PlantPlacement, right: PlantPlacement):
		return _slot_order(left.condition.place_plant_in_cell) < _slot_order(right.condition.place_plant_in_cell))
	return plan

## 承托物先恢复，再恢复普通植物、外壳和漂浮层，输入字典顺序不能改变结果。
static func _slot_order(slot: int) -> int:
	return [CharacterRegistry.PlacePlantInCell.Down, CharacterRegistry.PlacePlantInCell.Norm,
		CharacterRegistry.PlacePlantInCell.Shell, CharacterRegistry.PlacePlantInCell.Float,
		CharacterRegistry.PlacePlantInCell.Imitater].find(slot)

## 检查未来占用的相互关系，不用当前空场景代替存档中的植物。
func _compatible_claims() -> bool:
	var grave_cells: Dictionary[StringName, bool] = {} # 未来结构所在格。
	for grave: Dictionary in graves: # 墓碑与植物的共占规则来自条件资源。
		grave_cells[(grave["cell"] as PlantCell).cell_id] = true
	for plant: PlantPlacement in plants: # 保留吞碑植物这种合法结构共占，不写物种 ID 特判。
		for cell: PlantCell in plant.footprint:
			if grave_cells.has(cell.cell_id) != plant.condition.requires_tombstone:
				return false
			if plant.footprint.size() > 1 and plant.condition.place_plant_in_cell == CharacterRegistry.PlacePlantInCell.Norm \
					and _claims[cell.cell_id].has(CharacterRegistry.PlacePlantInCell.Shell):
				return false
	for ladder: Dictionary in ladders: # 梯子必须依附植物，不能与墓碑同时恢复。
		var cell: PlantCell = ladder["cell"] # 未来梯子目标。
		if not _claims.has(cell.cell_id) or _claims[cell.cell_id].is_empty() or grave_cells.has(cell.cell_id):
			return false
	return true

## 整体恢复只允许空白场地；先拒绝全部活占用，不能覆盖半个旧场景。
func can_commit() -> bool:
	for cell: PlantCell in board.cells(): # 包含模仿者槽，不用不完整的展示数量判断。
		if not is_instance_valid(cell) or cell.is_queued_for_deletion():
			return false
		for reference: Variant in cell.plant_entities(): # 任何仍有效的占用均不能被读档隐式覆盖。
			if is_instance_valid(reference):
				return false
		if is_instance_valid(cell.tombstone) or is_instance_valid(cell.ladder) or is_instance_valid(cell.pot) \
			or is_instance_valid(cell.crater) or not cell.curr_ice_roads.is_empty():
			return false
	for plant: PlantPlacement in plants: # 准备后身份、前置和占用仍必须有效。
		if not plant.can_commit():
			return false
	return true

## 已通过整体预检后提交；资源与数据均在离树阶段就绪，不再创建对象或解析输入。
func apply_prepared() -> void:
	for entry: Dictionary in graves: # 吞碑植物依赖墓碑先存在。
		var cell: PlantCell = entry["cell"] # 正式占用归属。
		var grave: TombStone = entry["node"] # 预留实体。
		cell.install_prepared_tombstone(grave)
		if grave is PvZ2AttackableTombstone:
			grave.restore_hp(entry["hp"])
	for plant: PlantPlacement in plants: # 已按承托层优先排序。
		plant.cell.commit_prepared_plant(plant, false)
	for entry: Dictionary in ladders: # 此时目标植物已完整恢复。
		(entry["cell"] as PlantCell).install_prepared_ladder(entry["node"], entry["tier"])

## 整体提交后才发布植物创建事件，监听者不会看到半份存档。
func publish() -> void:
	for plant: PlantPlacement in plants: # 多格植物只由原点发布一次。
		plant.cell.signal_plant_create.emit(plant.cell, plant.plant.plant_type)

## 放弃准备时释放结构；植物由 PlantPlacement 自身释放，活节点不属于计划。
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for entry: Dictionary in graves + ladders: # 仅释放未挂载对象。
			var node: Node = entry["node"] # 计划持有的离树资源。
			if is_instance_valid(node) and node.get_parent() == null:
				node.free()
