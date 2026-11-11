## 刚性种植平台定义；所有子地块及植物通过节点层级共同移动。
extends Resource
class_name BoardSurfaceDefinition

## 布局内稳定的平台 ID。
@export var surface_id: StringName = &"ground"
## 平台在主战场中的初始坐标，单位像素。
@export var origin := Vector2.ZERO
## 可选往返位移，保持逻辑攻击行不变；零向量为静态平台。
@export var travel_offset := Vector2.ZERO
## 单程移动所需有效战斗秒数；暂停/选卡/阶段间隙不计时。
@export_range(0.01, 3600.0) var travel_seconds: float = 5.0
## 平台上的统一视觉节点，不承担植物逻辑。
@export var visual_scene: PackedScene
