## 墓碑生成与存档服务；占用唯一来自 PlantCell，不维护第二份矩阵或改写地块身份。
extends Node
class_name TombStoneManager

## 随机墓碑从逻辑第 3 列起可选，内部列号从 0 开始。
const FIRST_RANDOM_GRAVE_COLUMN: int = 2
## 白爵士召出的墓碑使用的场景与存档种类。
const WHITE_DUKE_GRAVE_KIND: StringName = &"white_duke"
## 可攻击墓碑的种类到场景映射，生成与读档共用。
const ATTACKABLE_GRAVE_PATHS: Dictionary[StringName, String] = {
	&"pvz2": "res://scenes/item/game_scenes_item/pvz2_attackable_tombstone.tscn",
	WHITE_DUKE_GRAVE_KIND: "res://scenes/item/game_scenes_item/white_duke_tombstone.tscn",
}
## 所属种植管理器，只通过空间查询取得实际地块。
@onready var plant_cell_manager: PlantCellManager = %PlantCellManager
## 墓碑数量由有效实例计算，死亡回调无需同步第二份计数。
var tombstone_num: int:
	get:
		var count: int = 0 # 当前仍占格的墓碑。
		for cell: PlantCell in plant_cell_manager.board.cells(): # 空位和待释放实体不计数。
			if _has_grave(cell):
				count += 1
		return count

## 监听原版与冒险共用的生成入口。
func _ready() -> void:
	EventBus.subscribe("create_tombstone", create_tombstone)
	EventBus.subscribe("create_pvz2_tombstone", create_pvz2_tombstone)

## 保留管理器生命周期入口；空间已由 BoardSceneAdapter 完成，不得重新编号。
func init_tomb_stone_manager(_game_para: ResourceLevelData) -> void:
	pass

## 判断 [param cell] 的真实墓碑占用，等待释放的旧实体不占位。
func _has_grave(cell: PlantCell) -> bool:
	return is_instance_valid(cell.tombstone) and not cell.tombstone.is_queued_for_deletion()

## 返回 [param kind] 对应的墓碑场景，未知种类或加载失败时返回 null。
static func scene_for_kind(kind: StringName) -> PackedScene:
	if kind == &"legacy":
		return SceneRegistry.TOMBSTONE
	var path: String = ATTACKABLE_GRAVE_PATHS.get(kind, "") # 未知存档种类没有场景。
	return load(path) as PackedScene if not path.is_empty() else null

## 通过正式 PlantCell 事务在 [param cell] 生成 [param kind] 的墓碑。
func _create_one_tombstone(cell: PlantCell, kind: StringName = &"legacy") -> void:
	if cell == null or _has_grave(cell):
		return
	var source: PackedScene = scene_for_kind(kind) # 按归属选择模板，资源缺失时保留格内植物。
	if source != null:
		cell.create_tombstone(source)

## 随机生成最多 [param new_num] 个 [param kind] 墓碑。前两列受保护，合格格子优先用右侧六列。
func create_tombstone(new_num: int, kind: StringName = &"legacy") -> void:
	await get_tree().process_frame
	if not is_instance_valid(plant_cell_manager) or plant_cell_manager.board == null:
		return
	var preferred: Array[PlantCell] = [] # 原版右侧优先区域。
	var remaining: Array[PlantCell] = [] # 右侧不足时的候补。
	var start_column: int = maxi(0, plant_cell_manager.row_col.y - 6) # 兼容原版生成偏好。
	for cell: PlantCell in plant_cell_manager.board.cells(): # 无地块矩阵补齐逻辑。
		if cell.row_col.y < FIRST_RANDOM_GRAVE_COLUMN or _has_grave(cell):
			continue
		if cell.row_col.y >= start_column:
			preferred.append(cell)
		else:
			remaining.append(cell)
	preferred.shuffle()
	remaining.shuffle()
	preferred.append_array(remaining)
	for cell: PlantCell in preferred.slice(0, maxi(0, new_num)): # 需求超过数量时只返回实际候选。
		_create_one_tombstone(cell, kind)

## 返回中右侧可随机生成自然墓碑的空地地址，始终排除第 1、2 列。
func available_pvz2_positions() -> Array[Vector2i]:
	var result: Array[Vector2i] = [] # 不返回不存在的稀疏地址。
	if not is_instance_valid(plant_cell_manager) or plant_cell_manager.board == null:
		return result
	# 保留中右侧偏好，窄棋盘也从第 3 列起选。
	var start_column: int = maxi(FIRST_RANDOM_GRAVE_COLUMN, floori(float(plant_cell_manager.row_col.y) / 3.0))
	for cell: PlantCell in plant_cell_manager.board.cells(): # 实际占用为唯一判定。
		if cell.row_col.y >= start_column and cell.can_common_plant \
				and cell.get_curr_plant_num() == 0 and not _has_grave(cell) \
				and cell.get_spawn_terrain_type() != CharacterRegistry.ZombieRowType.Pool:
			result.append(cell.row_col)
	return result

