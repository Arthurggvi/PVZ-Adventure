extends Plant000Base
class_name Plant000DownBase

## 底层承托植物（睡莲/花盆）的通用基类。
## 承托物提供上层植物随动容器；格子种植条件由 PlantCell 在事务提交/释放时统一更新。
@onready var down_plant_container: Node2D = $DownPlantContainer

## 上层植物相对原种植锚点的抬升距离。
@export var plant_up_position: Vector2
