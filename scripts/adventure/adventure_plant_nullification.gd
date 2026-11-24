## 按来源登记植物活动封锁，同时保留受击、铲除和外部移除入口。
extends Node
class_name AdventurePlantNullification

## 每株植物只有一个无效化状态节点。
const NODE_NAME := &"AdventurePlantNullification"
## 限时眩晕独占来源位，普通无效化要求非零来源 ID。
const STUN_SOURCE := 0
## 状态所封锁的植物。
var _plant: Plant000Base
## 各外部来源是否使用黑色外观，最后一个移除时恢复植物。
var _sources: Dictionary[int, bool] = {}
## 眩晕剩余的游戏秒数。植物被封锁时由显式可暂停的计时器继续计时。
var _stun_timer: Timer
## 植物原进程模式。
var _original_process_mode: Node.ProcessMode
## 应用黑色外观前的颜色。
var _original_modulate: Color
## HP 组件在封锁前的进程模式。
var _hp_process_mode: Node.ProcessMode
## 受击框在封锁前的进程模式。
var _hurt_process_mode: Node.ProcessMode
## 承托容器中是另外的植物；底座被封锁时它们继续按各自的状态推进。
var _support_contents: Node2D

## 为 [param plant] 登记 [param source_id]；[param darken] 关闭时由该状态自己表现颜色。
static func grant(plant: Plant000Base, source_id: int, darken: bool = true) -> void:
    if not is_instance_valid(plant) or plant.is_death or not plant.can_receive_control_effects():
        return
    _for(plant)._add_source(source_id, darken)

## 使 [param plant] 眩晕 [param seconds] 个战斗秒，与其他活动封锁独立。
static func grant_stun(plant: Plant000Base, seconds: float) -> void:
    if not is_instance_valid(plant) or not plant.is_inside_tree() or plant.is_death or not plant.can_receive_control_effects():
        return
    var state: AdventurePlantNullification = _for(plant) # 共用进程封锁及其恢复快照。
    state._add_source(STUN_SOURCE, false)
    if state._stun_timer == null:
        state._stun_timer = Timer.new()
        state._stun_timer.one_shot = true
        state._stun_timer.process_mode = Node.PROCESS_MODE_PAUSABLE
        state.add_child(state._stun_timer)
        state._stun_timer.timeout.connect(release.bind(plant, STUN_SOURCE, false))
    state._stun_timer.start(maxf(seconds, state._stun_timer.time_left))

## 取得 [param plant] 的封锁状态，首次应用时保存恢复值。
static func _for(plant: Plant000Base) -> AdventurePlantNullification:
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
        var support := plant as Plant000DownBase # 承托层不是底座自身的动作子组件。
        if support != null and support.down_plant_container.process_mode == Node.PROCESS_MODE_INHERIT:
            state._support_contents = support.down_plant_container
            state._support_contents.process_mode = Node.PROCESS_MODE_PAUSABLE
        plant.process_mode = Node.PROCESS_MODE_DISABLED
    return state

## 记录 [param source_id] 的封锁；[param darken] 指明是否使用焦黑外观。
func _add_source(source_id: int, darken: bool) -> void:
    _sources[source_id] = darken
    _update_appearance()

## 无效化使用原有焦黑；眩晕只短暂改变色调。
func _update_appearance() -> void:
    _plant.modulate = _original_modulate
    if _sources.values().has(true):
        _plant.modulate = Color(0, 0, 0, _original_modulate.a)
    elif _sources.has(STUN_SOURCE):
        _plant.modulate *= Color(0.72, 0.61, 0.63, 1.0)

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
    else:
        state._update_appearance()

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
    if is_instance_valid(_support_contents):
        _support_contents.process_mode = Node.PROCESS_MODE_INHERIT
    _plant.modulate = _original_modulate
    _plant.remove_child(self)
    queue_free()
