## Persistent, source-keyed status: disables all plant activity but preserves
## damage/hurtbox and external shovel/removal APIs. Each ladder owns one source.
extends Node
class_name AdventurePlantNullification

const NODE_NAME := &"AdventurePlantNullification"
var _plant: Plant000Base
var _sources: Dictionary[int, bool] = {}
var _original_process_mode: Node.ProcessMode
var _original_modulate: Color
var _hp_process_mode: Node.ProcessMode
var _hurt_process_mode: Node.ProcessMode

static func grant(plant: Plant000Base, source_id: int) -> void:
    if not is_instance_valid(plant) or plant.is_death:
        return
    var state: AdventurePlantNullification = plant.get_node_or_null(
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

static func release(plant: Plant000Base, source_id: int, persistent: bool) -> void:
    if not is_instance_valid(plant):
        return
    var state: AdventurePlantNullification = plant.get_node_or_null(
            NodePath(NODE_NAME)) as AdventurePlantNullification
    if state == null:
        return
    if persistent:
        return
    state._sources.erase(source_id)
    if state._sources.is_empty():
        plant.process_mode = state._original_process_mode
        plant.hp_component.process_mode = state._hp_process_mode
        plant.hurt_box_component.process_mode = state._hurt_process_mode
        plant.modulate = state._original_modulate
        # Detach before deferred deletion: another ladder may be placed
        # within the same frame without inheriting a doomed status node.
        plant.remove_child(state)
        state.queue_free()
