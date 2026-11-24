## 设置页存在诊断记录时显示的单个复制动作；完全复用既有设置按钮样式。
extends Button

## 加载断点的唯一来源，不能读取或修改存档文件。
const Checkpoint = preload("res://scripts/ui/transitions/resource_load_checkpoint.gd")

## 正常玩家无记录时，设置页不创建这颗按钮。
static func available() -> bool:
	return Checkpoint.has_report()

## 放在原设置底栏左侧，不增加新的技术页签或独立面板。
func _ready() -> void:
	name = "CopyLoadingReport"
	text = "复制加载记录"
	tooltip_text = "复制最近一次加载异常或超过三秒的资源记录"
	accessibility_name = "复制加载诊断记录"
	size = Vector2(145, 32)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_theme_font_size_override("font_size", 13)
	pressed.connect(_copy)

## 一次点击得到纯文本，状态在原位置更新，不弹调试窗口。
func _copy() -> void:
	DisplayServer.clipboard_set(Checkpoint.report_text())
	Checkpoint.acknowledge()
	text = "已复制"
	disabled = true
