extends TextureRect
class_name UIShovel

## 槽内铲子图标，选中状态由手持管理器提交。
@onready var shovel: TextureRect = $Shovel

## 工具位只发出选择意图；按钮本身不修改手持外观。
func _on_button_pressed() -> void:
	EventBus.push_event("main_game_click_shovel")

## 根据 [param selected] 显示手持结果；触屏保留图标供再次点击收回。
func set_selected(selected: bool) -> void:
	var mobile: bool = OS.has_feature("mobile") # 桌面沿用鼠标拿起图标后的空槽表现。
	shovel.visible = mobile or not selected
	shovel.self_modulate = Color(1.0, 0.85, 0.55) if mobile and selected else Color.WHITE
