## 咖啡预览与真实提交共用同一目标计划；规则由冻结卡片投影，不改共享资源。
extends ResourcePlantCondition
class_name ResourcePlantConditionCoffeeBean

## 当前卡片独立的咖啡规则，空字典保留原生睡眠蘑菇资格。
var coffee_rules: Dictionary = {}

## 判断 [param plant_cell] 的中心或范围是否存在可作用目标；不消耗任何资源。
func _judge_special_plants_condition(plant_cell: PlantCell) -> bool:
	return CoffeeBeanUsePlan.prepare(plant_cell, coffee_rules).has_effect()
