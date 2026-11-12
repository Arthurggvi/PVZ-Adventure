## 旧菜单地址兼容跳转；运行主菜单只有注册表指定的一份。
extends Control
class_name StartMenuRoot

func _ready() -> void:
	_redirect.call_deferred()

func _redirect() -> void:
	if get_tree().current_scene!=self:
		return
	var destination: String=Global.main_scene_registry.MainScenesMap[MainSceneRegistry.MainScenes.StartMenu] # 由唯一注册表定义。
	assert(destination!=scene_file_path,"Menu redirect cycle")
	get_tree().change_scene_to_file(destination)
