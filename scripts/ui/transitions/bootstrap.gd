## 轻量首屏；不直接引用海滨场景素材或战斗资源。
## 正式启动仅经 SceneTransition 请求菜单加载。
extends Control

## 正式城镇菜单的唯一注册入口。
const MAIN_MENU := "res://scenes/main/01StartMenuCoastal.tscn"

## 启动时异步进入菜单，失败保持本页面并显示错误。
func _ready() -> void:
	$SceneTransition.transition_failed.connect(_show_failure)
	if not $SceneTransition.change_scene(MAIN_MENU):
		_show_failure()

## 已接受请求后的失败也显示可操作反馈；统一过渡负责恢复输入。
func _show_failure() -> void:
	$Status.text = "无法打开主菜单，按确认键重试"

## [param event] 在加载失败且过渡空闲时允许重新请求菜单。
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") and not $SceneTransition.busy:
		$Status.text = "准备进入城镇"
		if not $SceneTransition.change_scene(MAIN_MENU):
			_show_failure()
		get_viewport().set_input_as_handled()
