## 场景与窗口共用的小花园加载表现；只拥有绘制状态，不读取业务数据或发起资源请求。
extends Control

## 单张手绘插画经 Godot 限制最长边为 512px，不引用植物场景。
const GARDEN = preload("res://assets/adventure/ui/loading/garden_companions.png")
## 原版加载条的泥土，保留游戏熟悉的园艺语言。
const SOIL = preload("res://assets/image/main_game_item/LoadBar_dirt.png")
## 原版草皮仅通过裁剪显示进度，不拉伸叶片。
const GRASS = preload("res://assets/image/main_game_item/LoadBar_grass.png")
## 小阳光只作轻微活动提示，不代表剩余时长。
const SUN = preload("res://assets/reanim/Sun2.png")
## 约 20KB 的原有英文字体；中文使用系统字体，不在启动时载入大型字库。
const BRAND_FONT = preload("res://assets/fonts/Bake_Soda.otf")
## 设计画布尺寸；所有内容随可用空间等比缩放。
const DESIGN := Vector2(1280, 720)
## 未揭幕前不把资源就绪冒充整体完成。
const PREPARED_LIMIT := 0.94

## 当前请求宿主提供的玩家标题。
var _heading_text := "冒险即将开始"
## 当前阶段的辅助说明，不含内部路径或百分比。
var _detail_text := "正在准备下一段旅程"
## 紧凑模式只绘制居中纸色卡片，保留宿主后方场景。
var _compact := false
## 当前已绘制的进度比例，只向前平滑移动。
var _displayed_progress := 0.0
## 宿主最新确认的进度目标，不因切换资源批次而倒退。
var _target_progress := 0.0
## 轻量动画使用不受暂停、倍速影响的真实时间。
var _elapsed := 0.0
## 上次动画处理的单调微秒时间，隐藏后恢复时重新取样。
var _last_usec := 0
## 内容展开独立于宿主的遮幕和输入锁。
var _opacity := 0.0
## 内容淡入的目标透明度，独立于整个遮幕的揭幕动画。
var _target_opacity := 1.0
## 失败时隐藏加载条，保留同样温和的可操作页面。
var _error := false
## 宿主控制的唯一动作，不写入跨场景快照。
var _action_text := ""
## 只属于当前宿主的动作，退出时立即清空且不参与快照。
var _action_callback: Callable
## 所有前景元素共用一个缩放与淡入节点。
var _canvas: Control
## 紧凑模式的纸色背景，随前景共同缩放与淡入。
var _panel: Panel
## 小花园插画，不包含可运行的角色节点。
var _art: TextureRect
## 全屏顶部的小型英文标识。
var _brand: Label
## 当前目的地或功能的居中标题。
var _heading: Label
## 标题下方可换行的阶段或失败说明。
var _detail: Label
## 唯一操作按钮；退出后不再接受鼠标与键盘焦点。
var _action: Button
## 草皮通过裁剪推进，纹理自身不被拉伸。
var _bar: Control
## 按显示进度改变宽度的草皮裁剪区域。
var _grass_clip: Control
## 随进度移动并轻微呼吸的阳光标记。
var _sun: TextureRect
## 小尺寸径向渐变，仅用于全屏背景；没有屏幕采样或模糊后处理。
var _backdrop: GradientTexture2D

## [param heading]、[param detail] 是玩家文案；[param compact] 切换卡片布局，不重置请求进度。
func configure(heading: String, detail: String = "", compact: bool = false) -> void:
	_heading_text = heading
	_detail_text = detail
	_compact = compact
	if is_instance_valid(_canvas):
		_layout()
		_update_text()
	queue_redraw()

