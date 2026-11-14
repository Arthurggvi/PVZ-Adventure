## 轻量首屏；不直接引用海滨场景素材或战斗资源。
## 正式启动仅经 SceneTransition 请求菜单加载。
extends Control

## 正式城镇菜单的唯一注册入口。
const MAIN_MENU := "res://scenes/main/01StartMenuCoastal.tscn"
## 启动首屏与正式场景共用小型表现，不静态引用城镇或角色场景。
const LoadingPresentation = preload("res://scripts/ui/transitions/loading_presentation.gd")
## 失败时继续保留的首屏表现；请求被接受后由过渡层接管其视觉快照。
var _presentation: Control
## 当前是否有可供玩家重试的失败，不允许在普通启动期重复请求。
var _failed := false
## 唯一加载管线，保持原有成功交接与失败输入恢复契约。
@onready var _transition: CanvasLayer = $SceneTransition

## 启动时异步进入菜单，失败保持本页面并显示错误。
func _ready() -> void:
	_transition.transition_failed.connect(_show_failure)
	_transition.revealed.connect(_on_revealed)
	_request_menu()

## 真实按钮与确认键复用同一重试入口；已覆盖的首屏可直接交给统一加载层。
func _request_menu() -> void:
	if _transition.busy:
		return
	_failed = false
	if is_instance_valid(_presentation):
		remove_child(_presentation)
		_presentation.queue_free()
	_presentation = LoadingPresentation.new()
	_presentation.name = "LoadingPresentation"
	add_child(_presentation)
	_presentation.disable_action()
	_presentation.configure("准备进入城镇", "让阳光先铺满小路")
	_presentation.set_content_visible(true, true)
	if not _transition.change_scene(MAIN_MENU):
		_show_failure()
		return
	_transition.adopt_presentation(_presentation.snapshot())
	_presentation.hide()

## 已接受请求后的失败也显示可操作反馈；统一过渡负责恢复输入。
func _show_failure() -> void:
	_failed = true
	_presentation.show_error("城镇暂时没有打开，请再试一次。")
	_presentation.set_action("重试", _request_menu)
	if not _transition.busy:
		_on_revealed()

## 统一过渡完全释放输入后再显示错误并聚焦，避免两层文字或按钮焦点互相覆盖。
func _on_revealed() -> void:
	if not _failed:
		return
	_presentation.show()
	_presentation.focus_action()

## [param event] 在加载失败且过渡空闲时允许重新请求菜单。
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") and _failed and not _transition.busy:
		_request_menu()
		get_viewport().set_input_as_handled()
