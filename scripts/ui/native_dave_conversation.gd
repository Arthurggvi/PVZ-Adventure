## 原版顺序戴夫对话的可复用封装；不重写动画状态机、气泡、语音或逐句循环。
extends Control

## 当前句子已显示；[param index] 为零基索引，供业务层处理赠卡等事件。
signal line_started(index: int)
## 原版离场结束或主动跳过成功后发出，组件随即释放。
signal finished
## 原版逻辑坐标；外层画布可整体缩放，不改变原气泡布局。
const NATIVE_SIZE := Vector2(1066, 600)
## 可选临时屏蔽原BGM播放器，保留音量、静音及曲目；默认不影响其他原版对话。
var suppress_bgm := false
## 本次暂时接管的原播放器，不创建并行音乐系统。
var bgm_player: AudioStreamPlayer
## 进入前的暂停状态，任何退出路径都须原样恢复。
var bgm_was_paused := false
## 原版对话资源，配置后交给CrazyDave.init_dave执行。
var dialogue_resource: CrazyDaveDialogResource
## 业务完成前的可选校验；失败时保留当前原版气泡，允许点击重试。
var completion_guard: Callable
## 各句最短显示秒数，只限制输入，不控制原版动画。
var line_holds: Dictionary
## 原场景实例，AnimationTree始终交给原版脚本管理。
var actor: CrazyDave
## 当前原版句子，-1代表仍在进场。
var line_index := -1
## 已获准完成，阻止重复点击及重复持久化。
var closing := false
## 结束信号只发一次。
var ended := false
## 随组件销毁的单次停顿计时器，不使用跨场景await回调。
var hold_timer: Timer
## 最后由此对话启动的戴夫语音，关闭时只停止同一音轨。
var owned_voice: AudioStream
## 等待原版应激状态真正发出结束回调，避免上一句残留的idle状态提前放行。
var reaction_pending := false

## 入树前配置。[param resource] 为原版资源；[param guard] 决定能否结束；[param holds] 为句索引到秒数。
func configure(resource: CrazyDaveDialogResource, guard: Callable = Callable(), holds: Dictionary = {}) -> void:
	dialogue_resource = resource
	completion_guard = guard
	line_holds = holds.duplicate()

## 原版进场动画完成后自动调用start_dialog；封装层不手动播放或推进动画。
func _ready() -> void:
	assert(dialogue_resource != null and not dialogue_resource.dialog_detail_list.is_empty())
	assert(not dialogue_resource.is_long_time_dave, "此封装用于一次性顺序对话，商店继续使用原生常驻接口")
	for detail: CrazyDaveDialogDetailResource in dialogue_resource.dialog_detail_list: # 选项分支仍由原版场景及业务直接管理。
		assert(not detail.is_choosed, "此封装不接管原生选项对话")
	size = NATIVE_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	if suppress_bgm:
		bgm_player = SoundManager.bgm_play
		bgm_was_paused = bgm_player.stream_paused
		bgm_player.stream_paused = true
	hold_timer = Timer.new()
	hold_timer.one_shot = true
	add_child(hold_timer)
	actor = SceneRegistry.CRAZY_DAVE.instantiate() as CrazyDave
	actor.init_dave(dialogue_resource)
	actor.dialog_line_started.connect(_on_line_started)
	actor.signal_dave_leave_end.connect(_emit_finished)
	actor.talk_end_signal.connect(_on_talk_ended)
	add_child(actor)
	actor.animation_tree.active = true
	actor.dave_dialog_mouse_press_panel.advance_guard = _can_advance
	_ignore_bubble_input(actor.get_node("SpeechBubble"))

## [param node] 的气泡控件不另行截断输入，点击气泡也由原版点击面板统一接收。
func _ignore_bubble_input(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in node.get_children(): # 不处理原版选择框或其他场景节点。
		_ignore_bubble_input(child)

## [param index] 由原版顺序循环通知；只管理输入停顿与业务事件。
func _on_line_started(index: int) -> void:
	line_index = index
	reaction_pending = dialogue_resource.dialog_detail_list[index].is_crazy
	owned_voice = SoundManager.crazy_dave_player.stream
	hold_timer.stop()
	if float(line_holds.get(index, 0.0)) > 0.0:
		hold_timer.start(float(line_holds[index]))
	line_started.emit(index)

## 只接受原版CrazyDave_crazy状态的结束事件，不用定时器模拟帽子动画时长。
func _on_talk_ended() -> void:
	if not reaction_pending:
		return
	var playback := actor.animation_tree.get("parameters/StateMachine/TalkNoHand/playback") as AnimationNodeStateMachinePlayback # 原版无手持对话子状态机。
	if playback.get_current_node() == &"CrazyDave_crazy":
		reaction_pending = false

## 拒绝进场期、停顿期和重复输入；最后一句先提交业务，再让原版执行离场。
func _can_advance() -> bool:
	if closing or line_index < 0 or not hold_timer.is_stopped():
		return false
	# 原版crazy动画包含帽子飞起及表情动作，等待原版_talk_end回调，不用固定时长替代。
	if reaction_pending:
		return false
	if line_index == dialogue_resource.dialog_detail_list.size() - 1:
		if completion_guard.is_valid() and not completion_guard.call():
			return false
		closing = true
	return true

## 对外推进入口仍走原生面板，不能绕过停顿与结束校验。
func request_advance() -> void:
	actor.dave_dialog_mouse_press_panel.request_advance()

## 跳过可在进场及停顿中使用；校验失败时原气泡和输入状态不变。
func skip() -> void:
	if closing or (completion_guard.is_valid() and not completion_guard.call()):
		return
	closing = true
	_emit_finished()

## 自然结束等原版离场信号；跳过释放全部子节点和等待中的原版点击循环。
func _emit_finished() -> void:
	if ended:
		return
	ended = true
	hold_timer.stop()
	finished.emit()
	queue_free()

## 场景关闭即停止本地计时器和所属语音，并恢复原播放器的暂停状态；不修改音量或总线静音。
func _exit_tree() -> void:
	if is_instance_valid(hold_timer):
		hold_timer.stop()
	if owned_voice != null and SoundManager.crazy_dave_player.stream == owned_voice:
		SoundManager.crazy_dave_player.stop()
	if is_instance_valid(bgm_player):
		bgm_player.stream_paused = bgm_was_paused
