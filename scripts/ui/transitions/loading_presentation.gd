## 加载的纯视觉反馈；正常状态不显示说明文字，只在失败时提供可操作信息。
extends Control

## 全屏使用的静态花园插画；不引用植物场景，导入最长边限制为 512px。
const GARDEN = preload("res://assets/adventure/ui/loading/garden_companions.png")
## 加载条底部的泥土纹理。
const SOIL = preload("res://assets/image/main_game_item/LoadBar_dirt.png")
## 按已知进度裁剪的草皮纹理。
const GRASS = preload("res://assets/image/main_game_item/LoadBar_grass.png")
## 单个资源超过三秒才显示的轻量文字控件，不增加其他动效。
const ResourceHint = preload("res://scripts/ui/transitions/loading_resource_hint.gd")
## 所有布局坐标以此画布等比缩放。
const DESIGN := Vector2(1280, 720)
## 准备资源不代表已可交互，揭幕前不填满进度。
const PREPARED_LIMIT := 0.94

## 窗口加载使用小提示，保留原场景且不重复展示插画。
var _compact := false
## 已绘制进度，取值 0..1，只向前平滑移动。
var _displayed_progress := 0.0
## 当前请求已确认的进度目标。
var _target_progress := 0.0
## 上次更新的单调微秒时间，不受暂停或倍速影响。
var _last_usec := 0
## 内容当前透明度，取值 0..1，独立于宿主的遮幕。
var _opacity := 0.0
## 内容淡入的目标透明度。
var _target_opacity := 1.0
## 失败时替换进度为说明，不继续播放正常加载表现。
var _error := false
## 仅在失败状态展示的可操作说明。
var _error_message := ""
## 宿主提供的取消、返回或重试按钮文字。
var _action_text := ""
## 动作只属于当前宿主，退出立即清空且不参与跨场景快照。
var _action_callback: Callable
## 全部前景共用的居中缩放与淡入节点。
var _canvas: Control
## 紧凑提示或错误反馈的底板。
var _panel: Panel
## 全屏静态插画，没有上下漂浮或呼吸动画。
var _art: TextureRect
## 唯一说明标签，只在错误状态可见。
var _message: Label
## 唯一操作按钮，淡出时同步释放输入和焦点。
var _action: Button
## 单个慢资源的说明行，默认不占任何视觉空间。
var _resource_hint: Label
## 组合泥土与草皮的进度条。
var _bar: Control
## 只改变裁剪宽度，不拉伸草皮。
var _grass_clip: Control
## 小尺寸静态渐变，不使用粒子、屏幕采样或后处理。
var _backdrop: GradientTexture2D

## [param compact] 选择窗口的小提示或全屏插画；不重置进度与显隐。
func configure(compact: bool = false) -> void:
	_compact = compact
	if is_instance_valid(_canvas):
		_layout()
	queue_redraw()

## 只构造表现节点；正常状态无需阅读标题、阶段或品牌文字。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var font := SystemFont.new() # 仅取消按钮和失败说明需要中文字体。
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "PingFang SC", "Noto Sans CJK SC", "sans-serif"])
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	_panel = Panel.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var paper := StyleBoxFlat.new() # 小提示沿用暖纸底色，减小边框与阴影的存在感。
	paper.bg_color = Color("eee5ca")
	paper.border_color = Color("9eaa76")
	paper.set_border_width_all(1)
	paper.set_corner_radius_all(14)
	paper.shadow_color = Color(0.015, 0.035, 0.025, 0.18)
	paper.shadow_size = 12
	paper.shadow_offset = Vector2(0, 4)
	_panel.add_theme_stylebox_override("panel", paper)
	_canvas.add_child(_panel)
	_art = _texture(GARDEN)
	_canvas.add_child(_art)
	_message = Label.new()
	_message.add_theme_font_override("font", font)
	_message.add_theme_font_size_override("font_size", 18)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_message)
	_bar = Control.new()
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.size = Vector2(321, 53)
	_canvas.add_child(_bar)
	var dirt := _texture(SOIL) # 保留原版泥土边缘，不额外描边或缩放动画。
	dirt.size = Vector2(321, 53)
	dirt.modulate = Color(0.86, 0.9, 0.78)
	_bar.add_child(dirt)
	_grass_clip = Control.new()
	_grass_clip.position = Vector2(4, -15)
	_grass_clip.clip_contents = true
	_grass_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(_grass_clip)
	var blades := _texture(GRASS) # 纹理宽度固定，裁剪区按真实准备进度扩展。
	blades.size = Vector2(314, 33)
	blades.modulate = Color(0.94, 0.96, 0.72)
	_grass_clip.add_child(blades)
	_action = Button.new()
	_action.add_theme_font_override("font", font)
	_action.add_theme_font_size_override("font_size", 14)
	_style_action()
	_action.pressed.connect(_invoke_action)
	_canvas.add_child(_action)
	_resource_hint = ResourceHint.new()
	_resource_hint.hide()
	_canvas.add_child(_resource_hint)
	_create_backdrop()
	resized.connect(_layout)
	visibility_changed.connect(_sync_processing)
	_layout()
	_update_state()
	_update_visuals()
	_sync_processing()

