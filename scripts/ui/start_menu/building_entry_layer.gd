extends Control
## 场景式入口控制：统一目标、名称和请求；实际功能/解锁/模态由注入门面所有。
## 视觉层只接收当前目标，不在输入层重建动态坐标。
signal highlight_changed(entry_id: String, mode: String, pressed: bool)
## 每次请求记录接受与否，供预览和可访问反馈使用。
signal action_requested(entry_id: String, accepted: bool)
## 稳定命中控件的唯一实现。
const Hit = preload("res://scripts/ui/start_menu/building_entry_hit.gd")
## 权威入口元数据及运行命中对象。
var entries: Dictionary = {}
var controls: Dictionary = {}
## 业务依赖均由宿主显式提供。
var _status: Callable
var _open: Callable
var _blocked: Callable
## 当前可见目标和视觉状态。
var hovered_id := ""
var _last_feedback := ""
## 键盘导航与鼠标悬停不能互相保持陈旧焦点。
var _keyboard_mode := false
## 唯一悬停名称牌。
var _caption: Label

## [param data] 定义入口；三个Callable分别查询、提交、阻塞，复用工具栏而非新全局。
func configure(data: Dictionary, status: Callable, action: Callable, blocked: Callable, font: Font) -> void:
	_status=status
	_open=action
	_blocked=blocked
	size=Vector2(data.canvas[0],data.canvas[1])
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	for entry: Dictionary in data.entries:
		entries[entry.id]=entry
		var hit: Control=Hit.new() # 每个建筑一份稳定命中轮廓。
		hit.configure(entry,size)
		add_child(hit)
		hit.activated.connect(_activate)
		controls[entry.id]=hit
	var ids: Array=controls.keys() # 明确键盘顺序，不让全屏命中框的位置决定焦点。
	for index: int in ids.size():
		controls[ids[index]].focus_next=NodePath("../"+ids[(index+1)%ids.size()])
		controls[ids[index]].focus_previous=NodePath("../"+ids[(index+ids.size()-1)%ids.size()])
	_caption=Label.new()
	_caption.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	_caption.add_theme_font_override("font",font)
	_caption.add_theme_font_size_override("font_size",25)
	_caption.add_theme_color_override("font_color",Color("fff2d1"))
	_caption.add_theme_color_override("font_outline_color",Color("2a2118"))
	_caption.add_theme_constant_override("outline_size",4)
	_caption.add_theme_constant_override("line_spacing",3)
	add_child(_caption)
	_caption.hide()

## [param event] 仅记录交互模态，不抢占窗口的按键。
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		_keyboard_mode=false
	elif event is InputEventKey and event.pressed:
		_keyboard_mode=true

## [param delta] 只用于框架回调；输入状态每帧重新取GUI真实最上层目标。
func _process(_delta: float) -> void:
	refresh_target()

## 同时处理UI遮挡与模态；只拦点击而不清hover是不完整的。
func refresh_target() -> void:
	if _caption==null:
		return
	var blocked: bool=_blocked.call() # 当前同一权威窗口状态。
	for hit: Control in controls.values():
		hit.set_input_allowed(not blocked)
	var target := "" # 最多一个当前建筑。
	var gui: Control=get_viewport().gui_get_hovered_control() # 让实际工具栏/窗口优先。
	if not blocked:
		for id: String in controls:
			var hit: Control=controls[id] # 原生GUI实际命中或键盘焦点。
			if (_keyboard_mode and hit.has_focus()) or (not _keyboard_mode and gui==hit):
				target=id
				break
	if target.is_empty():
		hovered_id=""
		_caption.hide()
		if not _last_feedback.is_empty():
			_last_feedback=""
			highlight_changed.emit("","",false)
		return
	var entry: Dictionary=entries[target] # 只读元数据。
	var state: Dictionary=_status.call(entry.feature) # 实时权威解锁状态。
	var mode := "available" if state.allowed else "locked" # 未开放/锁定均弱反馈，文案有区别。
	controls[target].mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND if state.allowed else Control.CURSOR_ARROW
	var caption: String=entry.name+" · "+entry.title if entry.name!=entry.title else entry.name # 不常驻多个牌匾。
	caption+="\n点击进入" if state.allowed else "\n"+str(state.reason)
	_caption.text=caption
	_caption.size=Vector2(460,83)
	var anchor: Array=entry.anchor # 采用原画坐标，随画布同一缩放。
	_caption.position=Vector2(clampf(float(anchor[0])-230,4,size.x-464),clampf(float(anchor[1]),4,size.y-88))
	_caption.show()
	hovered_id=target
	var pressed: bool=controls[target].armed # 短按下反馈不触发打开。
	var signature: String=target+mode+str(pressed)+caption # 档案变化即刷新。
	if signature!=_last_feedback:
		_last_feedback=signature
		highlight_changed.emit(target,mode,pressed)

## [param id] 通过真实门面重新校验；窗口打开后当帧清除所有背景交互。
func _activate(id: String) -> void:
	var accepted := false # 不根据旧hover状态擅自打开。
	if entries.has(id) and not bool(_blocked.call()):
		accepted=bool(_open.call(entries[id].feature))
	action_requested.emit(id,accepted)
	refresh_target()
