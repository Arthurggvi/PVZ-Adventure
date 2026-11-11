## 关卡空间的唯一静态定义；原场景与自定义布局共用 BoardRuntime。
extends Resource
class_name BoardDefinition

## 布局稳定身份，不能使用展示名称或数组索引代替。
@export var board_id: StringName = &""
## 不兼容的地块/行拓扑变更应递增，读档拒绝错版恢复。
@export_range(1, 1000000) var revision: int = 1
## 逻辑攻击行及其生成标记。
@export var lanes: Array[BoardLaneDefinition] = []
## 可以独立运动的平台；移动不隐式更换攻击行。
@export var surfaces: Array[BoardSurfaceDefinition] = []
## 稀疏种植点，不要求矩阵或相同尺寸。
@export var cells: Array[BoardCellDefinition] = []
## 本布局可使用及切换到的地形目录。
@export var terrains: Array[BoardTerrainDefinition] = []

## 返回实际种植点定义；规则网格子类仅覆盖此展开接口。
func cell_definitions() -> Array[BoardCellDefinition]:
	return cells

## 返回实际攻击行；允许生成器展开，不依赖战斗场景节点数量。
func lane_definitions() -> Array[BoardLaneDefinition]:
	return lanes

## 校验完整静态引用，错误布局不允许部分装配。
func validate() -> PackedStringArray:
	return BoardDefinitionValidator.validate(self)
