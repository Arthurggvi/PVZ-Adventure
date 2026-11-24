## 桌面设置栏中的独立导出按钮：使用系统保存窗口写出当前玩家的真实存档。
extends Button
class_name DesktopSaveExportButton

## 写文件的唯一入口，隔离桌面平台操作与设置窗口布局。
const Writer = preload("res://scripts/adventure/player/desktop_save_export_writer.gd")

## 初始化为设置栏顶部的小操作按钮，复用现成的木纹按钮主题。
func _ready() -> void:
	text = "导出存档"
	theme_type_variation = &"Keycap"
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	accessibility_name = "导出当前玩家存档文件"
	tooltip_text = "将当前冒险版存档保存到电脑"
	pressed.connect(_open_save_dialog)

## 保存当前玩家进度并冻结单次导出的原始字节，然后交由文件选择器决定位置。
func _open_save_dialog() -> void:
	if Global.save_service == null:
		_show_result("无当前存档")
		return
	var source: String = Global.save_service.prepare_current_export_path() # 确保先提交最新进度。
	if source.is_empty():
		_show_result("先进入存档")
		return
	var original_file: FileAccess = FileAccess.open(source, FileAccess.READ) # 只读源文件，不覆盖。
	if original_file == null:
		_show_result("读取失败")
		return
	var snapshot: PackedByteArray = original_file.get_buffer(original_file.get_length()) # 冻结本次保存内容。
	var read_ok: bool = original_file.get_error() == OK # 检查文件是否完整读取。
	original_file.close()
	if not read_ok or snapshot.is_empty():
		_show_result("读取失败")
		return
	var picker := FileDialog.new() # 使用系统提供的文件保存对话框。
	picker.title = "保存冒险版存档"
	picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	picker.filters = PackedStringArray(["*.json ; JSON 存档"])
	picker.use_native_dialog = true
	var stamp: String = Time.get_datetime_string_from_system().replace("-", "").replace(":", "").replace("T", "_") # 文件名仅使用本机时间。
	picker.current_file = "PVZAdventure_" + stamp + ".json"
	picker.file_selected.connect(_write_selected.bind(picker, source, snapshot))
	picker.canceled.connect(picker.queue_free)
	add_child(picker)
	picker.popup_centered(Vector2i(740, 480))

## 用户确认目标后，先校验不能覆盖游戏原档，再写入并反馈。
func _write_selected(destination: String, picker: FileDialog, source: String, snapshot: PackedByteArray) -> void:
	picker.queue_free()
	if destination.simplify_path().to_lower() == source.simplify_path().to_lower():
		_show_result("不可覆盖原档")
		return
	_show_result("导出中…")
	var success: bool = Writer.write_snapshot(destination, snapshot) # 完整写入并校验后才算成功。
	_show_result("导出成功" if success else "导出失败")

## 保留按钮功能，反馈只占原按钮的一行，不增加技术对话框。
func _show_result(message: String) -> void:
	text = message
