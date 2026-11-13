extends Plant000Base
class_name Plant999Imitater

## 模仿的植物类型
var imitater_plant_type :CharacterRegistry.PlantType = CharacterRegistry.PlantType.Null
@onready var imitater_effect: Node2D = $ImitaterEffect

func spawn_species_id() -> int:
	return int(imitater_plant_type)


## 更新模仿者植物
func update_imitater():
	## plant_cell创造植物,该函数会先等待一帧,当前模仿者死亡后创建
	plant_cell.imitater_create_plant(imitater_plant_type, true, plant_spawn_profile)
	imitater_effect.visible = true
	imitater_effect.z_index += 1
	imitater_effect.activate_it()
	## 转化中间体的退场不是死亡，避免与完成转化的真实植物重复留尸体。
	death_recording_enabled = false
	character_death_disappear()