## 仅在可见且透明度或进度需要变化时处理；静止和隐藏状态不持续重绘。
func _sync_processing() -> void:
	var active: bool = is_visible_in_tree() and (not is_equal_approx(_opacity, _target_opacity) or (not _error and not is_equal_approx(_displayed_progress, _target_progress))) # 只有有效视觉变化需要逐帧更新。
	if active and not is_processing():
		_last_usec = Time.get_ticks_usec()
	set_process(active)

## 返回尚未挂树的 [param texture] 展示节点，不参与输入。
func _texture(texture: Texture2D) -> TextureRect:
	var view := TextureRect.new() # 所有素材共用原生等比显示方式。
	view.texture = texture
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return view

## 全屏只用静态颜色过渡，不让背景持续漂移或闪烁。
func _create_backdrop() -> void:
	var colors := Gradient.new() # 中央略亮，边缘与宿主遮幕颜色一致。
	colors.offsets = PackedFloat32Array([0.0, 0.64, 1.0])
	colors.colors = PackedColorArray([Color("344a34"), Color("1b382b"), Color("152d25")])
	_backdrop = GradientTexture2D.new()
	_backdrop.gradient = colors
	_backdrop.width = 256
	_backdrop.height = 144
	_backdrop.fill = GradientTexture2D.FILL_RADIAL
	_backdrop.fill_from = Vector2(0.5, 0.44)
	_backdrop.fill_to = Vector2(0.99, 0.99)

## 取消操作保持可见但不突出；键盘焦点仍有明确轮廓。
func _style_action() -> void:
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]: # 普通状态透明，交互时才显示底色。
		var style := StyleBoxFlat.new() # 小型原生按钮无需额外图片资源。
		style.set_corner_radius_all(12)
		style.bg_color = Color(0.20, 0.31, 0.22, 0.0 if state == "normal" else 0.09)
		style.border_color = Color(0.34, 0.44, 0.27, 0.45 if state == "focus" else 0.0)
		style.set_border_width_all(1)
		_action.add_theme_stylebox_override(state, style)

## 窗口只留小进度提示；全屏插画与进度条组成一个静态视觉中心。
func _layout() -> void:
	if not is_instance_valid(_canvas):
		return
	var fit: float = minf(size.x / DESIGN.x, size.y / DESIGN.y) # 窄屏保持完整布局。
	_canvas.position = size * 0.5
	_canvas.scale = Vector2.ONE * fit
	_panel.visible = _compact
	_panel.position = Vector2(-170, -90) if _error else Vector2(-156, -44)
	_panel.size = Vector2(340, 180) if _error else Vector2(312, 112)
	_art.visible = not _compact and not _error
	_art.size = Vector2(480, 360)
	_art.position = Vector2(-240, -216)
	_message.position = Vector2(-145, -66) if _compact else Vector2(-250, -38)
	_message.size = Vector2(290, 80) if _compact else Vector2(500, 80)
	_message.modulate = Color("354a33") if _compact else Color("f1e9cd")
	_bar.scale = Vector2.ONE * (0.70 if _compact else 0.80)
	_bar.position = Vector2(-112, -11) if _compact else Vector2(-128, 112)
	_resource_hint.configure(_compact)
	_action.position = Vector2(-52, 34) if _error and _compact else (Vector2(-38, 28) if _compact else Vector2(-52, 62))
	_action.size = Vector2(76, 28) if _compact and not _error else Vector2(104, 32)
	for state: String in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_disabled_color"]: # 避免全局主题的白字落在浅底上。
		_action.add_theme_color_override(state, Color("40573a") if _compact else Color("e2e7cf"))
	queue_redraw()

