extends Control
## 主菜单远征车：以地图和前木牌承接真实冒险入口，视觉与玩家进度解耦。

## 请求已完成权威校验；[param accepted] 表示现有地图入口是否接收动作。
signal action_requested(accepted: bool)

## 新前景的真实透明素材；不参与既有建筑合成链。
const ART_PATH := "res://assets/adventure/main_menu/coastal/foreground/expedition_camp.png"
## 独立前景受光与局部植物轻摆材质。
const CAMP_SHADER = preload("res://shaders/ui/main_menu/expedition_camp.gdshader")
## 原画画布内的固定位置，不随悬停移动整辆车。
const ART_POSITION := Vector2(440.0, 390.0)
## 1536×1024 素材等比缩到 800 像素宽。
const ART_SIZE := Vector2(800.0, 1600.0 / 3.0)
## 稳定地图与木牌命中轮廓；不拦截两侧植物与透明区域。
var _hit_polygon := PackedVector2Array([
	Vector2(213, 200), Vector2(476, 147), Vector2(517, 168),
	Vector2(598, 253), Vector2(586, 281), Vector2(617, 309),
	Vector2(614, 394), Vector2(602, 408), Vector2(215, 408),
	Vector2(199, 393), Vector2(199, 316), Vector2(214, 285),
	Vector2(233, 274)
])
## 主动作文字的固定局部位置；只允许 2 像素悬停抬升。
const LABEL_POSITION := Vector2(225, 309)
## 权威地图状态查询，由宿主注入。
var _status: Callable
## 权威地图动作，由宿主注入。
var _action: Callable
## 场景、导航、教学及模态的统一阻塞查询。
var _blocked: Callable
## 独占前景材质实例，避免多个预览互相修改参数。
var _material: ShaderMaterial
## 始终忽略鼠标的前景美术。
var _art: TextureRect
## 木牌上的主动作名称。
var _action_label: Label
## 聚焦时才显示的真实不可用原因。
var _reason_label: Label
## 当前交互方式，防止鼠标离开后保留陈旧键盘反馈。
var _keyboard_mode := false
## 当前权威可用性，只影响本控件表现。
var _allowed := false
## 当前统一阻塞状态，阻塞时释放输入捕获。
var _input_blocked := true
## 当前鼠标或键盘视觉焦点。
var _focused := false
## 当前按下归属；释放仍须在本控件且重新校验权限。
var armed := false
## 按下是否来自键盘，避免鼠标释放完成键盘动作。
var _keyboard_armed := false
## 平滑后的聚焦强度，范围为 0 至 1。
var _focus_amount := 0.0
## 当前真实时段的灯光权重，范围为 0 至 1。
var _night_amount := 0.0

## [param status] 查询地图状态，[param action] 提交地图请求，[param blocked] 查询统一阻塞。
## [param font] 为主菜单真实字体；须在加入场景前调用，不创建全局状态或导航实例。
func configure(status: Callable, action: Callable, blocked: Callable, font: Font) -> void:
	name = "ExpeditionCamp"
	position = ART_POSITION
	size = ART_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	accessibility_name = "开始冒险"
	_status = status
	_action = action
	_blocked = blocked
	focus_exited.connect(_on_focus_exited)
	_material = ShaderMaterial.new()
	_material.shader = CAMP_SHADER
	_art = TextureRect.new()
	_art.name = "CampArtwork"
	_art.texture = load(ART_PATH) as Texture2D
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_SCALE
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.show_behind_parent = true
	_art.material = _material
	_art.size = ART_SIZE
	add_child(_art)
	_action_label = _make_label(font, 42)
	_action_label.name = "AdventureAction"
	_action_label.text = "开始冒险"
	_action_label.position = LABEL_POSITION
	_action_label.size = Vector2(310, 73)
	_action_label.add_theme_color_override("font_color", Color("fff0c6"))
	_action_label.add_theme_color_override("font_outline_color", Color("563317"))
	_action_label.add_theme_constant_override("outline_size", 5)
	_action_label.add_theme_color_override("font_shadow_color", Color(0.18, 0.085, 0.025, 0.65))
	_action_label.add_theme_constant_override("shadow_offset_y", 2)
	_reason_label = _make_label(font, 17)
	_reason_label.name = "UnavailableReason"
	_reason_label.position = Vector2(224, 374)
	_reason_label.size = Vector2(370, 24)
	_reason_label.add_theme_color_override("font_color", Color("f6e3b9"))
	_reason_label.add_theme_color_override("font_outline_color", Color("4d2a12"))
	_reason_label.add_theme_constant_override("outline_size", 3)
	_reason_label.hide()

## [param font] 与 [param font_size] 指定本地标签字体；返回不拦截输入的居中标签。
func _make_label(font: Font, font_size: int) -> Label:
	var label := Label.new() # 标签的整个矩形均穿透到稳定多边形命中。
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	add_child(label)
	return label

## [param values] 来自菜单同一显示时钟；[param seconds] 是可暂停回放的单调动作时间。
func set_environment(values: Dictionary, seconds: float) -> void:
	if _material == null:
		return
	_material.set_shader_parameter("ambient_rgb", values.get("ambient_rgb", Vector3(0.57, 0.64, 0.76)))
	_material.set_shader_parameter("key_rgb", values.get("key_rgb", Vector3(0.63, 0.50, 0.31)))
	_night_amount = clampf(float(values.get("window_energy", 0.0)), 0.0, 1.0)
	_material.set_shader_parameter("window_energy", _night_amount)
	_material.set_shader_parameter("effect_seconds", seconds)

## [param event] 只记录输入来源，不抢占工具栏、窗口或父级按键。
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		_keyboard_mode = false
	elif event is InputEventKey and event.pressed:
		_keyboard_mode = true

