## 可复用弹层开关动效；只操作独立表现容器，不接管布局、导航或玩家状态。
extends Node

## 入场完成后允许宿主恢复焦点和输入。
signal opened
## 退场完成后由宿主释放弹层。
signal closed
## 明确的表现生命周期，快速关闭可以打断入场，重复退场不会叠加 Tween。
enum Phase { HIDDEN, OPENING, OPEN, CLOSING }
## 专用表现容器；布局画布应作为其子节点，保持自身坐标不变。
@export var target: Control
## 独立背景遮罩，可不指定。
@export var backdrop: CanvasItem
## 入场秒数，使用真实时间，不受游戏速度影响。
@export_range(0.05, 1.0, 0.01) var open_seconds := 0.26
## 退场秒数，短于入场，保持关闭操作利落。
@export_range(0.05, 1.0, 0.01) var close_seconds := 0.18
## 隐藏姿态相对于正常姿态的统一倍率，避免大幅弹跳。
@export_range(0.8, 1.0, 0.005) var hidden_scale := 0.96
## 隐藏姿态的轻微偏移，单位为视口逻辑像素。
@export var hidden_offset := Vector2(0, 18)
## 当前表现阶段，供宿主控制输入和技术验收读取。
var phase: Phase = Phase.HIDDEN
## 唯一有效的动效实例，打断或销毁时主动终止。
var _tween: Tween
## 容器初始位置，不能使用布局画布的适配坐标。
var _rest_position := Vector2.ZERO
## 容器初始倍率，入场完成后精确恢复。
var _rest_scale := Vector2.ONE
## 容器原始透明度，避免改变场景定义的外观。
var _rest_alpha := 1.0
## 遮罩原始透明度，保留美术定义的遮光强度。
var _backdrop_alpha := 1.0

## 记录表现容器的正常姿态，窗口变化只更新缩放中心。
func _ready() -> void:
	_rest_position = target.position
	_rest_scale = target.scale
	_rest_alpha = target.modulate.a
	if backdrop != null:
		_backdrop_alpha = backdrop.modulate.a
	target.resized.connect(_update_pivot)
	_update_pivot()

## 从轻微缩小、下移的透明姿态入场；重入先终止旧 Tween。
func play_open() -> void:
	_stop_tween()
	phase = Phase.OPENING
	target.position = _rest_position + hidden_offset
	target.scale = _rest_scale * hidden_scale
	target.modulate.a = 0.0
	if backdrop != null:
		backdrop.modulate.a = 0.0
	_tween = _make_tween(Tween.EASE_OUT)
	_tween.tween_property(target, "position", _rest_position, open_seconds)
	_tween.tween_property(target, "scale", _rest_scale, open_seconds)
	_tween.tween_property(target, "modulate:a", _rest_alpha, open_seconds)
	if backdrop != null:
		_tween.tween_property(backdrop, "modulate:a", _backdrop_alpha, open_seconds)
	_tween.chain().tween_callback(_finish_open)

## 从当前姿态退场，可在入场中途调用；退场中的重复请求直接忽略。
func play_close() -> void:
	if phase == Phase.CLOSING or phase == Phase.HIDDEN:
		return
	_stop_tween()
	phase = Phase.CLOSING
	_tween = _make_tween(Tween.EASE_IN)
	_tween.tween_property(target, "position", _rest_position + hidden_offset * 0.6, close_seconds)
	_tween.tween_property(target, "scale", _rest_scale * hidden_scale, close_seconds)
	_tween.tween_property(target, "modulate:a", 0.0, close_seconds)
	if backdrop != null:
		_tween.tween_property(backdrop, "modulate:a", 0.0, close_seconds)
	_tween.chain().tween_callback(_finish_close)

## 返回是否还在过渡，供宿主屏蔽重复输入。
func is_animating() -> bool:
	return phase == Phase.OPENING or phase == Phase.CLOSING

## [param easing] 为方向；所有 Tween 绑定本组件且不受暂停、游戏时间倍率影响。
func _make_tween(easing: Tween.EaseType) -> Tween:
	return create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS) \
		.set_ignore_time_scale(true).set_trans(Tween.TRANS_CUBIC).set_ease(easing)

## 只更新表现层中心，不写入布局画布的位置或倍率。
func _update_pivot() -> void:
	target.pivot_offset = target.size / 2.0

## 精确结束入场后再通知宿主，防止焦点在移动中接受确认。
func _finish_open() -> void:
	phase = Phase.OPEN
	opened.emit()

## 退场只发出生命周期信号，是否释放由界面宿主决定。
func _finish_close() -> void:
	phase = Phase.HIDDEN
	closed.emit()

## 终止唯一 Tween，避免快速开关时多个动画争用同一属性。
func _stop_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()

## 场景销毁主动取消动效，不保留异步回调或悬浮层。
func _exit_tree() -> void:
	_stop_tween()
