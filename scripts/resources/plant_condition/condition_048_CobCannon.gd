## Cob cannon is an ordinary upgrade transaction with a two-cell footprint.
## No plant deletion or cell mutation is allowed inside the condition resource.
extends ResourcePlantCondition
class_name ResourcePlantConditionCobCannon

func placement_cells(cell: PlantCell) -> Array[PlantCell]:
	if not is_instance_valid(cell) or not is_instance_valid(Global.main_game):
		return []
	var manager: PlantCellManager = Global.main_game.plant_cell_manager
	var r: int = cell.row_col.x
	var next_column: int = cell.row_col.y + 1
	if r < 0 or r >= manager.all_plant_cells.size() \
			or next_column >= manager.all_plant_cells[r].size():
		return []
	return [cell, manager.all_plant_cells[r][next_column]]

func upgrade_footprint_available(cells: Array[PlantCell]) -> bool:
	for cell: PlantCell in cells:
		if is_instance_valid(cell.plant_in_cell.get(CharacterRegistry.PlacePlantInCell.Shell)):
			return false
	return true
