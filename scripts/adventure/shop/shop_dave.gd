## 常驻商店戴夫：复用原版 AnimationTree、说话长度和发疯动作，不接管交易。
extends Control

## 原生进场完成后可接受商品描述。
signal available
## 发疯动画真正结束，窗口可恢复下一笔交易。
signal celebration_finished
## 共用商店字体与纸张。
const Style = preload("res://scripts/adventure/shop/shop_skin.gd")
## 原版角色实例，所有动画均由其原生状态机驱动。
var actor: CrazyDave
## 原版开场白推进完毕后才能调用外部对话接口。
var _ready_to_talk := false
## 进场期间收到的最新商品介绍，不排队播放过时选择。
var _pending_text := "来点好东西？"
## 发疯期间不允许普通介绍覆盖动作。
var _celebrating := false
## 当前组件启动的语音资源，退出时仅清理自身声音。
var _voice: AudioStream
## 每次换句只淡入气泡，不用逐字动画拖延阅读。
var _bubble_motion: Tween

## 原版进场自动启动开场白；商店不要求额外点击一次欢迎语。
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dialogue := CrazyDaveDialogResource.new() # 空闲台词保留原生协议，但不自动打断当前商品介绍。
	dialogue.is_long_time_dave = true
	dialogue.is_enter_up = true
	dialogue.dialog_detail_list.append(_detail(_pending_text))
	dialogue.dialog_detail_long_time_idle_list.append(_detail("平底锅不卖！"))
	actor = SceneRegistry.CRAZY_DAVE.instantiate() as CrazyDave
	actor.init_dave(dialogue)
	actor.position = Vector2(57, 181)
	actor.scale = Vector2.ONE * 0.94
	actor.dialog_line_started.connect(_greeting_started)
	actor.talk_end_signal.connect(_talk_ended)
	add_child(actor)
	# 原生点击遮罩不参与商店命中；商品、确认与返回始终由窗口拥有。
	_ignore_input(actor)
	actor.dave_dialog_mouse_press_panel.advance_guard = func() -> bool: return false
	var bubble_root: Control = actor.get_node("SpeechBubble") # 气泡仍由原版说话逻辑显示和隐藏。
	bubble_root.position = Vector2(-27, 491)
	actor.bubble_2.size = Vector2(318, 106)
	actor.bubble_2.add_theme_stylebox_override("panel", Style.box(Color("f3e9cd"), Color("d6bd83"), 18))
	var margin: MarginContainer = actor.get_node("SpeechBubble/Bubble2/MarginContainer") # 自适应到固定气泡尺寸。
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "top", "right", "bottom"]: # 给气泡文字保留足够内边距。
		margin.add_theme_constant_override("margin_" + side, 18)
	actor.speech_text_label.custom_minimum_size = Vector2.ZERO
	actor.speech_text_label.add_theme_font_override("font", Style.FONT)
	actor.speech_text_label.add_theme_font_size_override("font_size", 24)
	actor.speech_text_label.add_theme_color_override("font_color", Style.INK)
	actor.animation_tree.active = true

## 将 [param node] 下的原生控件设置为穿透，让页面上的真实按钮统一处理输入。
func _ignore_input(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in node.get_children(): # 不改变原生动画或节点层级。
		_ignore_input(child)

## [param _index] 表示原版开场白已启动；延迟推进以等候原生 await 注册。
func _greeting_started(_index: int) -> void:
	_voice = SoundManager.crazy_dave_player.stream
	_finish_greeting.call_deferred()

## 只推进一次原版开场白，保留常驻初始化与原生语音行为。
func _finish_greeting() -> void:
	if _ready_to_talk or not is_inside_tree():
		return
	actor.dave_dialog_mouse_press_panel.signal_dave_dialog_press.emit()
	actor.timer_long_time_idle.stop()
	_ready_to_talk = actor.start_long_time_dave
	if _ready_to_talk:
		say(_pending_text)
		available.emit()

## 用原版外部对话描述 [param text]；进场时只记住最后一句，发疯期间拒绝覆盖。
func say(text: String) -> void:
	_pending_text = text
	if not _ready_to_talk or _celebrating:
		return
	actor.long_time_dave_start_dialog()
	actor.external_trigger_dialog(_detail(text))
	_voice = SoundManager.crazy_dave_player.stream
	if is_instance_valid(_bubble_motion):
		_bubble_motion.kill()
	actor.bubble_2.modulate.a = 0.35
	_bubble_motion = create_tween()
	_bubble_motion.tween_property(actor.bubble_2, "modulate:a", 1.0, 0.16)

## 成交保存后播放原版发疯动作并显示 [param text]，空文本采用默认庆祝台词。
func celebrate(text: String = "") -> void:
	if not _ready_to_talk or _celebrating:
		return
	_celebrating = true
	var line: CrazyDaveDialogDetailResource = _detail(text if not text.is_empty() else "歪比巴卜！！") # 台词与原版动作及音效一起播放。
	line.is_crazy = true
	actor.long_time_dave_start_dialog()
	actor.external_trigger_dialog(line)
	_voice = SoundManager.crazy_dave_player.stream

## 只接受原生发疯状态的结束通知；不会被上一句说话的结束回调提前解锁。
func _talk_ended() -> void:
	if not _celebrating:
		return
	var playback := actor.animation_tree.get("parameters/StateMachine/TalkNoHand/playback") as AnimationNodeStateMachinePlayback # 原版无手持对话子状态机。
	if playback != null and playback.get_current_node() == &"CrazyDave_crazy":
		_finish_celebration.call_deferred()

## 动画回调完成后解除商店锁，避免在 AnimationTree 更新中重入说话。
func _finish_celebration() -> void:
	if not _celebrating:
		return
	_celebrating = false
	celebration_finished.emit()

## 根据 [param text] 生成只属于本次交互的原版台词资源。
func _detail(text: String) -> CrazyDaveDialogDetailResource:
	var line := CrazyDaveDialogDetailResource.new() # 不修改共享对话资源。
	line.text = text
	return line

## 关闭或切换档案时停止此页面启动的语音，不影响后续对话的声音。
func _exit_tree() -> void:
	if _voice != null and SoundManager.crazy_dave_player.stream == _voice:
		SoundManager.crazy_dave_player.stop()
