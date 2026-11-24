## 教堂战场的本地预览入口。正式入场与重开仍读取冒险会话已提交的参数。
extends MainGameManager

## 编辑器直接运行时使用内置预览牌组，退出经统一过渡回奇境地图。
func set_game_para() -> void:
	if Global.game_para == null:
		preview_return_scene = "res://scenes/adventure/wonderland_map.tscn"
	super()
