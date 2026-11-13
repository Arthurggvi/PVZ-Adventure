## 在仅导出已暂存地图素材的干净工程中运行，检查提交内容可独立导入。
extends Node

## 按布局逐项加载实际运行所需的地图、按钮和图标。
func _ready() -> void:
	# 素材路径相对于干净工程根目录，不访问原工程忽略的文件。
	var base := "res://assets/adventure/zombie_island/"
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(base + "layout.json"))
	assert(load(base + layout.map.file) is Texture2D)
	assert(load(base + layout.button.frame) is Texture2D)
	for stage: Dictionary in layout.stages: # 六个配置节点分别引用独立图片。
		assert(load(base + stage.button) is Texture2D)
		assert(load(base + stage.icon) is Texture2D)
	print("PASS: staged map assets imported and loaded in clean standalone project")
	get_tree().quit(0)