## [param delta] 仅推进轻微文字抬升与木牌提亮；植物动作由宿主显式时间驱动。
func _process(delta: float) -> void:
	refresh_target()
	var desired: float = 1.0 if _focused else 0.0 # 无周期闪烁，仅响应当前焦点。
	_focus_amount = lerpf(_focus_amount, desired, 1.0 - exp(-maxf(delta, 0.0) * 12.0))
	if absf(_focus_amount - desired) < 0.001:
		_focus_amount = desired
	var lift: float = _focus_amount * (0.5 if armed else 2.0) # 只有文字和箭头轻抬，木牌与地面固定。
	_action_label.position = LABEL_POSITION - Vector2(0, lift)
	_action_label.modulate = Color.WHITE.lerp(Color("e9dabd"), _night_amount * 0.28)
	_material.set_shader_parameter("hover_amount", _focus_amount * (1.0 if _allowed else 0.16) * (0.68 if armed else 1.0))
	queue_redraw()

## 查询当帧真实目标和权限；模态出现时立即取消按下、焦点与木牌高亮。
func refresh_target() -> void:
	if not _status.is_valid() or not _blocked.is_valid():
		return
	_input_blocked = bool(_blocked.call())
	var state: Dictionary = _status.call("map") # 与原港口和工具栏共用地图状态。
	_allowed = bool(state.get("allowed", false))
	if _input_blocked:
		armed = false
		_keyboard_armed = false
		_focus_amount = 0.0
		if has_focus():
			release_focus()
		_material.set_shader_parameter("hover_amount", 0.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE if _input_blocked else Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if _allowed and not _input_blocked else Control.CURSOR_ARROW
	var current_focus: bool = not _input_blocked and ((has_focus() and _keyboard_mode) or (not _keyboard_mode and get_viewport().gui_get_hovered_control() == self)) # 原生最上层 GUI 决定鼠标归属。
	if current_focus and not _focused and _allowed:
		_play_sound(&"bleep")
	_focused = current_focus
	var reason: String = str(state.get("reason", "")) # 不增加任何虚构的开放条件或关卡进度。
	_reason_label.text = "未开放" if reason == "尚未开放" else reason
	_reason_label.visible = _focused and not _allowed and not reason.is_empty()

## [param point] 为控件局部坐标；透明区域不拦截原建筑，阻塞时完全退出命中。
func _has_point(point: Vector2) -> bool:
	if not _blocked.is_valid() or bool(_blocked.call()):
		return false
	return Geometry2D.is_point_in_polygon(point, _hit_polygon)

## [param event] 使用原生 GUI 捕获；鼠标须同目标按下释放，键盘使用同一激活门面。
func _gui_input(event: InputEvent) -> void:
	if not _blocked.is_valid() or bool(_blocked.call()):
		armed = false
		_keyboard_armed = false
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			grab_focus()
			armed = true
			_keyboard_armed = false
		else:
			var submit: bool = armed and not _keyboard_armed and _has_point(event.position) and get_viewport().gui_get_hovered_control() == self # 上层工具栏覆盖时取消捕获释放。
			armed = false
			if submit:
				_activate()
		accept_event()
	elif event.is_action_pressed(&"ui_accept") and not event.is_echo():
		armed = true
		_keyboard_armed = true
		accept_event()
	elif event.is_action_released(&"ui_accept"):
		var submit: bool = armed and _keyboard_armed and has_focus() # 焦点被窗口移走后不能完成旧按下。
		armed = false
		_keyboard_armed = false
		if submit:
			_activate()
		accept_event()

## 提交时重新调用真实地图门面；拒绝请求不会自行创建窗口或改写存档。
func _activate() -> void:
	var accepted := false # 不相信上一帧缓存的 allowed。
	if _action.is_valid() and _blocked.is_valid() and not bool(_blocked.call()):
		accepted = bool(_action.call("map"))
	if accepted:
		_play_sound(&"buttonclick")
	action_requested.emit(accepted)
	refresh_target()

## [param cue] 使用现有 SoundManager 音效；独立美术预览没有该自动加载时保持静音。
func _play_sound(cue: StringName) -> void:
	var sound_manager: Node = get_node_or_null("/root/SoundManager") # 只查找既有自动加载，不创建另一套播放器。
	if sound_manager != null:
		sound_manager.call("play_other_SFX", cue)

## 通过 Tab 或前景窗口移走焦点时取消未完成的按下，防止恢复焦点后沿用旧动作。
func _on_focus_exited() -> void:
	armed = false
	_keyboard_armed = false

## 在主木牌文字旁绘制方向箭头，避免图形字体缺字；全部位于固定可点击区域内。
func _draw() -> void:
	var lift: float = _focus_amount * (0.5 if armed else 2.0) # 与文字共享短按抬升量。
	var center := Vector2(510, 346 - lift) # 对齐“开始冒险”的视觉中线。
	var shade := Color(0.26, 0.13, 0.045, 0.9) # 木牌上的暗色细阴影。
	var ink := Color("f4dfaa").lerp(Color("fff3cc"), _focus_amount) # 聚焦时轻微增亮，不呼吸闪烁。
	draw_line(center + Vector2(-12, 2), center + Vector2(12, 2), shade, 5.0, true)
	draw_polyline(PackedVector2Array([center + Vector2(4, -6), center + Vector2(12, 2), center + Vector2(4, 10)]), shade, 5.0, true)
	draw_line(center + Vector2(-12, 0), center + Vector2(12, 0), ink, 2.8, true)
	draw_polyline(PackedVector2Array([center + Vector2(4, -8), center + Vector2(12, 0), center + Vector2(4, 8)]), ink, 2.8, true)
