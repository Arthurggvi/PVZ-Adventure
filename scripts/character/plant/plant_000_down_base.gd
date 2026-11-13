## 底座植物拥有实际承托容器，地形与承托归属仍由 PlantCell 管理。
extends Plant000Base
class_name Plant000DownBase

## 承托普通层、壳层及其伴生植物的实际容器。
@onready var down_plant_container: Node2D = $DownPlantContainer
## 被承托层相对地格锚点的高度偏移。
@export var plant_up_position: Vector2

## 返回当前确实由本株承托的活植物，不把同格但未承托的对象算入。
## 承托归属统一读取格子，兼容普通植物、不占位伴生与壳层。
func supported_plants() -> Array[Plant000Base]:
	var result: Array[Plant000Base] = [] # 每个实体最多受益一次。
	if is_death or is_queued_for_deletion() or not is_inside_tree() \
			or not is_instance_valid(plant_cell) or plant_cell.is_queued_for_deletion() \
			or plant_cell.get_support_plant() != self or not is_instance_valid(down_plant_container):
		return result
	for target: Plant000Base in plant_cell.living_plants(): # 格子枚举同时包含正常占用与伴生登记。
		if target != self and target.is_node_ready() and down_plant_container.is_ancestor_of(target) \
				and not result.has(target):
			result.append(target)
	return result
