## 原冒险入口的独立新游戏/继续选择；新游戏备份旧进度，不删除原版用户。
extends ConfirmationDialog

## 当前进度的继续入口。
var continue_button: Button
## 已有冒险时的二次确认，只作用于游戏内的新游戏操作。
var restart_prompt: ConfirmationDialog

## 保持原菜单全部功能，另加明确的新游戏与继续语义。
func _ready() -> void:
	title = "冒险"
	ok_button_text = "开始新游戏"
	cancel_button_text = "返回"
	continue_button = add_button("继续游戏", true, "continue")
	custom_action.connect(_on_action)
	confirmed.connect(_new_game)
	restart_prompt = ConfirmationDialog.new()
	restart_prompt.title = "开始新冒险"
	restart_prompt.dialog_text = "将从草坪重新开始。当前冒险会先保留为备份，原版存档不会删除。"
	restart_prompt.ok_button_text = "备份并开始"
	restart_prompt.cancel_button_text = "返回"
	restart_prompt.confirmed.connect(_start_new)
	add_child(restart_prompt)
	about_to_popup.connect(_refresh)

## 每次弹出时读取当前用户进度，防止切换用户后串档。
func _refresh() -> void:
	var valid := AdventureSession.refresh_profile() # 当前文件是否可读取。
	continue_button.disabled = not valid or not AdventureSession.progress.started
	dialog_text = "新游戏：开始僵尸岛冒险。\n继续游戏：返回世界地图，保留卡片与通关进度。"
	if not valid:
		dialog_text = AdventureSession.progress.error_message

## [param action] 为自定义按钮操作名。
func _on_action(action: StringName) -> void:
	if action == "continue":
		AdventureSession.continue_game()
		_show_error()

## 已存在文件时先显示游戏内重开提示。
func _new_game() -> void:
	if FileAccess.file_exists(AdventureSession.progress.save_path):
		restart_prompt.popup_centered(Vector2i(620, 160))
	else:
		_start_new()

## 新游戏成功时切场景，失败时明确显示保存错误。
func _start_new() -> void:
	AdventureSession.start_new_game()
	_show_error()

## IO 失败时保持菜单可用，且让用户看到错误原因。
func _show_error() -> void:
	if not AdventureSession.progress.error_message.is_empty():
		dialog_text = AdventureSession.progress.error_message
		popup_centered(Vector2i(620, 180))
