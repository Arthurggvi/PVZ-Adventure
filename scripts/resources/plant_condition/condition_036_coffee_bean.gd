extends ResourcePlantCondition
class_name ResourcePlantConditionCoffeeBean


## [param plant_cell] 的普通层或伴生层存在睡眠植物时才可种植，复用实际唤醒的目标查询。
func _judge_special_plants_condition(plant_cell: PlantCell) -> bool:
	return is_instance_valid(plant_cell) and plant_cell.sleeping_plant() != null
