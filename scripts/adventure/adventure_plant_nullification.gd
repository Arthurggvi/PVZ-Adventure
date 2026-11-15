## 按来源登记植物活动封锁，同时保留受击、铲除和外部移除入口。
extends Node
class_name AdventurePlantNullification

## 每株植物只有一个无效化状态节点。
const NODE_NAME := &"AdventurePlantNullification"
## 状态所封锁的植物。
var _plant: Plant000Base
## 各梯子等独立来源，最后一个移除时恢复植物。
var _sources: Dictionary[int, bool] = {}
## 植物原进程模式。
var _original_process_mode: Node.ProcessMode
## 应用黑色外观前的颜色。
var _original_modulate: Color
## HP 组件在封锁前的进程模式。
var _hp_process_mode: Node.ProcessMode
## 受击框在封锁前的进程模式。
var _hurt_process_mode: Node.ProcessMode

## 为 [param plant] 登记 [param source_id]；只在第一份来源生效时冻结恢复数据。
static func grant(plant: Plant000Base, source_id: int) -> void:
    if not is_instance_valid(plant) or plant.is_death:
        return
    var state: AdventurePlantNullification = plant.get_node_or_null( # 同一植物共享恢复快照。
            NodePath(NODE_NAME)) as AdventurePlantNullification
    if state == null:
        state = AdventurePlantNullification.new()
        state.name = NODE_NAME
        plant.add_child(state)
        state._plant = plant
        state._original_process_mode = plant.process_mode
        state._original_modulate = plant.modulate
        state._hp_process_mode = plant.hp_component.process_mode
        state._hurt_process_mode = plant.hurt_box_component.process_mode
        plant.hp_component.process_mode = Node.PROCESS_MODE_ALWAYS
        plant.hurt_box_component.process_mode = Node.PROCESS_MODE_ALWAYS
        plant.process_mode = Node.PROCESS_MODE_DISABLED
        plant.modulate = Color(0, 0, 0, plant.modulate.a)
    state._sources[source_id] = true

## 移除 [param plant] 的 [param source_id]；[param persistent] 表示解除来源时保留状态。
static func release(plant: Plant000Base, source_id: int, persistent: bool) -> void:
    if not is_instance_valid(plant):
        return
    var state: AdventurePlantNullification = plant.get_node_or_null( # 查找当前有效的封锁记录。
            NodePath(NODE_NAME)) as AdventurePlantNullification
    if state == null:
        return
    if persistent:
        return
    state._sources.erase(source_id)
    if state._sources.is_empty():
        state._restore()

## 净化 [param plant] 的全部无效化来源，包括保留的永久来源。
static func purge(plant: Plant000Base) -> void:
    if not is_instance_valid(plant):
        return
    var state := plant.get_node_or_null(NodePath(NODE_NAME)) as AdventurePlantNullification # 只有登记状态持有原模式。
    if state != null:
        state._restore()

## 恢复进程与颜色后立即摘除状态，允许同帧新来源重新登记。
func _restore() -> void:
    _plant.process_mode = _original_process_mode
    _plant.hp_component.process_mode = _hp_process_mode
    _plant.hurt_box_component.process_mode = _hurt_process_mode
    _plant.modulate = _original_modulate
    _plant.remove_child(self)
    queue_free()
