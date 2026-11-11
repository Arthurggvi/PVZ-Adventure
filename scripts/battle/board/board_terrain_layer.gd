## 地块地形实例层，统一承载自定义地形行为与精确水体接触区域。
extends Node2D
class_name BoardTerrainLayer

## 所属地块。
var cell: PlantCell
## 当前独立地形行为，不在资源中保存运行状态。
var behavior: BoardTerrainBehavior
## 当前水体区域。
var _water: WaterBodyArea

## 校验 [param terrain] 的行为根类型，并检查待恢复的 [param state]。
static func accepts_state(terrain: BoardTerrainDefinition, state: Dictionary) -> bool:
	if terrain.behavior_scene == null:
		return state.is_empty()
	var instance: Node = terrain.behavior_scene.instantiate() # 离树预检，不触发地形入场。
	var accepted: bool = instance is BoardTerrainBehavior \
		and (instance as BoardTerrainBehavior).accepts_state(state)
	instance.free()
	return accepted

## 替换 [param terrain] 的实例；无效行为在释放旧实例之前拒绝。
func apply(terrain: BoardTerrainDefinition) -> bool:
	var next: BoardTerrainBehavior # 预先实例化，保证无效类型不会破坏旧地形。
	if terrain.behavior_scene != null:
		var instance: Node = terrain.behavior_scene.instantiate() # 每格独占行为。
		next = instance as BoardTerrainBehavior
		if next == null:
			instance.free()
			return false
	if is_instance_valid(behavior):
		remove_child(behavior)
		behavior.queue_free()
	behavior = next
	if is_instance_valid(_water):
		remove_child(_water)
		_water.queue_free()
	_water = null
	cell.board_terrain = terrain
	cell.plant_cell_type = terrain.presentation_kind as PlantCell.PlantCellType
	cell.init_condition()
	if terrain.water_contact:
		_water = _create_water()
		add_child(_water)
	if behavior != null:
		behavior.cell = cell
		add_child(behavior)
	return true

## 水体几何与交互点来自同一份地块定义，平台移动时共同随动。
func _create_water() -> WaterBodyArea:
	if cell.board_definition == null or cell.board_definition.hit_polygon.is_empty():
		return WaterBodyArea.from_region(Rect2(Vector2.ZERO, cell.size))
	var water := WaterBodyArea.new() # 独立水体，不从背景像素猜测。
	var collision := CollisionPolygon2D.new() # 自定义地块的精确多边形。
	collision.polygon = cell.board_definition.hit_polygon
	water.add_child(collision)
	return water
