## 每个场景可复用的轻量遮幕；封装切换时序和输入锁，不持有游戏或存档状态。
extends CanvasLayer

## 当前场景完全揭开，输入已恢复。
signal revealed
## 切换失败或成功标记与实际场景不符；宿主负责恢复自己的导航等待状态。
signal transition_failed
## 覆盖画面所需的真实秒数。
@export_range(0.05, 1.0, 0.01) var cover_seconds := 0.16
## 新场景揭开所需的真实秒数。
@export_range(0.05, 1.0, 0.01) var reveal_seconds := 0.36
## 场景首次入树自动从不透明遮幕揭开，避免暴露未准备的首帧。
@export var reveal_on_ready := true
## 过渡期间拒绝重复请求与底层输入；不使用全局暂停。
var busy := false
## 当前唯一 Tween，绑定本组件生命周期。
var _tween: Tween
## 本次请求的原场景，用实际离场结果验证旧入口的成功返回，防止永久黑屏。
var _source_scene: Node
## 首次揭幕前保留的已渲染帧数，吸收父场景加载与首帧预热耗时。
var _prepare_frames := 0
## 适应整个视口的纯色遮幕，也是鼠标输入屏障。
@onready var curtain: ColorRect = $Curtain

## 自动揭开新场景；无跨场景全局对象，也不会创建音频播放器。
func _ready() -> void:
	if reveal_on_ready:
		busy = true
		curtain.show()
		curtain.modulate.a = 1.0
		if DisplayServer.get_name() == "headless":
			_reveal.call_deferred() # 无显示后端没有呈现屏障，仍正常释放导航输入锁。
		else:
			_prepare_frames = 2
			RenderingServer.frame_post_draw.connect(_on_prepared_frame)
	else:
		curtain.hide()

## 第一帧完成场景/渲染预热，第二帧吸收其耗时；此后才创建揭幕 Tween。
func _on_prepared_frame() -> void:
	_prepare_frames -= 1
	if _prepare_frames == 0:
		RenderingServer.frame_post_draw.disconnect(_on_prepared_frame)
		_reveal.call_deferred()

## 覆盖后执行 [param action]；返回是否接受请求。[br]
## 动作必须返回场景切换的 Error 或既有安全入口的 bool，失败自动揭开原场景。
func run(action: Callable) -> bool:
	if busy or not action.is_valid():
		return false
	busy = true
	_source_scene = get_tree().current_scene
	curtain.show()
	_tween = _fade_to(1.0, cover_seconds)
	_tween.tween_callback(_invoke.bind(action))
	return true

## [param scene_path] 由宿主明确注册，遮住画面后切换，失败留在原场景恢复输入。
func change_scene(scene_path: String) -> bool:
	return run(get_tree().change_scene_to_file.bind(scene_path))

## [param action] 在画面完全盖住后调用一次；错误不会遗留黑屏或输入锁。
func _invoke(action: Callable) -> void:
	if not action.is_valid():
		transition_failed.emit()
		_reveal()
		return
	var tree := get_tree() # 成功切换会立即把旧场景移出树，必须在动作之前保留 SceneTree 引用。
	var result: Variant = action.call() # 只接收受控宿主返回值，不解释外部配置。
	if ((result is bool and result) or (result is int and result == OK)) \
		and tree.current_scene != _source_scene:
		return # 成功切换由 SceneTree 释放旧组件；目标场景自带揭幕。
	transition_failed.emit()
	_reveal()

## 从当前遮光强度恢复画面；失败回滚和新场景入场共用同一实现。
func _reveal() -> void:
	busy = true
	curtain.show()
	_tween = _fade_to(0.0, reveal_seconds)
	_tween.tween_callback(_finish_reveal)

## [param alpha] 是目标遮光强度，[param seconds] 为真实时长，返回绑定组件的 Tween。
func _fade_to(alpha: float, seconds: float) -> Tween:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_ignore_time_scale(true) # 单一生命周期。
	tween.tween_property(curtain, "modulate:a", alpha, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return tween

## 揭幕完成后才恢复输入，隐藏屏障避免遮挡后续普通交互。
func _finish_reveal() -> void:
	curtain.hide()
	busy = false
	revealed.emit()

## [param _event] 在遮幕期间统一消费，阻止键盘、手柄或鼠标穿透及重复触发。
func _input(_event: InputEvent) -> void:
	if busy:
		get_viewport().set_input_as_handled()

## 切换或外部销毁时清理 Tween，组件不会驻留到下一场景。
func _exit_tree() -> void:
	if RenderingServer.frame_post_draw.is_connected(_on_prepared_frame):
		RenderingServer.frame_post_draw.disconnect(_on_prepared_frame)
	if _tween != null and _tween.is_valid():
		_tween.kill()
