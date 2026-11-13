## 蘑菇物种与实际在场查询；光环和群落共用，不以当前睡眠状态辨认物种。
extends RefCounted
class_name MushroomPlantQuery

## 包含未标注日眠的忧郁菇、金磁，以及模仿者目标物种可解析的原版蘑菇。
const SPECIES: Array[int] = [9, 10, 11, 13, 14, 15, 16, 25, 32, 43, 46]

## [param plant] 按真实生成物种判断；原生日眠标记兼容后续注册的蘑菇。
static func is_mushroom(plant: Plant000Base) -> bool:
	return is_instance_valid(plant) and (
		SPECIES.has(plant.spawn_species_id()) or plant.native_day_sleep)

## [param plant] 必须仍在 [param game] 的有效地格内，且可以提供战斗词条。
## 保留平台平移和同帧承托重挂的格子身份，不按像素距离重新寻找归属。
static func is_active(plant: Plant000Base, game: MainGameManager) -> bool:
	if not is_instance_valid(plant) or not is_instance_valid(game) \
			or plant.is_death or plant.is_queued_for_deletion() or not plant.is_inside_tree() \
			or game.is_queued_for_deletion() or not game.is_inside_tree() or game != Global.main_game \
			or game.get_tree().current_scene != game or not game.is_ancestor_of(plant) \
			or game.board == null or plant.process_mode == Node.PROCESS_MODE_DISABLED \
			or plant.character_init_type != Character000Base.E_CharacterInitType.IsNorm \
			or plant.has_node(NodePath(AdventurePlantNullification.NODE_NAME)):
		return false
	var cell: PlantCell = plant.plant_cell # 当前实际登记格；伴生植株也由living_plants覆盖。
	return is_instance_valid(cell) and not cell.is_queued_for_deletion() \
		and cell.board == game.board and cell.living_plants().has(plant)

## 统计 [param plant] 在 [param game] 中自身九宫格内的不同蘑菇物种，包含自身。
static func species_count(plant: Plant000Base, game: MainGameManager) -> int:
	if not is_instance_valid(plant) or not is_instance_valid(game) or game.board == null \
			or not is_instance_valid(plant.plant_cell) or plant.plant_cell.board != game.board:
		return 0
	var species: Dictionary[int, bool] = {} # 同种不同卡牌、星级和伴生身份均只计一次。
	for cell: PlantCell in game.board.neighbors(plant.plant_cell): # 邻接查询含中心格并适配移动平台。
		if not is_instance_valid(cell) or cell.is_queued_for_deletion():
			continue
		for target: Plant000Base in cell.living_plants(): # 已死或真正离场的实体不会被计入。
			if is_mushroom(target):
				species[target.spawn_species_id()] = true
	return species.size()