## 只构造少量原生节点与小纹理，所有交互由宿主决定。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_last_usec = Time.get_ticks_usec()
	var font := SystemFont.new() # 使用系统中文字体，不为加载页引入 5MB 的游戏中文字库。
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "PingFang SC", "Noto Sans CJK SC", "sans-serif"])
	font.font_weight = 500
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	_panel = Panel.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var paper := StyleBoxFlat.new() # 暖纸、细金边与克制的阴影。
	paper.bg_color = Color("eee5ca")
	paper.border_color = Color("9eaa76")
	paper.set_border_width_all(2)
	paper.set_corner_radius_all(22)
	paper.shadow_color = Color(0.015, 0.035, 0.025, 0.26)
	paper.shadow_size = 24
	paper.shadow_offset = Vector2(0, 9)
	_panel.add_theme_stylebox_override("panel", paper)
	_canvas.add_child(_panel)
	_art = _texture(GARDEN)
	_canvas.add_child(_art)
	_brand = _label(BRAND_FONT, 20)
	_brand.text = "PVZ  ADVENTURE"
	_brand.modulate = Color("c5c59a")
	_heading = _label(font, 32)
	_detail = _label(font, 17)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bar = Control.new()
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.size = Vector2(321, 53)
	_canvas.add_child(_bar)
	var dirt := _texture(SOIL) # 原图中的土壤边缘保持自然轮廓。
	dirt.size = Vector2(321, 53)
	dirt.modulate = Color(0.86, 0.9, 0.78)
	_bar.add_child(dirt)
	_grass_clip = Control.new()
	_grass_clip.position = Vector2(4, -15)
	_grass_clip.clip_contents = true
	_grass_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(_grass_clip)
	var blades := _texture(GRASS) # 宽度固定，裁剪区沿进度扩展。
	blades.size = Vector2(314, 33)
	blades.modulate = Color(0.94, 0.96, 0.72)
	_grass_clip.add_child(blades)
	_sun = _texture(SUN)
	_sun.size = Vector2(24, 24)
	_sun.pivot_offset = _sun.size * 0.5
	_bar.add_child(_sun)
	_action = Button.new()
	_action.add_theme_font_override("font", font)
	_action.add_theme_font_size_override("font_size", 16)
	_style_action()
	_action.pressed.connect(_invoke_action)
	_canvas.add_child(_action)
	_create_backdrop()
	resized.connect(_layout)
	visibility_changed.connect(_sync_processing)
	_layout()
	_update_text()
	_update_motion()
	_sync_processing()

## 遮幕隐藏后停止动画和重绘，不给正常游戏帧留下常驻加载表现开销。
func _sync_processing() -> void:
	_last_usec = Time.get_ticks_usec()
	set_process(is_visible_in_tree())

## 返回尚未挂树的 [param texture] 展示节点，尺寸由当前布局指定。
func _texture(texture: Texture2D) -> TextureRect:
	var view := TextureRect.new() # 所有纹理都是表现元素，不参与输入。
	view.texture = texture
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return view

## 返回使用 [param font] 和 [param font_size] 的居中说明，同时加入前景画布。
func _label(font: Font, font_size: int) -> Label:
	var label := Label.new() # 可访问的原生文字，不烘焙进插画。
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(label)
	return label

## 原生渐变尺寸固定，不随大窗口创建高分辨率离屏缓冲。
func _create_backdrop() -> void:
	var colors := Gradient.new() # 中央带一点阳光，四周自然收深。
	colors.offsets = PackedFloat32Array([0.0, 0.64, 1.0])
	colors.colors = PackedColorArray([Color("344a34"), Color("1b382b"), Color("152d25")])
	_backdrop = GradientTexture2D.new()
	_backdrop.gradient = colors
	_backdrop.width = 256
	_backdrop.height = 144
	_backdrop.fill = GradientTexture2D.FILL_RADIAL
	_backdrop.fill_from = Vector2(0.5, 0.44)
	_backdrop.fill_to = Vector2(0.99, 0.99)

## 操作使用安静的文字胶囊，键盘焦点保留清晰描边。
func _style_action() -> void:
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]: # 五种状态共享轮廓，只改变对比度。
		var style := StyleBoxFlat.new() # 小按钮无需引用任何窗口皮肤图集。
		style.set_corner_radius_all(16)
		style.bg_color = Color(0.20, 0.31, 0.22, 0.05 if state == "normal" else 0.13)
		style.border_color = Color(0.34, 0.44, 0.27, 0.35 if state == "focus" else 0.0)
		style.set_border_width_all(2)
		_action.add_theme_stylebox_override(state, style)

