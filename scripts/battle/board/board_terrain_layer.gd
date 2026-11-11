## 可离树准备的地形层；构造失败不会释放旧地形或改写格子能力。
extends Node2D
class_name BoardTerrainLayer

## 目标地块，离树准备时绑定。
var cell: PlantCell
## 本层对应的地形资源。
var terrain: BoardTerrainDefinition
## 已构造的独立行为。
var behavior: BoardTerrainBehavior
## 预检并冻结的行为恢复数据。
var _saved_state: Dictionary = {}
## 仅恢复路径在安装后调用行为恢复。
var _restoring: bool = false

## 验证 [param terrain] 的实例与 [param state]；纯预检结束即释放临时实例。
static func accepts_state(terrain: BoardTerrainDefinition, state: Dictionary) -> bool:
	if terrain == null or not terrain.validate().is_empty():
		return false
	if terrain.behavior_scene == null:
		return state.is_empty()
	var instance: BoardTerrainBehavior = terrain.create_behavior() # 共用类型/可实例化性检查。
	if instance == null:
		return false
	var valid: bool = instance.accepts_state(state) # 扩展必须提供离树纯校验。
	instance.free()
	return valid

## 构造 [param target] 的新地形；[param restoring] 时先验证并复制 [param state]。
## 返回完整离树节点或 null；调用者拥有返回节点，失败不会影响旧层。
static func prepare(target: PlantCell, definition: BoardTerrainDefinition,
		state: Dictionary = {}, restoring: bool = false) -> BoardTerrainLayer:
	if not is_instance_valid(target) or definition == null or not definition.validate().is_empty():
		return null
	var layer := BoardTerrainLayer.new() # 只有准备成功后才能交给格子安装。
	layer.cell = target
	layer.terrain = definition
	layer.name = "TerrainLayer"
	layer.z_index = -1
	layer._saved_state = state.duplicate(true)
	layer._restoring = restoring
	if definition.behavior_scene != null:
		layer.behavior = definition.create_behavior()
		if layer.behavior == null:
			layer.free()
			return null
		layer.behavior.cell = target
		layer.add_child(layer.behavior)
	if restoring and ((layer.behavior == null and not state.is_empty()) \
			or (layer.behavior != null and not layer.behavior.accepts_state(layer._saved_state))):
		layer.free()
		return null
	if definition.water_contact:
		layer.add_child(layer._create_water())
	return layer

## 安装完成后恢复已经验证的行为状态，不在此阶段构造任何资源。
func restore_prepared_state() -> void:
	if _restoring and behavior != null:
		behavior.restore_state(_saved_state)

## 水体与地块共用几何，准备时创建、安装后自动随平台移动。
func _create_water() -> WaterBodyArea:
	if cell.board_definition == null or cell.board_definition.hit_polygon.is_empty():
		return WaterBodyArea.from_region(Rect2(Vector2.ZERO, cell.size))
	var water := WaterBodyArea.new() # 独立水体实例。
	var collision := CollisionPolygon2D.new() # 精确局部多边形。
	collision.polygon = cell.board_definition.hit_polygon
	water.add_child(collision)
	return water
