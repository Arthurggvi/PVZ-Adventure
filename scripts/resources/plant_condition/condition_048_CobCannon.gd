## Cob cannon is an ordinary upgrade transaction with a two-cell footprint.
## No plant deletion or cell mutation is allowed inside the condition resource.
extends ResourcePlantCondition
class_name ResourcePlantConditionCobCannon

func placement_cells(cell: PlantCell) -> Array[PlantCell]:
	if not is_instance_valid(cell) or cell.board == null:
		return []
	var next: PlantCell = cell.board.right_of(cell) # 稀疏或显式邻接，不按数组下标猜测。
	return [cell, next] if next != null else []


func upgrade_footprint_available(cells: Array[PlantCell]) -> bool:
	for cell: PlantCell in cells:
		if is_instance_valid(cell.plant_in_cell.get(CharacterRegistry.PlacePlantInCell.Shell)):
			return false
	return true
