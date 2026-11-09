extends Node
class_name TombStoneManager

const PVZ2_TOMBSTONE_PATH := "res://scenes/item/game_scenes_item/pvz2_attackable_tombstone.tscn"

@onready var plant_cell_manager: PlantCellManager = %PlantCellManager

## 是否有墓碑(二维)
var all_is_tombstone:Array[Array]
## 墓碑数量
var tombstone_num := 0

func _ready() -> void:
	## 注册创建墓碑全局事件
	EventBus.subscribe("create_tombstone", create_tombstone)
	EventBus.subscribe("create_pvz2_tombstone", create_pvz2_tombstone)

## 初始化墓碑管理器
func init_tomb_stone_manager(_game_para:ResourceLevelData):
	# 植物种植区域信号，更新植物位置列号,更新墓碑信息
	for plant_cells_row_i in range(plant_cell_manager.all_plant_cells.size()):
		var plant_cells_row = plant_cell_manager.all_plant_cells[plant_cells_row_i]
		var is_tombstone_row := []
		for plant_cells_col_j in range(plant_cells_row.size() - 1, -1, -1):
			var plant_cell:PlantCell = plant_cells_row[plant_cells_col_j]
			plant_cell.row_col = Vector2(plant_cells_row_i, plant_cells_col_j)
			## 该位置没有墓碑
			is_tombstone_row.append(false)

		all_is_tombstone.append(is_tombstone_row)

#region 墓碑相关
## 生成待选位置,没有墓碑的行和列
func _candidates_position(rows:int, cols_start:int, cols_end:int=plant_cell_manager.row_col.y) -> Array[Vector2i]:
	# 构建可选位置列表
	var candidates: Array[Vector2i]= []
	for r in range(rows):
		for c in range(cols_start, cols_end):
			## 如果没有墓碑
			if not all_is_tombstone[r][c]:
				candidates.append(Vector2i(r, c))

	# 打乱顺序确保随机性
	candidates.shuffle()
	return candidates

## 随机生成墓碑的位置
func _reandom_tombstone_pos(new_num:int) ->  Array[Vector2i]:
	var rows = plant_cell_manager.row_col.x
	var cols = plant_cell_manager.row_col.y

	# 如果请求的数量超过所有格子总数，就返回所有格子
	if new_num + tombstone_num >= rows * cols:
		var all_positions = _candidates_position(rows, cols)
		return all_positions

	var usable_cols : int
	## 当场上墓碑数量小于 6列 * 行数时
	if tombstone_num < 6 * rows:
		usable_cols = cols - 6
	else:
		usable_cols = cols

	# 构建可选位置列表
	var candidates = _candidates_position(rows, usable_cols)
	print("待选位置", candidates)
	# 取前n个作为随机选择位置
	var selected_positions = candidates.slice(0, min(new_num, candidates.size()))

	if len(selected_positions) < new_num:
		# 构建可选位置列表
		var new_candidates = _candidates_position(rows, 0, usable_cols)
		var add_pos = new_candidates.slice(0, min(new_num- len(selected_positions), new_candidates.size()))

		selected_positions.append_array(add_pos)

	print("墓碑生成位置：",  selected_positions)

	return selected_positions

## 创建一个墓碑
func _create_one_tombstone(plant_cell: PlantCell, pos:Vector2i, kind: StringName = &"legacy"):
	assert(not is_instance_valid(plant_cell.tombstone))
	assert(not all_is_tombstone[pos.x][pos.y], "第"+str(pos)+"墓碑有问题")

	## plant_cell生成墓碑并连接信号
	var source: PackedScene = null
	if kind == &"pvz2":
		source = load(PVZ2_TOMBSTONE_PATH) as PackedScene
		if source == null:
			push_error("PVZ2 tombstone scene failed to load")
			return
	plant_cell.create_tombstone(source)
	if not is_instance_valid(plant_cell.tombstone):
		return
	plant_cell.signal_cell_delete_tombstone.connect(_delete_tombstone)

	# 创建墓碑相关参数变化
	all_is_tombstone[pos.x][pos.y] = true
	tombstone_num += 1


