extends Resource
class_name ResourceSaveGamePlantCell
## 植物格子存档数据

## 新存档使用稳定地块身份；空值只允许旧布局地址兼容。
@export var cell_id: StringName = &""
## 植物格子的行和列
@export var row_col:Vector2i
## 在当前格子中对应位置的植物 [位置, 植物数据字典]
@export var plant_type_in_cell:Dictionary[CharacterRegistry.PlacePlantInCell, Dictionary] =  {}
## 是否有梯子
@export var is_ladder:bool = false
## Tier-specific planted ladder art; empty is the legacy/original texture.
@export var ladder_tier_id: StringName = &""
