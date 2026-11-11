## Cob cannon is an ordinary upgrade transaction with a two-cell footprint.
## No plant deletion or cell mutation is allowed inside the condition resource.
extends ResourcePlantCondition
class_name ResourcePlantConditionCobCannon

func placement_cells(cell: PlantCell) -> Array[PlantCell]:
	var result: Array[PlantCell] = [] # 成功和失败分支都保持相同的元素类型。
	if not is_instance_valid(cell) or cell.board == null:
		return result
	var next: PlantCell = cell.board.right_of(cell) # 邻接由空间协议解析，不压缩缺格。
	if next != null:
		result.append(cell)
		result.append(next)
	return result

func upgrade_footprint_available(cells: Array[PlantCell]) -> bool:
	for cell: PlantCell in cells:
		if is_instance_valid(cell.plant_in_cell.get(CharacterRegistry.PlacePlantInCell.Shell)):
			return false
	return true
