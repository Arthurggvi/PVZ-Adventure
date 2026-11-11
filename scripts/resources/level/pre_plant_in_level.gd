extends Resource
class_name PrePlantResource
## 关卡预种植植物数据

## 植物类型
@export var plant_type :CharacterRegistry.PlantType
## 可选稳定地块 ID；非空时忽略旧行列选择器。
@export var cell_id: StringName = &""
## 植物位置
@export var plant_cell_pos:Vector2i
## 是否为模仿者植物
@export var is_imitater_plant:bool = false
