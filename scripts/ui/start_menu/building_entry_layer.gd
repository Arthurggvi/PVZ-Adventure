extends Control
## 场景式入口控制：命中保持固定，牌匾与高亮只呈现同一工具栏门面的实时状态。

## 当前建筑的视觉状态；不会直接开启功能。
signal highlight_changed(entry_id: String, mode: String, pressed: bool)
## 每次请求记录接受与否，供预览和可访问反馈使用。
signal action_requested(entry_id: String, accepted: bool)
## 稳定命中控件的唯一实现。
const Hit = preload("res://scripts/ui/start_menu/building_entry_hit.gd")
## 只负责显示、始终穿透鼠标的小型名称牌。
const Badge = preload("res://scripts/ui/start_menu/building_entry_badge.gd")
## 权威入口元数据，不保存独立解锁条件。
var entries: Dictionary = {}
## 原画坐标下的稳定命中控件。
var controls: Dictionary = {}
## 与各个建筑对应的视觉牌匾。
var _badges: Dictionary = {}
## 查询真实入口权限的宿主门面。
var _status: Callable
## 重新校验并提交动作的宿主门面。
var _open: Callable
## 查询工具栏及场景模态阻塞的宿主门面。
var _blocked: Callable
## 当前最多一个有效悬停或键盘焦点建筑。
var hovered_id := ""
## 上次发出的高亮签名，避免每帧重复通知合成层。
var _last_feedback := ""
## 键盘导航与鼠标悬停不能互相保持陈旧焦点。
var _keyboard_mode := false

## [param data] 定义入口和原画尺寸；[param status]、[param action]、[param blocked] 复用工具栏权限与窗口。
## [param font] 用于独立牌匾，显示控件不改变任何命中范围。
func configure(data: Dictionary, status: Callable, action: Callable, blocked: Callable, font: Font) -> void:
	_status = status
	_open = action
	_blocked = blocked
	size = Vector2(data.canvas[0], data.canvas[1])
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for entry: Dictionary in data.entries: # 每个入口共享一份静态几何与元数据。
		entries[entry.id] = entry
		var hit: Control = Hit.new() # 每个建筑一份稳定命中轮廓。
		hit.configure(entry, size)
		add_child(hit)
		hit.activated.connect(_activate)
		controls[entry.id] = hit
	var ids: Array = controls.keys() # 明确键盘顺序，不由全屏命中框的位置决定焦点。
	for index: int in ids.size(): # 按配置顺序形成完整键盘焦点环。
		controls[ids[index]].focus_next = NodePath("../" + ids[(index + 1) % ids.size()])
		controls[ids[index]].focus_previous = NodePath("../" + ids[(index + ids.size() - 1) % ids.size()])
	for entry: Dictionary in data.entries: # 视觉牌统一位于命中层上方，但不接受输入。
		var badge: Control = Badge.new() # 只接收当前权限与焦点，不持有业务状态。
		badge.configure(entry, size, font)
		add_child(badge)
		_badges[entry.id] = badge

## [param event] 仅记录交互模态，不抢占窗口的按键。
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		_keyboard_mode = false
	elif event is InputEventKey and event.pressed:
		_keyboard_mode = true

## [param delta] 以秒推进轻微抬升和透明度；真实目标仍由原生 GUI 决定。
func _process(delta: float) -> void:
	refresh_target()
	for badge: Control in _badges.values(): # 每个牌匾独立收敛，不做持续弹跳。
		badge.advance(delta)

## 同时处理真实 UI 遮挡、键盘焦点与模态；窗口开启后立即取消背景反馈。
func refresh_target() -> void:
	if _badges.is_empty():
		return
	var blocked: bool = _blocked.call() # 与工具栏共用当前权威窗口状态。
	var target := "" # 当前最多一个建筑。
	var gui: Control = get_viewport().gui_get_hovered_control() # 真实工具栏和窗口始终优先。
	for id: String in controls: # 稳定命中控件不随视觉牌匾运动。
		var hit: Control = controls[id] # 原生 GUI 实际命中或键盘焦点。
		hit.set_input_allowed(not blocked)
		if not blocked and ((_keyboard_mode and hit.has_focus()) or (not _keyboard_mode and gui == hit)):
			target = id
	var target_mode := "" # 无目标时用于清除高亮。
	var target_pressed := false # 只呈现当前目标的短按反馈。
	for id: String in entries: # 每帧查询同一权限门面，档案切换后不保留旧牌匾。
		var entry: Dictionary = entries[id] # 只读入口身份和表现元数据。
		var state: Dictionary = _status.call(entry.feature) # 实时权威解锁状态。
		var allowed: bool = bool(state.allowed) # 可用性不由标签文字推断。
		var focused: bool = id == target # 鼠标与键盘共享一种视觉反馈。
		controls[id].mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if allowed else Control.CURSOR_ARROW
		_badges[id].set_state(allowed, str(state.get("reason", "")), focused, bool(controls[id].armed), blocked)
		if focused:
			target_mode = "available" if allowed else "locked"
			target_pressed = bool(controls[id].armed)
	hovered_id = target
	var signature: String = target + target_mode + str(target_pressed) if not target.is_empty() else "" # 无目标统一为空签名。
	if signature != _last_feedback:
		_last_feedback = signature
		highlight_changed.emit(target, target_mode, target_pressed)

## [param id] 通过真实门面重新校验；窗口打开后当帧清除所有背景交互。
func _activate(id: String) -> void:
	var accepted := false # 不根据旧悬停状态擅自打开。
	if entries.has(id) and not bool(_blocked.call()):
		accepted = bool(_open.call(entries[id].feature))
	action_requested.emit(id, accepted)
	refresh_target()
