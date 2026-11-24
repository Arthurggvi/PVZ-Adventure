extends Resource
class_name ResourcePlantCondition

## 额外需要的地形能力标签；空数组保持全部原植物行为。
@export var required_terrain_tags: Array[StringName] = []
## 明确禁止的地形能力标签，不与原种植能力位混用。
@export var forbidden_terrain_tags: Array[StringName] = []
## 该物种与墓碑共占且依赖墓碑存在；恢复计划据此验证结构关系。
@export var requires_tombstone: bool = false

@export_group("植物种植")
@export_flags("1 无", "2 草地", "4 花盆", "8 水", "16 睡莲", "32 屋顶/裸地")
## 植物种植地形条件（满足一个即可），默认（草地2+花盆4+睡莲16 = 22）
var plant_condition:int = 22

## 植物在格子中占的位置，
@export var place_plant_in_cell :CharacterRegistry.PlacePlantInCell = CharacterRegistry.PlacePlantInCell.Norm

## 是否为特殊植物，非特殊植物满足上面两点（地形条件、格子位置）种植即可,
## 特殊植物调用重写方法判断是否可以种植judge_special_plants_condition
@export var is_special_plants := false
## 是否为紫卡  紫卡非特殊植物, 特殊植物只走特殊植物判定方法,特殊紫卡(玉米炮)走特殊植物判定方法
@export var is_purple_card := false
### 是否为双格植物,用于南瓜壳判断是否可以种植
#@export var is_double_plant_cell:=false


## One footprint contract for preview, placement, transformation and save restore.
## A subclass only describes geometry, never mutates cells or destroys plants.
func placement_cells(cell: PlantCell) -> Array[PlantCell]:
	return [cell]


## 返回面向 [param _cell] 的实际种植槽，预览和放置事务共用。
func placement_slot(_cell: PlantCell) -> CharacterRegistry.PlacePlantInCell:
	return place_plant_in_cell

## Additional restrictions for footprints (e.g. two-column cannon needs clear shells).
func upgrade_footprint_available(_cells: Array[PlantCell]) -> bool:
	return true

## Resolve every predecessor before placement; an empty result means invalid.
## Entries carry the owning cell and the actual slot, so upgrades can span cells.
func get_upgrade_claims(cell: PlantCell, plant_type: CharacterRegistry.PlantType) -> Array[Dictionary]:
	var claims: Array[Dictionary] = []
	if not is_purple_card or not Global.character_registry.AllPrePlantPurple.has(plant_type):
		return claims
	var predecessor_type: CharacterRegistry.PlantType = Global.character_registry.AllPrePlantPurple[plant_type]
	var predecessor_condition: ResourcePlantCondition = Global.character_registry.get_plant_info(
		predecessor_type, CharacterRegistry.PlantInfoAttribute.PlantConditionResource)
	if predecessor_condition == null:
		return claims
	var cells: Array[PlantCell] = placement_cells(cell)
	if cells.is_empty() or not upgrade_footprint_available(cells):
		return claims
	for target: PlantCell in cells:
		if not is_instance_valid(target):
			return []
		var source_slot: CharacterRegistry.PlacePlantInCell = predecessor_condition.place_plant_in_cell
		var predecessor: Plant000Base = target.plant_in_cell.get(source_slot)
		if not is_instance_valid(predecessor) or predecessor.is_queued_for_deletion() \
				or predecessor.plant_type != predecessor_type:
			return []
		var destination: Plant000Base = target.plant_in_cell.get(place_plant_in_cell)
		if is_instance_valid(destination) and destination != predecessor:
			return []
		claims.append({"cell": target, "slot": source_slot, "plant": predecessor})
	return claims

## 在 [param plant_cell] 预检 [param curr_plant_type]；[param companion] 仅为单格普通植物跳过种植位冲突。
## 伴生仍遵守地形、承托、障碍与禁种，不适用于升级、特殊植物或承托层。
func judge_is_can_plant(plant_cell: PlantCell, curr_plant_type: CharacterRegistry.PlantType,
		companion: bool = false) -> bool:
	if not is_instance_valid(plant_cell):
		return false
	var footprint: Array[PlantCell] = placement_cells(plant_cell) # 预览与事务使用同一占用声明。
	if footprint.is_empty():
		return false
	if companion and (is_purple_card or is_special_plants or footprint.size() != 1 \
			or place_plant_in_cell != CharacterRegistry.PlacePlantInCell.Norm):
		return false
	if not _terrain_allows_footprint(plant_cell, footprint):
		return false
	if is_purple_card:
		var cells: Array[PlantCell] = placement_cells(plant_cell)
		if cells.is_empty():
			return false
		for cell: PlantCell in cells:
			if not is_instance_valid(cell) or not cell.can_common_plant \
					or not (plant_condition & cell.curr_condition):
				return false
		return get_upgrade_claims(plant_cell, curr_plant_type).size() == cells.size()
	if is_special_plants:
		return judge_special_plants_condition(plant_cell)
	if not plant_cell.can_common_plant or not (plant_condition & plant_cell.curr_condition):
		return false
	if not companion and is_instance_valid(plant_cell.plant_in_cell[place_plant_in_cell]):
		return false
	## A shell cannot cover a plant occupying multiple cells, regardless of species.
	if place_plant_in_cell == CharacterRegistry.PlacePlantInCell.Shell:
		var occupant: Plant000Base = plant_cell.plant_in_cell[CharacterRegistry.PlacePlantInCell.Norm]
		if is_instance_valid(occupant) and is_instance_valid(occupant.plant_cell):
			var occupant_condition: ResourcePlantCondition = Global.character_registry.get_plant_info(
				occupant.spawn_species_id(), CharacterRegistry.PlantInfoAttribute.PlantConditionResource)
			if occupant_condition != null and occupant_condition.placement_cells(occupant.plant_cell).size() > 1:
				return false
	return true

