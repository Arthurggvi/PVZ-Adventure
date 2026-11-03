## 首次冒险引导只处理资源、停顿和幂等赠卡；对话表现完全交给原版戴夫封装。
extends Control

## 引导已完成并持久化，由地图决定后续显示。
signal completed
## 原版对话的可复用封装，不包含冒险存档逻辑。
const Conversation = preload("res://scripts/ui/native_dave_conversation.gd")
## 七句定稿原文使用原生CrazyDaveDialogResource格式。
const INTRO = preload("res://resources/adventure/dave_intro.tres")
## 辅助状态文字与官方跳过按钮。
const UI = preload("res://scripts/adventure/island_ui.gd")
## 本次原生对话组件。
var conversation: Control
## 赠卡结果或写入错误；不替代原版对话气泡。
var gift_label: Label

## 只构建背景遮罩和辅助控件，不再创建另一套对话框或继续按钮。
func _ready() -> void:
	size = Vector2(1920, 1080)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new() # 阻断地图误触，同时保留背景可见。
	shade.color = Color(0.02, 0.06, 0.04, 0.35)
	shade.size = size
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	conversation = Conversation.new()
	conversation.configure(INTRO, _complete_progress, {2: 0.85})
	conversation.scale = size / Conversation.NATIVE_SIZE
	conversation.line_started.connect(_on_line_started)
	conversation.finished.connect(_on_finished)
	add_child(conversation)
	gift_label = UI.label(self, "", Rect2(570, 940, 1080, 80), 28)
	UI.official_button(self, "跳过对话", Rect2(1560, 40, 270, 66), _finish)

## [param index] 为原版资源中的句索引，第四句沿用原有幂等发卡接口。
func _on_line_started(index: int) -> void:
	if index == 3:
		if AdventureSession.progress.grant_starter_cards():
			gift_label.text = "获得：向日葵 ×1    豌豆射手 ×1"
		else:
			gift_label.text = AdventureSession.progress.error_message

## 原版最后一句和跳过共享持久化校验；返回false时保持气泡，点击可重试。
func _complete_progress() -> bool:
	if not AdventureSession.progress.complete_intro():
		gift_label.text = AdventureSession.progress.error_message
		return false
	return true

## 官方跳过按钮只请求封装层结束，不绕过赠卡或保存校验。
func _finish() -> void:
	conversation.skip()

## 自然对话结束等待原版离场，跳过则立即释放；本节点不保留异步计时回调。
func _on_finished() -> void:
	completed.emit()
	queue_free()
