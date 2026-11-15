extends ComponentNormBase
class_name FogClearerComponent

@onready var area_2d_fog_clear: Area2D = $Area2DFogClear

var fog_node:Fog

func _ready() -> void:
	super._ready()
	if is_instance_valid(Global.main_game):
		fog_node = Global.main_game.background_manager.fog
	if is_instance_valid(fog_node):
		fog_node.add_fog_clearer(area_2d_fog_clear)

## 植物离场时移除清雾登记；手套移动时原清雾区域随本株移动。
func _exit_tree() -> void:
	if owner is Plant000Base and (owner as Plant000Base).is_being_relocated:
		return
	if is_instance_valid(fog_node):
		fog_node.del_fog_clearer(area_2d_fog_clear)