## [param new_num] 为目标生成数量；返回真正新增的墓碑数。
func create_pvz2_tombstone(new_num: int) -> int:
	if new_num <= 0:
		return 0
	var before: int = tombstone_num # 真实生成前计数。
	var candidates: Array[Vector2i] = available_pvz2_positions() # 只读资格查询。
	candidates.shuffle()
	for address: Vector2i in candidates.slice(0, new_num): # 地址由空间解析，不拿来下标压缩行。
		_create_one_tombstone(plant_cell_manager.board.cell_at(address), &"pvz2")
	return tombstone_num - before

## 生成最多 [param count] 个白爵士墓碑，可顶掉植物并避开水体与障碍。
## [param columns] 为空时使用所有合格列，前两列始终受保护。
func spawn_boss_graves(count: int, columns: Array[int] = []) -> Array[TombStone]:
	var result: Array[TombStone] = [] # 正式创建成功的实体。
	if count <= 0 or not is_instance_valid(plant_cell_manager):
		return result
	var candidates: Array[PlantCell] = [] # 不在此阶段清除植物。
	for cell: PlantCell in plant_cell_manager.board.cells(): # 每个候选对应一个真实种植点。
		if cell.row_col.y < FIRST_RANDOM_GRAVE_COLUMN \
				or (not columns.is_empty() and not columns.has(cell.row_col.y)) or _has_grave(cell) \
				or cell.get_spawn_terrain_type() == CharacterRegistry.ZombieRowType.Pool \
				or not cell.is_terrain_planting_allowed():
			continue
		if cell.curr_special_state_plant.get(PlantCell.E_SpecialStatePlant.IsCrater, false) \
				or cell.curr_special_state_plant.get(PlantCell.E_SpecialStatePlant.IsIceRoad, false) \
				or cell.curr_special_state_plant.get(PlantCell.E_SpecialStatePlant.IsPot, false):
			continue
		candidates.append(cell)
	candidates.shuffle()
	for cell: PlantCell in candidates.slice(0, count): # 仍走同一个实体/占用生成入口。
		_create_one_tombstone(cell, WHITE_DUKE_GRAVE_KIND)
		if _has_grave(cell):
			result.append(cell.tombstone)
	return result

## 保存稳定地块身份、墓碑种类和血量；旧地址仅为兼容资料。
func get_save_game_data_tomb_stone_manager() -> Dictionary:
	var records: Array[Dictionary] = [] # 不再持久化冗余占用矩阵。
	for cell: PlantCell in plant_cell_manager.board.cells(): # 同一墓碑只有一个地块拥有者。
		if _has_grave(cell):
			records.append({"cell_id": str(cell.cell_id), "row": cell.row_col.x, "col": cell.row_col.y,
				"kind": str(cell.tombstone.get_tombstone_kind()), "hp": cell.tombstone.get_current_hp()})
	return {"tombstones": records}

## 校验 [param data] 的全部引用；旧矩阵只在旧场景兼容，错误记录不静默丢失。
func accepts_save(data: Dictionary) -> bool:
	var records: Array = decode_save_records(data) # 统一旧矩阵与当前记录协议。
	if records.size() == 1 and records[0] == null:
		return false
	var seen: Dictionary[StringName, bool] = {} # 防止同一地块重复生成。
	for record: Variant in records: # 先检查未可信数据类型。
		if not record is Dictionary or not record.get("cell_id", "") is String \
				or not record.get("row", -1) is int or not record.get("col", -1) is int:
			return false
		var cell: PlantCell = plant_cell_manager.saved_cell(StringName(record.get("cell_id", "")),
			Vector2i(record.get("row", -1), record.get("col", -1))) # 稳定 ID 优先。
		var stored_kind: Variant = record.get("kind", "legacy") # 旧存档缺省为无血量墓碑。
		if cell == null or seen.has(cell.cell_id) or (not stored_kind is String and not stored_kind is StringName):
			return false
		var kind: StringName = StringName(stored_kind) # 使用与场景映射一致的种类标识。
		if kind != &"legacy" and (not ATTACKABLE_GRAVE_PATHS.has(kind) \
				or not record.get("hp") is int or record["hp"] <= 0):
			return false
		seen[cell.cell_id] = true
	return true

## 将 [param data] 中旧布尔矩阵解码为记录；[null] 表示非法格式，空数组表示没有墓碑。
func decode_save_records(data: Dictionary) -> Array:
	if data.has("tombstones"):
		return data["tombstones"] if data["tombstones"] is Array else [null]
	var result: Array = [] # 仅向后兼容读取，不在运行时保留矩阵。
	var rows: Variant = data.get("all_is_tombstone", []) # 老版本存档字段。
	if not rows is Array:
		return [null]
	for r: int in range(rows.size()): # 老矩阵的逻辑行号。
		if not rows[r] is Array:
			return [null]
		for c: int in range(rows[r].size()): # 老矩阵的逻辑列号。
			if not rows[r][c] is bool:
				return [null]
			if rows[r][c]:
				result.append({"row": r, "col": c, "kind": "legacy"})
	return result
