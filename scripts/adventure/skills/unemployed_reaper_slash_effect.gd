## 以实际棋盘倒数第三逻辑列定位，由战场持有延时斩击。
extends CharacterSkillEffect

## 从刷怪侧向内数第三列，逻辑地址从零起算。
const COLUMN_FROM_RIGHT: int = 3
## 仅装备莫伊并绑定技能时解析演出及其资源。
const Slash = preload("res://scripts/adventure/skills/unemployed_reaper_slash.gd")

## [param context] 必须属于可施放的战斗，且存在有效的目标列与表现容器。
func can_execute(context: CharacterSkillContext) -> bool:
	if context == null or not context.is_active() or not is_instance_valid(context.game.bombs) \
			or not context.game.bombs.is_inside_tree() or context.game.bombs.is_queued_for_deletion():
		return false
	return not _column_cells(context.board).is_empty()

## 在 [param context] 同步提交斩击节点，空棋盘位置不会消耗冷却，允许预判空列。
func execute(context: CharacterSkillContext) -> bool:
	if context == null:
		return false
	var battle: RepeaterShotContext = context.state_source() # 异步落斩及灼烧共用本局边界。
	if battle == null:
		return false
	var cells: Array[PlantCell] = _column_cells(context.board) # 在出手时冻结逻辑列身份。
	if cells.is_empty():
		return false
	var slash := Slash.new(battle, context, cells) # 列地块提供落点，命中由峰值刀光的真实轮廓决定。
	context.game.bombs.add_child(slash)
	return true

## 从 [param board] 读取真实存在的目标列地块，稀疏棋盘上的缺格保留为空。
func _column_cells(board: BoardRuntime) -> Array[PlantCell]:
	var cells: Array[PlantCell] = [] # 按攻击行排序，供视觉与命中共用。
	var column: int = board.extent.y - COLUMN_FROM_RIGHT # 随棋盘布局变化并保留真实逻辑列。
	if column < 0:
		return cells
	for lane: int in range(board.extent.x): # 每行最多取得一个实际可见地块。
		var cell: PlantCell = board.cell_at(Vector2i(lane, column)) # 缺格或待删除格不参与。
		if is_instance_valid(cell) and cell.is_visible_in_tree():
			cells.append(cell)
	return cells
