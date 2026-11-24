## 关卡空间的唯一静态定义；原场景与自定义布局共用 BoardRuntime。
extends Resource
class_name BoardDefinition

## 布局稳定身份，不能使用展示名称或数组索引代替。
@export var board_id: StringName = &""
## 不兼容的地块/行拓扑变更应递增，读档拒绝错版恢复。
@export_range(1, 1000000) var revision: int = 1
## 逻辑攻击行及其生成标记。
@export var lanes: Array[BoardLaneDefinition] = []
## 可以独立运动的平台；攻防行只有在显式启用脚点投影时才随动。
@export var surfaces: Array[BoardSurfaceDefinition] = []
## 稀疏种植点，不要求矩阵或相同尺寸。
@export var cells: Array[BoardCellDefinition] = []
## 本布局可使用及切换到的地形目录。
@export var terrains: Array[BoardTerrainDefinition] = []
## 入场加速启用时，以最后一列左界为终点，只加快敌人的移动。
@export var accelerate_entry_from_last_column: bool = false
## 开启时平台上植株按当前脚点就近匹配固定进攻线；格子身份、占用与拓扑地址仍然稳定。
@export var project_surface_combat_lanes: bool = false

## 返回实际种植点定义；规则网格子类仅覆盖此展开接口。
func cell_definitions() -> Array[BoardCellDefinition]:
	return cells

## 返回实际攻击行；允许生成器展开，不依赖战斗场景节点数量。
func lane_definitions() -> Array[BoardLaneDefinition]:
	return lanes

## 在构建节点前恢复 [param _snapshot] 可选的关卡拓扑，普通布局无需恢复额外状态。
func apply_saved_topology(_snapshot: Dictionary) -> void:
	pass

## 返回供恢复事务预检的 [param snapshot]。有已知旧版布局的关卡可返回转换后的副本。
## 调用方仍校验所有格子、平台和占用；此处不得更改存档或活棋盘。
func upgrade_saved_state(snapshot: Dictionary) -> Dictionary:
	return snapshot

## 校验完整静态引用，错误布局不允许部分装配。
func validate() -> PackedStringArray:
	return BoardDefinitionValidator.validate(self)
