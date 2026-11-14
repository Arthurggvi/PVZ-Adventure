## 功能窗口的轻量花园反馈；短请求不展开卡片，取消立即生效且淡出不拦截输入。
extends Control

## 取消时通知同一个业务拥有者，不自行管理后台任务。
signal closed
## 与 Bootstrap 和场景切换共用表现，不引用任何功能窗口。
const Presentation = preload("res://scripts/ui/transitions/loading_presentation.gd")
## 延迟展开时间，单位真实秒；完成更快的请求不会被人为延长。
const CONTENT_DELAY := 0.18
## 当前功能名称；可以在入树前配置。
var _heading := "正在打开"
## 轻量遮罩缓慢淡入，避免立即压暗整个场景。
var _shade: ColorRect
## 共用的纸色花园卡片，仅在超过短请求阈值后展开。
var _presentation: Control
## 请求起点只用于表现，不判断业务超时。
var _started_usec := 0
## 业务已取消时不再接受输入。
var _closed := false
## 正式内容已就绪或反馈正在退出时，不再推进加载表现。
var _finishing := false
## 错误反馈立即展开，不继续等短请求阈值。
var _failed := false

## [param title] 为当前功能的简短标题，不展示内部路径或阶段百分比。
func set_context(title: String) -> void:
	_heading = title
	if is_instance_valid(_presentation):
		_presentation.configure(_heading, "一切正在就位", true)

## 建立低幅遮罩和可取消反馈，底层场景始终留在原位。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_started_usec = Time.get_ticks_usec()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_shade = ColorRect.new()
	_shade.color = Color(0.025, 0.06, 0.04, 0.0)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shade)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_presentation = Presentation.new()
	_presentation.configure(_heading, "一切正在就位", true)
	_presentation.set_content_visible(false, true)
	add_child(_presentation)
	_presentation.set_action("取消 · Esc", request_close)
	_presentation.focus_action()

## [param _delta] 不参与计时；仅推进视觉，不添加最短停留或改变资源批次的完成时间。
func _process(_delta: float) -> void:
	if _finishing:
		return
	var elapsed: float = float(Time.get_ticks_usec() - _started_usec) / 1_000_000.0 # 不受倍速影响。
	_shade.color.a = 0.30 * smoothstep(0.0, 0.28, elapsed)
	if elapsed >= CONTENT_DELAY or _failed:
		_presentation.set_content_visible(true)

## [param amount] 为当前请求映射后的准备比例；表现层保证不倒退。
func set_progress(amount: float) -> void:
	_presentation.set_progress(amount)

## [param text] 更新构造阶段说明，不重置已显示的草皮或动效。
func set_detail(text: String) -> void:
	_presentation.set_detail(text)

## [param message] 为失败原因，关闭后恢复原入口。
func show_error(message: String) -> void:
	_failed = true
	_presentation.show_error(message)
	_presentation.set_action("返回 · Esc", request_close)

## 正式窗口已发布或请求已取消，立即放开输入并以短淡出退出，不再发出取消信号。
func dismiss() -> void:
	if _finishing:
		return
	_finishing = true
	_closed = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_input(false)
	_presentation.finish()
	var fade: Tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_ignore_time_scale(true) # 视觉退出不阻挡新内容交互。
	fade.tween_property(self, "modulate:a", 0.0, 0.14).set_trans(Tween.TRANS_SINE)
	fade.tween_callback(queue_free)

## 取消资格同步撤销，后台回收仍归原拥有者，淡出只是表现。
func request_close() -> void:
	if _closed:
		return
	_closed = true
	closed.emit()
	dismiss()

## [param event] 的取消键关闭反馈并阻止同一次按键穿透。
func _input(event: InputEvent) -> void:
	if not _closed and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		request_close()