## 布局只缩放当前表现，不修改宿主窗口或场景坐标。
func _layout() -> void:
	if not is_instance_valid(_canvas):
		return
	var fit: float = minf(size.x / DESIGN.x, size.y / DESIGN.y) # 窄屏与低分辨率保持内容完整。
	_canvas.position = size * 0.5
	_canvas.scale = Vector2.ONE * fit
	_panel.visible = _compact
	_panel.position = Vector2(-238, -225)
	_panel.size = Vector2(476, 450)
	_art.size = Vector2(348, 261) if _compact else Vector2(560, 420)
	_art.position = Vector2(-174, -224) if _compact else Vector2(-280, -260)
	_brand.visible = not _compact
	_brand.position = Vector2(-240, -296)
	_brand.size = Vector2(480, 38)
	_heading.position = Vector2(-220, 37) if _compact else Vector2(-400, 143)
	_heading.size = Vector2(440, 48) if _compact else Vector2(800, 50)
	_heading.add_theme_font_size_override("font_size", 26 if _compact else 32)
	_heading.modulate = Color("354a33") if _compact else Color("f1e9cd")
	_detail.position = Vector2(-209, 82) if _compact else Vector2(-300, 195)
	_detail.size = Vector2(418, 56) if _compact else Vector2(600, 40)
	_detail.modulate = Color("6b7859") if _compact else Color("b6c4a5")
	_bar.scale = Vector2.ONE * (0.76 if _compact else 0.88)
	_bar.position = Vector2(-122, 137) if _compact else Vector2(-141, 253)
	_action.position = Vector2(-62, 178) if _compact else Vector2(-62, 310)
	_action.size = Vector2(124, 32)
	_action.add_theme_color_override("font_color", Color("526545") if _compact else Color("d1d7b9"))
	_action.add_theme_color_override("font_hover_color", Color("304b2e") if _compact else Color("fff4d4"))
	_action.add_theme_color_override("font_focus_color", Color("304b2e") if _compact else Color("fff4d4"))
	_action.add_theme_color_override("font_pressed_color", Color("304b2e") if _compact else Color("fff4d4"))
	_action.add_theme_color_override("font_disabled_color", Color("6b7859") if _compact else Color("b6c4a5"))
	queue_redraw()

## [param _delta] 不参与计时；内容淡入与阳光呼吸使用墙钟间隔，不跟随暂停或倍速。
func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_usec() # 恢复长帧后限幅，避免装饰突然跳跃。
	var step: float = clampf(float(now - _last_usec) / 1_000_000.0, 0.0, 0.06) # 单帧动画步长，单位秒。
	_last_usec = now
	_elapsed += step
	_opacity = move_toward(_opacity, _target_opacity, step * 5.0)
	_displayed_progress = move_toward(_displayed_progress, _target_progress, step * 0.85)
	_update_motion()
	if not _compact:
		queue_redraw()

## 仅更新轻微位移与草皮裁剪；不创建粒子节点、角色或材质副本。
func _update_motion() -> void:
	if not is_instance_valid(_canvas):
		return
	_canvas.modulate.a = _opacity
	_grass_clip.size = Vector2(314.0 * _displayed_progress, 33)
	_sun.position = Vector2(4 + 308 * _displayed_progress - 12, -23 + sin(_elapsed * 1.4) * 1.8)
	_sun.rotation = sin(_elapsed * 0.65) * 0.12
	_sun.modulate.a = 0.65 + sin(_elapsed * 1.4) * 0.12
	_art.position.y = (-224.0 if _compact else -260.0) + sin(_elapsed * 0.85) * 2.0

