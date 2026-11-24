## 猎人的只读索敌；沿用棋盘实际格宽与现有同格保护层，不建立第二份植物列表。
extends RefCounted
class_name HunterThrowTarget

## 雪球可以碰到普通与低矮植物，不把地下地刺或悬浮层当作地面投掷目标。
const PLANT_STATUSES: int = 9

## 从 [param game] 的同路选择 [param source] 身前 [param reach_cells] 格内最近一株。
## 已冰封的前排仍然返回，调用者据此停投接近，不能隔着冰壳瞄准后排。
static func nearest(source: Zombie000Base, game: MainGameManager, reach_cells: float) -> Plant000Base:
	if game.board == null or source.lane < 0:
		return null
	var width: float = game.board.cell_width_at(source.global_position, source.lane) # 当前实际格宽，兼容不同关卡布局。
	var nearest_distance: float = width * reach_cells # 候选只允许在本物种射程内。
	var result: Plant000Base = null # 没有存活合法候选时明确返回空引用。
	var detector: DetectComponent = source.attack_component.detect_component # 复用同格南瓜、普通、伴生、底座的既有优先级。
	for cell: PlantCell in game.board.row_cells(source.lane): # 仍按原始行登记顺序检查每一个地块。
		var first: Plant000Base = null # 只需要原始活体顺序的第一株，不生成两份整格植物数组。
		for reference: Variant in cell.plant_in_cell.values(): # 与 PlantCell.plant_entities 的占位层枚举顺序一致。
			if not is_instance_valid(reference):
				continue
			var plant: Plant000Base = reference as Plant000Base # 不读取已释放实例的生命周期字段。
			if plant != null and plant.is_inside_tree() and not plant.is_death and not plant.is_queued_for_deletion():
				first = plant
				break
		if first == null:
			first = cell.first_companion_plant() # 原顺序只有占位层无活株时才读取伴生层。
		if first == null:
			continue
		var candidate: Plant000Base = detector.get_first_be_hit_plant_in_cell(first) # 保护壳优先级由原组件决定。
		if not is_instance_valid(candidate) or candidate.lane != source.lane \
				or candidate.is_death or candidate.is_queued_for_deletion() \
				or not candidate.hurt_box_component.is_enabling \
				or (candidate.curr_be_attack_status & PLANT_STATUSES) == 0:
			continue
		var distance: float = source.global_position.x - candidate.global_position.x # 猎人未魅惑时只面向左侧。
		if distance > 0.0 and distance <= nearest_distance:
			nearest_distance = distance
			result = candidate
	return result
