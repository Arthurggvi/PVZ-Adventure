## 寄生书为当前出战卡开放水域叠种；普通海草继续使用原生种植条件。
extends ResourcePlantCondition
class_name ResourcePlantConditionTanglekelp

## 复生和已有实体搬迁继续使用原生种植条件。
var _native: ResourcePlantCondition

## [param native] 提供原生种植条件；无参构造供 Godot 复制 Resource。
func _init(native: ResourcePlantCondition = null) -> void:
	_native = native if native != null else ResourcePlantCondition.new()
	plant_condition = _native.plant_condition
	place_plant_in_cell = _native.place_plant_in_cell
	required_terrain_tags = _native.required_terrain_tags.duplicate()
	forbidden_terrain_tags = _native.forbidden_terrain_tags.duplicate()

## [param cell] 有可寄生的水域宿主时使用临时悬浮槽，空水面仍走普通槽。
func placement_slot(cell: PlantCell) -> CharacterRegistry.PlacePlantInCell:
	return CharacterRegistry.PlacePlantInCell.Float if parasite_host(cell) != null else place_plant_in_cell

## [param cell] 和 [param species] 沿用预览与提交共用的地形约束；[param companion] 按原生规则预检。
func judge_is_can_plant(cell: PlantCell, species: CharacterRegistry.PlantType,
		companion: bool = false) -> bool:
	if not companion and parasite_host(cell) != null:
		return _terrain_allows_footprint(cell, placement_cells(cell))
	return super.judge_is_can_plant(cell, species, companion)

## [param plant] 搬到 [param cell] 的 [param footprint] 时按原有槽位规则；[param companion] 为原伴生层。
func judge_relocation_allowed(cell: PlantCell, footprint: Array[PlantCell], plant: Plant000Base,
		companion: bool) -> bool:
	return _native.judge_relocation_allowed(cell, footprint, plant, companion)

## 在 [param cell] 复生 [param species] 使用原海草种植资格，避免重新施加寄生。
func judge_revival_allowed(cell: PlantCell, species: CharacterRegistry.PlantType) -> bool:
	return _native.judge_revival_allowed(cell, species)

## [param cell] 的可寄生对象按前排优先选取；同一宿主只能承接一次寄生。
static func parasite_host(cell: PlantCell) -> Plant000Base:
	if not is_instance_valid(cell) or not cell.can_common_plant \
			or cell.get_spawn_terrain_type() != CharacterRegistry.ZombieRowType.Pool \
			or is_instance_valid(cell.plant_in_cell.get(CharacterRegistry.PlacePlantInCell.Float)):
		return null
	for slot: CharacterRegistry.PlacePlantInCell in [CharacterRegistry.PlacePlantInCell.Shell,
			CharacterRegistry.PlacePlantInCell.Norm]: # 保护壳先于主植物承受普通啃食。
		var candidate: Variant = cell.plant_in_cell.get(slot) # 先验证可能已被释放的瞬时槽位引用。
		if _eligible_host(candidate):
			return candidate as Plant000Base
	var companion: Plant000Base = cell.first_companion_plant(_eligible_host) # 没有前排时同样可寄生伴生植物。
	if companion != null:
		return companion
	var support: Plant000Base = cell.get_support_plant() # 独立的睡莲也是水域植物。
	return support if _eligible_host(support) else null

## [param candidate] 必须为可承接受击的活体友军，排除海草自身和已寄生宿主。
static func _eligible_host(candidate: Variant) -> bool:
	if not is_instance_valid(candidate):
		return false
	var plant := candidate as Plant000Base # 通过引用校验后再验证真实物种和生命周期。
	return plant != null and not plant.is_death and not plant.is_hypno \
		and not plant.is_queued_for_deletion() and plant.is_inside_tree() \
		and plant.spawn_species_id() != CharacterRegistry.PlantType.P020TangleKelp \
		and not plant.has_node(NodePath(AdventureTanglekelpParasite.NODE_NAME))
