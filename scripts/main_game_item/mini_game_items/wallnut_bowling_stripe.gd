extends Sprite2D
class_name WallnutBowlingStripe

var plant_cell_manager:PlantCellManager

func init_item(plant_cell_col_j:int=2, plant_cell_can_use:Dictionary = {}):
	var board: BoardRuntime = Global.main_game.board # 战场空间权威。
	var target: PlantCell = board.cell_at(Vector2i(0, plant_cell_col_j)) # 红线参考种植点。
	if target == null:
		push_error("保龄球红线缺少配置的参考种植点。")
		return
	var point: Vector2 = target.global_position # 当前视觉定位，不修改格子。
	if is_instance_valid(Global.main_game.main_game_slope):
		scale.y = 0.88
		var next: PlantCell = board.right_of(target) # 屋顶的下一逻辑格。
		if next != null:
			point.y = next.global_position.y
	global_position = point + Vector2(target.size.x - 11.0, 0.0)
	for cell: PlantCell in board.cells(): # 每个实际地块独立执行限制。
		var side: String = "left" if cell.row_col.y <= plant_cell_col_j else "right" # 逻辑列边界。
		if not plant_cell_can_use.get(side + "_can_plant", true):
			cell.set_bowling_no_plant()
		if not plant_cell_can_use.get(side + "_can_zombie", true):
			cell.set_bowling_no_zombie()
