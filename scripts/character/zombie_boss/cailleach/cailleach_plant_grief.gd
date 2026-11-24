## 悲寒独立保存在原株身上，满层封锁行动但保留受击及种植格占用。
extends Node

## 每株至多一个悲寒来源，同场不同妇人可以叠到同一株。
const NODE_NAME := &"CailleachPlantGrief"
## 每层减少十分之一的行动速度；达到上限时完全停止。
const MAX_STACKS: int = 10
## 只有实际有悲寒时才读取植物滤镜。
const PALETTE_PATH := "res://shaders/adventure/wonderland/cailleach_grief.gdshader"
## 同一脚本资源创建首个状态，避免引入全局类缓存依赖。
const STATE_PATH := "res://scripts/character/zombie_boss/cailleach/cailleach_plant_grief.gd"

## 当前植物。
var _plant: Plant000Base
## 视觉与倍率共用的层数。
var _stacks: int = 0
## 只由当前植物拥有的可变颜色材质。
var _palette: ShaderMaterial
## 保留每个身体部件的原材质与继承方式，净化时逐项还原。
var _painted: Dictionary[CanvasItem, Array] = {}

## 为 [param plant] 加 [param count] 层；场上已有的同一来源合并计算。
static func apply_to(plant: Plant000Base, count: int) -> bool:
	if count <= 0 or not plant.can_receive_cold():
		return false
	var state := plant.get_node_or_null(NodePath(NODE_NAME)) # 只读取当前原株的层数。
	if state == null:
		state = (load(STATE_PATH) as Script).new()
		state.name = NODE_NAME
		state._plant = plant
		plant.add_child(state)
		state._palette = ShaderMaterial.new()
		state._palette.shader = load(PALETTE_PATH) as Shader
		state._palette.set_shader_parameter(&"imitater", plant.is_imitater_material)
	return state._add(count)

## 返回 [param plant] 当前是否已经达到完全悲寒。普通冻结另由冰壳及寒冷系统判断。
static func is_complete(plant: Plant000Base) -> bool:
	var state: Node = plant.get_node_or_null(NodePath(NODE_NAME)) # 无状态的普通植株无需创建节点。
	return state != null and state._stacks == MAX_STACKS

## 清除 [param plant] 的悲寒来源，并恢复原画材质。
static func clear_from(plant: Plant000Base) -> void:
	var state: Node = plant.get_node_or_null(NodePath(NODE_NAME)) # 允许净化在末次命中之前或之后执行。
	if state != null:
		state._clear()

## 增加 [param count] 层，变化后将累计倍率和冷色同时提交。
func _add(count: int) -> bool:
	var next: int = mini(MAX_STACKS, _stacks + count) # 十层以后不重复冻结组件。
	if next == _stacks:
		return false
	_stacks = next
	var strength: float = float(_stacks) / MAX_STACKS # 每层都从相同上限计算，无乘法叠减误差。
	_palette.set_shader_parameter(&"sorrow", strength)
	for item: CanvasItem in _plant.body.find_children("*", "CanvasItem", true, false): # 仅绘制部件，保留原骨骼和动画脚本。
		if not (item is Sprite2D or item is AnimatedSprite2D or item is Polygon2D or item is MeshInstance2D):
			continue
		if not _painted.has(item):
			_painted[item] = [item.material, item.use_parent_material]
		item.use_parent_material = false
		item.material = _palette
	_plant.set_action_slowdown(get_instance_id(), 1.0 - strength, true)
	if _stacks == MAX_STACKS:
		AdventurePlantNullification.grant(_plant, get_instance_id(), false)
	return true

## 从本株撤销自己的动作倍率、活动封锁及冷色材质。
func _clear() -> void:
	_plant.set_action_slowdown(get_instance_id(), 1.0)
	AdventurePlantNullification.release(_plant, get_instance_id(), false)
	for item: Variant in _painted: # 在净化前自行移除的老动画部件不再访问。
		if is_instance_valid(item) and item.material == _palette:
			item.material = _painted[item][0]
			item.use_parent_material = _painted[item][1]
	_plant.remove_child(self)
	queue_free()
