## 共用关卡预览的显示生命周期；滚动和排版分别交给原生容器与展示层。
## 只消费展示字典，不读取进度或解释战斗规则。
extends Panel

## 面板真正关闭时释放地图保留的预览身份；移入面板阅读不会触发。
signal dismissed

## 沿用地图的底框样式。
const UI = preload("res://scripts/adventure/island_ui.gd")
## 固定标题与原生滚动视口。
const View = preload("res://scripts/adventure/ui/stage_preview_view.gd")
## 共用文字和图标绘制。
const Art = preload("res://scripts/adventure/ui/stage_preview_art.gd")
## 所有地图使用同一设计坐标。
const DESIGN_SIZE := Vector2(1920, 1080)
## 完整情报尺寸，内部内容可手动滚动。
const PANEL_SIZE := Vector2(640, 740)
## 尚未解锁情报时保持原问号小框。
const SEALED_SIZE := Vector2(64, 64)
## 地区短介绍的固定尺寸。
const REGION_SIZE := Vector2(640, 300)
## 面板与关卡节点的设计像素间距。
const GAP := 24.0
## 顶部返回区与底部提示区之间的安全边界。
const SAFE_TOP := 110.0
## 面板下沿不得盖住底部提示条。
const SAFE_BOTTOM := 972.0
## 快速经过节点时不弹出预览，单位秒。
const SHOW_DELAY := 0.15
## 允许指针跨过节点与面板之间的空隙，单位秒。
const HIDE_DELAY := 0.35

## 只负责内容显示的子控件。
var _view: Control
## 未解锁时显示的唯一文字。
var _sealed_label: Label
## 延迟显示计时器，离开尚未显示的节点时取消。
var _delay: Timer
## 最后一次请求的展示字典。
var _pending_data: Dictionary = {}
## 当前已显示的数据，用于同一关卡往返悬停时保留阅读位置。
var _active_data: Dictionary = {}
## 待展示关卡在父画布内的矩形。
var _pending_anchor := Rect2()
## 当前已显示关卡的矩形，用于保留往返阅读。
var _anchor := Rect2()
## 节点移出后等待指针离开整个阅读区域。
var _leaving := false
## 本次移出后的剩余宽限时间，单位秒。
var _leave_remaining := 0.0
## 当前面板的淡入动画，切换或关闭时终止。
var _tween: Tween

## 建立唯一展示层和计时器；隐藏期间不运行逐帧检查。
func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_force_pass_scroll_events = false
	add_theme_stylebox_override("panel", UI.panel_style(Color("12211cee")))
	_view = View.new()
	add_child(_view)
	_sealed_label = Art.text(self, "？", Rect2(Vector2.ZERO, SEALED_SIZE), 40,
		Color("ffe8b0"), HORIZONTAL_ALIGNMENT_CENTER)
	_delay = Timer.new()
	_delay.one_shot = true
	_delay.wait_time = SHOW_DELAY
	_delay.timeout.connect(_apply_pending)
	add_child(_delay)
	set_process(false)

## 延迟显示 [param data]，以父画布坐标 [param anchor] 定位；新关卡重新从顶部阅读。
func request(data: Dictionary, anchor: Rect2) -> void:
	if visible and data == _active_data and anchor == _anchor:
		_pending_data = {}
		_delay.stop()
		_leaving = false
		return
	_pending_data = data
	_pending_anchor = anchor
	_leaving = false
	_delay.start()

## 节点移出仅启动关闭宽限；面板和原节点内继续阅读，触屏由地图显式关闭。
func release_hover() -> void:
	if OS.has_feature("android"):
		return
	if not visible or _sealed_label.visible:
		cancel()
		return
	_pending_data = {}
	_delay.stop()
	_leaving = true
	_leave_remaining = HIDE_DELAY

## 模态、移图、返回和触摸取消立即关闭，不等待悬停宽限。
func cancel() -> void:
	var was_active: bool = visible or not _pending_data.is_empty() # 只对有效请求发送一次关闭通知。
	_pending_data = {}
	_active_data = {}
	_delay.stop()
	visible = false
	set_process(false)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if was_active:
		dismissed.emit()

## 返回指针是否位于面板内；地图据此保留当前情报，避免旧键盘焦点切换内容。
func is_pointer_over() -> bool:
	return visible and Rect2(Vector2.ZERO, size).has_point(get_local_mouse_position())

## 仅管理桌面悬停退出；[param delta] 为秒，不修改任何滚动位置。
func _process(delta: float) -> void:
	if not get_window().has_focus():
		cancel()
		return
	if not _leaving:
		return
	var pointer: Vector2 = position + get_local_mouse_position() # 与关卡锚点处于同一父画布坐标。
	if is_pointer_over() or _anchor.has_point(pointer) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_leave_remaining = HIDE_DELAY # 拖动滚动条时允许指针短暂离开面板。
		return
	_leave_remaining -= delta
	if _leave_remaining <= 0.0:
		cancel()

## 提交最后一次展示请求，问号、地区介绍和正式情报共用定位与淡入。
func _apply_pending() -> void:
	if _pending_data.is_empty():
		return
	var data: Dictionary = _pending_data # 本次展示快照。
	_pending_data = {}
	_active_data = data
	_anchor = _pending_anchor
	var sealed: bool = data.get("state") == "sealed" # 维持首通前的情报封锁。
	var region: bool = data.get("state") == "region" # 未开放地区只显示介绍。
	size = SEALED_SIZE if sealed else (REGION_SIZE if region else PANEL_SIZE)
	_view.visible = not sealed
	_sealed_label.visible = sealed
	mouse_filter = Control.MOUSE_FILTER_IGNORE if sealed else Control.MOUSE_FILTER_STOP
	if not sealed:
		_view.show_data(data, size)
	_place(_anchor)
	visible = true
	set_process(not OS.has_feature("android")) # 触摸选择与关闭仍由地图独占，避免选择状态失配。
	modulate.a = 0.0
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, 0.12)

## 优先位于 [param anchor] 右侧；空间不足时翻到左侧，并限制在地图安全区。
func _place(anchor: Rect2) -> void:
	var x: float = anchor.end.x + GAP # 面板左缘在设计画布上的横坐标。
	if x + size.x > DESIGN_SIZE.x - 32.0:
		x = anchor.position.x - GAP - size.x
	x = clampf(x, 32.0, DESIGN_SIZE.x - 32.0 - size.x)
	var y: float = anchor.get_center().y - size.y * 0.5 # 纵向以节点中心对齐。
	position = Vector2(x, clampf(y, SAFE_TOP, SAFE_BOTTOM - size.y))
