## 轻量首屏；不直接引用海滨场景素材或战斗资源。
## 正式启动仅经 SceneTransition 请求菜单加载。
extends Control

## 正式城镇菜单的唯一注册入口。
const MAIN_MENU := "res://scenes/main/01StartMenuCoastal.tscn"

## 启动时异步进入菜单，失败保持本页面并显示错误。
func _ready() -> void:
	if not $SceneTransition.change_scene(MAIN_MENU):
		$Status.text = "无法打开主菜单"
		push_error("Bootstrap: main menu request was rejected")
