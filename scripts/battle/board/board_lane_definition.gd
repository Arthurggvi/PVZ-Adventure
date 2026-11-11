## 僵尸攻击行与种植点分离；坐标均为主战场局部像素。
extends Resource
class_name BoardLaneDefinition

## 稳定行身份；数组顺序是兼容原战斗内核的零起点行号。
@export var lane_id: StringName = &""
## 出生标记坐标；不会随种植平台移动。
@export var spawn_position := Vector2(850.0, 150.0)
## 本行可生成的水陆类别；混合地形可用 Both，入水仍走 WaterBodyArea。
@export var spawn_type: CharacterRegistry.ZombieRowType = CharacterRegistry.ZombieRowType.Land
## 清洁车位置，独立于植物是否存在及其坐标。
@export var mower_position := Vector2(20.0, 150.0)
## 清洁车类型：0 草地、1 水池、2 屋顶。
@export_range(0, 2) var mower_kind: int = 0