## [param _delta] 不参与计时；只有淡入和进度推进需要真实时间更新。
func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_usec() # 单调时间与游戏速度无关。
	var step: float = clampf(float(now - _last_usec) / 1_000_000.0, 0.0, 0.06) # 真实秒数，长帧后不突然跳变。
	_last_usec = now
	_opacity = move_toward(_opacity, _target_opacity, step * 7.0)
	if not _error:
		_displayed_progress = move_toward(_displayed_progress, _target_progress, step * 0.85)
	_update_visuals()
	_sync_processing()

## 只更新透明度和裁剪宽度，不移动、旋转或缩放插画。
func _update_visuals() -> void:
	if not is_instance_valid(_canvas):
		return
	_canvas.modulate.a = _opacity
	_grass_clip.size = Vector2(314.0 * _displayed_progress, 33)

## 全屏绘制静态背景；紧凑模式由宿主控制遮罩。
func _draw() -> void:
	if not _compact and _backdrop != null:
		draw_texture_rect(_backdrop, Rect2(Vector2.ZERO, size), false)

## [param amount] 为已知准备比例，不因批次变化而倒退，也不提前填满。
func set_progress(amount: float) -> void:
	_target_progress = maxf(_target_progress, clampf(amount, 0.0, PREPARED_LIMIT))
	_sync_processing()

## 仅接收当前批次的活动快照；短加载不改变现有版式。
func set_resource_activity(activity: Dictionary) -> void:
	if is_instance_valid(_resource_hint):
		_resource_hint.present({} if _error else activity)

## 交付已完成；不等待进度条填满，立即禁用旧操作。
func finish() -> void:
	set_resource_activity({})
	_target_progress = 1.0
	disable_action()
	_sync_processing()

## [param value] 控制内容显隐；[param instant] 用于首屏和跨场景快照恢复。
func set_content_visible(value: bool, instant: bool = false) -> void:
	_target_opacity = 1.0 if value else 0.0
	if instant:
		_opacity = _target_opacity
	_update_visuals()
	_sync_processing()

## [param message] 仅用于失败，正常准备阶段没有说明文字。
func show_error(message: String) -> void:
	set_resource_activity({})
	_error = true
	_error_message = message
	_layout()
	_update_state()
	set_content_visible(true)

## [param text] 与 [param callback] 定义唯一必要操作，不进入快照。
func set_action(text: String, callback: Callable) -> void:
	_action_text = text
	_action_callback = callback
	_update_state()

## 旧反馈退出时同步释放键盘焦点与鼠标，不影响新窗口已有的焦点。
func disable_action() -> void:
	_action_callback = Callable()
	if is_instance_valid(_action):
		_action.disabled = true
		_action.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_action.release_focus()
		_action.focus_mode = Control.FOCUS_NONE

## 仅可用动作接受焦点，宿主决定是否需要聚焦。
func focus_action() -> void:
	if is_instance_valid(_action) and _action.visible and not _action.disabled:
		_action.grab_focus()

## 动作只调用当前宿主，不保存或修改业务状态。
func _invoke_action() -> void:
	if _action_callback.is_valid():
		_action_callback.call()

## 正常状态没有标签，失败才显示说明；操作仍由宿主控制。
func _update_state() -> void:
	if not is_instance_valid(_message):
		return
	_message.visible = _error
	_message.text = _error_message if _error else ""
	_bar.visible = not _error
	_action.text = _action_text
	_action.visible = not _action_text.is_empty()
	_action.disabled = not _action_callback.is_valid()
	_action.mouse_filter = Control.MOUSE_FILTER_STOP if _action_callback.is_valid() else Control.MOUSE_FILTER_IGNORE
	_action.focus_mode = Control.FOCUS_ALL if _action_callback.is_valid() else Control.FOCUS_NONE

## 返回纯表现快照，不含业务对象、正常加载文案或装饰动画相位。
func snapshot() -> Dictionary:
	return {"compact": _compact, "displayed": _displayed_progress, "target": _target_progress,
		"opacity": _opacity, "target_opacity": _target_opacity, "error": _error, "message": _error_message}

## [param state] 在首帧前恢复进度和显隐，避免目标场景重新播放加载内容。
func restore(state: Dictionary) -> void:
	_displayed_progress = float(state.get("displayed", 0.0))
	_target_progress = float(state.get("target", 0.0))
	_opacity = float(state.get("opacity", 0.0))
	_target_opacity = float(state.get("target_opacity", 1.0))
	_error = bool(state.get("error", false))
	_error_message = str(state.get("message", ""))
	set_resource_activity({})
	configure(bool(state.get("compact", false)))
	_update_state()
	_update_visuals()
	_sync_processing()
