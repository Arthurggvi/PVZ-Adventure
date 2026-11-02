## 地图首次引导：复用戴夫立绘、动画和音效，逐句推进并幂等发卡。
extends Control

## 对话结束后由地图更新卡片提示。
signal completed
## UI 构造工具。
const UI = preload("res://scripts/adventure/island_ui.gd")
## 精确定稿台词，来自独立 JSON。
var lines: Array = []
## 当前句子，从零开始。
var line_index := 0
## 文本点击区域。
var dialogue: Label
## 继续按钮；第三句停顿期间禁用。
var next_button: Button
## 第四句赠卡提示或存档错误。
var gift_label: Label
## 复用场景中的动画播放器。
var player: AnimationPlayer
## 第三句停顿时屏蔽连续点击。
var waiting := false

## 创建遮罩、戴夫与对话框，覆盖整张地图避免误点。
func _ready() -> void:
	size = Vector2(1920, 1080)
	mouse_filter = Control.MOUSE_FILTER_STOP
	lines = JSON.parse_string(FileAccess.get_file_as_string("res://resources/adventure/dave_intro.json"))
	# 半透明遮罩保持背景仍可见。
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.06, 0.04, 0.35)
	shade.size = size
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	# 戴夫仍使用现有骨骼贴图和动画；禁用原对话控制以免两套点击逻辑并行。
	var dave := SceneRegistry.CRAZY_DAVE.instantiate() as CrazyDave
	add_child(dave)
	dave.get_node("AnimationTree").active = false
	dave.get_node("DaveDialogMousePressPanel").hide()
	dave.get_node("SpeechBubble").hide()
	dave.position = Vector2(120, 310)
	dave.scale = Vector2(1.25, 1.25)
	player = dave.get_node("AnimationPlayer")
	# 对话面板位于设计画布底部右侧，长句自动换行。
	var panel := Panel.new()
	panel.position = Vector2(550, 704)
	panel.size = Vector2(1280, 306)
	panel.add_theme_stylebox_override("panel", UI.panel_style(Color("23392fee")))
	panel.gui_input.connect(_on_dialogue_input)
	add_child(panel)
	UI.label(panel, "疯狂戴夫", Rect2(26, 8, 220, 48), 32)
	dialogue = UI.label(panel, "", Rect2(44, 62, 1192, 115), 40)
	dialogue.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	gift_label = UI.label(panel, "", Rect2(30, 190, 700, 75), 28)
	next_button = UI.button(panel, "继续", Rect2(990, 214, 230, 64), _advance)
	UI.button(self, "跳过对话", Rect2(1560, 40, 270, 66), _finish)
	_show_line()

## 鼠标左键点击文本区域可推进；[param event] 为面板输入。
func _on_dialogue_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_advance()

## 显示下一句；最后一句的继续按钮完成引导。
func _advance() -> void:
	if waiting:
		return
	if line_index == lines.size() - 1:
		_finish()
		return
	line_index += 1
	_show_line()

## 按句子切换原有动画；第四句立即发卡并落盘。
func _show_line() -> void:
	dialogue.text = lines[line_index]
	next_button.text = "开始冒险" if line_index == lines.size() - 1 else "继续  %d / 7" % (line_index + 1)
	player.play("CrazyDave_idle" if line_index == 2 else "CrazyDave_blahblah")
	SoundManager.play_crazy_dave_SFX("crazydaveshort" if line_index == 2 else "crazydavelong")
	if line_index == 3:
		if AdventureSession.progress.grant_starter_cards():
			gift_label.text = "获得：向日葵 ×1    豌豆射手 ×1"
		else:
			gift_label.text = AdventureSession.progress.error_message
	if line_index == 2:
		waiting = true
		next_button.disabled = true
		await get_tree().create_timer(0.85).timeout
		waiting = false
		next_button.disabled = false

## 跳过也赠卡；保存失败时保持对话，允许重试。
func _finish() -> void:
	if not AdventureSession.progress.complete_intro():
		gift_label.text = AdventureSession.progress.error_message
		return
	completed.emit()
	queue_free()