## 验证 [param footprint] 内各地块与 [param origin] 同一战场与平台，且满足种植能力标签。
func _terrain_allows_footprint(origin: PlantCell, footprint: Array[PlantCell]) -> bool:
	for target: PlantCell in footprint: # 每个实际占格都要能承载这株植物。
		if not is_instance_valid(target) or target.board != origin.board:
			return false
		if origin.board_definition != null and (target.board_definition == null \
			or target.board_definition.surface_id != origin.board_definition.surface_id):
			return false
		if not target.is_terrain_planting_allowed():
			return false
		for tag: StringName in required_terrain_tags: # 地块必须满足全部所需能力。
			if target.board_terrain == null or not target.board_terrain.tags.has(tag):
				return false
		for tag: StringName in forbidden_terrain_tags: # 命中任一禁用能力即拒绝。
			if target.board_terrain != null and target.board_terrain.tags.has(tag):
				return false
	return true

## 在 [param cell] 以 [param footprint] 安置已有 [param plant]；[param companion] 沿用伴生的独立名额。
## 已升级的植物免除升级前置，多格范围允许覆盖它自己原有的占格。
func judge_relocation_allowed(cell: PlantCell, footprint: Array[PlantCell], plant: Plant000Base,
		companion: bool) -> bool:
	if not is_purple_card:
		return judge_is_can_plant(cell, plant.plant_type, companion)
	if not _terrain_allows_footprint(cell, footprint) or not upgrade_footprint_available(footprint):
		return false
	for target: PlantCell in footprint: # 覆盖其他植物或壳层仍按实际格子阻挡。
		var occupant: Plant000Base = target.plant_in_cell.get(place_plant_in_cell) # 原株自身可在重叠格继续占位。
		if not target.can_common_plant or not (plant_condition & target.curr_condition) \
				or (is_instance_valid(occupant) and occupant != plant):
			return false
	return true

## 在 [param cell] 复生 [param species] 按普通占位，只免除已完成的紫卡前置；空间资格照常验证。
## 临时条件副本只关闭升级分支，不修改注册表共享资源或调用方的冻结配方。
func judge_revival_allowed(cell: PlantCell, species: CharacterRegistry.PlantType) -> bool:
	if not is_instance_valid(cell):
		return false
	var cells: Array[PlantCell] = placement_cells(cell) # 使用与普通种植相同的完整空间声明。
	if cells.is_empty() or not upgrade_footprint_available(cells) \
			or not cell._placement_is_available(place_plant_in_cell, cells, []):
		return false
	if not is_purple_card:
		return judge_is_can_plant(cell, species)
	for target: PlantCell in cells: # 紫卡的所有占用格都需要实际地形和空闲位置，不能只检查原点。
		if not is_instance_valid(target) or not target.can_common_plant \
				or not (plant_condition & target.curr_condition):
			return false
	var restored: ResourcePlantCondition = duplicate() as ResourcePlantCondition # 复制参数，不产生场景实体或前置副作用。
	if restored == null:
		return false
	restored.is_purple_card = false
	restored.is_special_plants = false
	return restored.judge_is_can_plant(cell, species)

func judge_purple_card_can_plant(all_plant_cells, curr_plant_type: CharacterRegistry.PlantType) -> bool:
	for cells: Array in all_plant_cells:
		for cell: PlantCell in cells:
			if judge_is_can_plant(cell, curr_plant_type):
				return true
	return false


## 获取当前场上所有的紫卡植物的对应预种植植物
func get_all_preplant_purple(all_plant_cells, curr_plant_type:CharacterRegistry.PlantType):
	var all_preplant_purple:Array[Plant000Base]
	for plant_cells_row in all_plant_cells:
		for plant_cell: PlantCell in plant_cells_row:
			if not judge_is_can_plant(plant_cell, curr_plant_type):
				continue
			for claim: Dictionary in get_upgrade_claims(plant_cell, curr_plant_type):
				var predecessor: Plant000Base = claim["plant"]
				if not all_preplant_purple.has(predecessor):
					all_preplant_purple.append(predecessor)

	return all_preplant_purple

## 一般特殊植物(不能有同一位置植物)种植函数判断是否可以种植
func judge_special_plants_condition(plant_cell:PlantCell) -> bool:
	if is_instance_valid(plant_cell.plant_in_cell[place_plant_in_cell]):
		return false
	else:
		return _judge_special_plants_condition(plant_cell)

## 特殊植物种植函数判断是否可以种植，特殊植物重写,如墓碑吞噬者，咖啡豆等
func _judge_special_plants_condition(_plant_cell) -> bool:
	return true