## 全屏背景使用极少的柔和光点；紧凑版由模态拥有者绘制遮罩。
func _draw() -> void:
	if _compact or _backdrop == null:
		return
	draw_texture_rect(_backdrop, Rect2(Vector2.ZERO, size), false)
	var fit: float = minf(size.x / DESIGN.x, size.y / DESIGN.y) # 光点数量不随分辨率增长。
	for index: int in 12: # 固定位置与低幅漂移，禁止随机闪动。
		var x: float = 0.09 + fmod(float(index) * 0.173, 0.83) # 光点的归一化横坐标。
		var y: float = 0.17 + fmod(float(index) * 0.217, 0.69) # 光点的归一化纵坐标。
		var drift := Vector2(sin(_elapsed * 0.19 + index) * 6.0, cos(_elapsed * 0.23 + index) * 7.0) # 设计画布上的低幅漂移。
		draw_circle(Vector2(x * size.x, y * size.y) + drift * fit, (1.3 + (index % 3) * 0.7) * fit,
			Color(0.91, 0.82, 0.49, 0.10 + sin(_elapsed * 0.6 + index) * 0.025), true, -1.0, true)

## [param amount] 是宿主已知的准备比例；显示只向前，未完成时不达到满格。
func set_progress(amount: float) -> void:
	_target_progress = maxf(_target_progress, clampf(amount, 0.0, PREPARED_LIMIT))

## 宿主已确认完成；只改变目标值，不等待填充动画或延迟交接。
func finish() -> void:
	_target_progress = 1.0
	disable_action()

## 更新 [param text] 而不重建布局或重置动画。
func set_detail(text: String) -> void:
	_detail_text = text
	_update_text()

## [param value] 控制内容目标透明度；[param instant] 用于初始状态和跨场景恢复。
func set_content_visible(value: bool, instant: bool = false) -> void:
	_target_opacity = 1.0 if value else 0.0
	if instant:
		_opacity = _target_opacity
	_update_motion()

## [param message] 是可操作的失败原因；反馈不使用突然的红色警告或闪烁。
func show_error(message: String) -> void:
	_error = true
	_detail_text = message
	set_content_visible(true)
	_update_text()

## 将 [param text] 与 [param callback] 交给当前宿主的唯一操作按钮。
func set_action(text: String, callback: Callable) -> void:
	_action_text = text
	_action_callback = callback
	_update_text()

## 淡出后不允许旧取消按钮拦截新窗口输入。
func disable_action() -> void:
	_action_callback = Callable()
	if is_instance_valid(_action):
		_action.disabled = true
		_action.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_action.release_focus()
		_action.focus_mode = Control.FOCUS_NONE

## 仅已显示且可用的动作接受键盘焦点。
func focus_action() -> void:
	if is_instance_valid(_action) and _action.visible and not _action.disabled:
		_action.grab_focus()

## 按钮只派发当前宿主回调，不在表现层保存或改变玩家状态。
func _invoke_action() -> void:
	if _action_callback.is_valid():
		_action_callback.call()

## 同步已有标签，允许宿主在入树前配置。
func _update_text() -> void:
	if not is_instance_valid(_heading):
		return
	_heading.text = "暂时没能打开" if _error else _heading_text
	_detail.text = _detail_text
	_bar.visible = not _error
	_action.text = _action_text
	_action.visible = not _action_text.is_empty()
	_action.disabled = not _action_callback.is_valid()
	_action.mouse_filter = Control.MOUSE_FILTER_STOP if _action_callback.is_valid() else Control.MOUSE_FILTER_IGNORE
	_action.focus_mode = Control.FOCUS_ALL if _action_callback.is_valid() else Control.FOCUS_NONE

## 返回可交接的纯表现快照，不包含节点、资源或业务回调。
func snapshot() -> Dictionary:
	return {"heading": _heading_text, "detail": _detail_text, "compact": _compact,
		"displayed": _displayed_progress, "target": _target_progress, "elapsed": _elapsed,
		"opacity": _opacity, "target_opacity": _target_opacity, "error": _error}

## 恢复 [param state] 后继续同一画面，源场景释放不会让进度、插画或显隐重新开始。
func restore(state: Dictionary) -> void:
	_displayed_progress = float(state.get("displayed", 0.0))
	_target_progress = float(state.get("target", 0.0))
	_elapsed = float(state.get("elapsed", 0.0))
	_opacity = float(state.get("opacity", 0.0))
	_target_opacity = float(state.get("target_opacity", 1.0))
	_error = bool(state.get("error", false))
	configure(str(state.get("heading", _heading_text)), str(state.get("detail", _detail_text)), bool(state.get("compact", false)))
	_update_motion()
