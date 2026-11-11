## 离散种植点定义；身份、逻辑地址与平台内像素坐标彼此独立。
extends Resource
class_name BoardCellDefinition

## 稳定身份；改坐标/数组顺序不得改此 ID。
@export var cell_id: StringName = &""
## 逻辑地址：x 为攻击行，y 为拓扑列；允许列号留空。
@export var address := Vector2i.ZERO
## 所属刚性种植平台；同一多格植物必须全部位于同平台。
@export var surface_id: StringName = &"ground"
## 所属平台局部坐标中的交互矩形左上角，单位像素。
@export var position := Vector2.ZERO
## 种植点交互矩形的宽高，单位像素；不缩放植物美术。
@export var size := Vector2(76.0, 95.0)
## 对应 BoardDefinition.terrains 中的能力定义。
@export var terrain_id: StringName = &"grass"
## 可选局部交互多边形；空值使用矩形，顶点须位于 size 内。
@export var hit_polygon := PackedVector2Array()
## 检测器相对表现的地面高度修正，单位像素；不从种植点 Y 坐标推导。
@export var ground_height: float = 0.0
## 非规则邻接；开启后空列表表示孤立点。
@export var explicit_neighbors: bool = false
## 一步邻接的稳定 ID；只定义同平台逻辑关系。
@export var neighbor_ids: Array[StringName] = []
## 多格植物向右扩展的显式邻格；空值按 address.y + 1 查询。
@export var right_neighbor_id: StringName = &""