## 删除墓碑修改对应的参数并断开信号连接
func _delete_tombstone(plant_cell:PlantCell, _tombstone:TombStone):
	var pos:Vector2i = plant_cell.row_col
	all_is_tombstone[pos.x][pos.y] = false
	tombstone_num -= 1
	plant_cell.signal_cell_delete_tombstone.disconnect(_delete_tombstone)


## 黑夜关卡生成墓碑（生成数量）
func create_tombstone(new_num:int, kind: StringName = &"legacy"):
	await get_tree().process_frame
	## 最大数量： 最大可生成列数 * 行数
	## 生成随机位置
	print("墓碑生成数量", new_num)
	var selected_positions :Array[Vector2i]= _reandom_tombstone_pos(new_num)

	print("墓碑生成位置", selected_positions)
	for pos in selected_positions:
		var plant_cell:PlantCell = plant_cell_manager.all_plant_cells[pos.x][pos.y]

		_create_one_tombstone(plant_cell, pos, kind)

## Pure occupancy filter, shared by all phase/flag spawn sources.
func available_pvz2_positions() -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	if not is_instance_valid(plant_cell_manager):
		return candidates
	var cols: int = plant_cell_manager.row_col.y
	for r in range(all_is_tombstone.size()):
		for c in range(maxi(0, cols / 3), cols):
			if c >= all_is_tombstone[r].size() or all_is_tombstone[r][c]:
				continue
			var cell: PlantCell = plant_cell_manager.all_plant_cells[r][c]
			if not cell.can_common_plant or cell.get_curr_plant_num() != 0:
				continue
			candidates.append(Vector2i(r, c))
	return candidates

## 可攻击墓碑仅在空格生成，优先中右侧，避免抢占已种植的格子。
func create_pvz2_tombstone(new_num: int) -> int:
	if new_num <= 0:
		return 0
	var previous_total := tombstone_num
	var candidates := available_pvz2_positions()
	candidates.shuffle()
	for i in range(mini(new_num, candidates.size())):
		var pos := candidates[i]
		_create_one_tombstone(plant_cell_manager.all_plant_cells[pos.x][pos.y], pos, &"pvz2")
	return tombstone_num - previous_total

#endregion

#region 存档

## 保存墓碑种类及剩余生命；保留旧二维布尔字段兼容既有存档。
func get_save_game_data_tomb_stone_manager() -> Dictionary:
	var records: Array[Dictionary] = []
	for r in range(plant_cell_manager.all_plant_cells.size()):
		for c in range(plant_cell_manager.all_plant_cells[r].size()):
			var stone: TombStone = plant_cell_manager.all_plant_cells[r][c].tombstone
			if not is_instance_valid(stone) or stone.is_queued_for_deletion():
				continue
			records.append({
				"row": r, "col": c,
				"kind": str(stone.get_tombstone_kind()),
				"hp": stone.get_current_hp(),
			})
	return {"all_is_tombstone": all_is_tombstone, "tombstones": records}

func load_game_data_tomb_stone_manager(save_data: Dictionary):
	if save_data.has("tombstones") and save_data["tombstones"] is Array:
		for record in save_data["tombstones"]:
			if not record is Dictionary:
				continue
			var r := int(record.get("row", -1))
			var c := int(record.get("col", -1))
			if r < 0 or r >= all_is_tombstone.size():
				continue
			if c < 0 or c >= all_is_tombstone[r].size() or all_is_tombstone[r][c]:
				continue
			var pos := Vector2i(r, c)
			var cell: PlantCell = plant_cell_manager.all_plant_cells[r][c]
			var kind: StringName = &"pvz2" if record.get("kind", "") == "pvz2" else &"legacy"
			_create_one_tombstone(cell, pos, kind)
			if kind == &"pvz2" and is_instance_valid(cell.tombstone):
				cell.tombstone.restore_hp(int(record.get("hp", 700)))
		return
	var old_cells: Array[Array] = save_data.get("all_is_tombstone", all_is_tombstone)
	for i in range(mini(old_cells.size(), all_is_tombstone.size())):
		for j in range(mini(old_cells[i].size(), all_is_tombstone[i].size())):
			if old_cells[i][j] and not all_is_tombstone[i][j]:
				var pos := Vector2i(i, j)
				_create_one_tombstone(plant_cell_manager.all_plant_cells[i][j], pos)

#endregion
