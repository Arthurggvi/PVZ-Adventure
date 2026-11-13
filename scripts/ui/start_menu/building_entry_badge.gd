extends Control
## 建筑前的小型暖色牌匾：主入口边缘随港口高亮呼吸，聚焦时轻抬；始终不参与输入路由。

## 名称字形与宽度测量使用同一字体。
var _font: Font
## 简短入口名称，不拼接功能清单。
var _title := ""
## 原画坐标下的牌匾顶部锚点；可用牌匾位于现有命中轮廓内部。
var _anchor := Vector2.ZERO
## 原画画布尺寸，用于防止长锁定原因超出边缘。
var _canvas_size := Vector2.ZERO
## 港口主入口采用略大的字号与牌面。
var _primary := false
## 是否允许可用状态下保留安静的常驻标签。
var _resting := false
## 当前权限仅来自宿主查询结果。
var _available := false
## 当前名称与必要解锁原因的缓存，避免每帧重排文本。
var _content_key := ""
## 平滑后的焦点强度，范围为 0 至 1。
var _focus_amount := 0.0
## 当前目标焦点强度。
var _focus_goal := 0.0
## 与场景轮廓同步的引导强度，范围为 0 至 1。
var _guide_strength := 0.0
## 平滑后的显示透明度，范围为 0 至 1。
var _opacity := 0.0
## 当前目标显示透明度。
var _opacity_goal := 0.0
## 按下期间取消部分抬升，释放恢复。
var _pressed := false
## 暖深色框面及柔和阴影，只属于当前牌匾实例。
var _frame := StyleBoxFlat.new()
## 单行入口名称。
var _name_label: Label
## 仅在锁定且原因必要时显示的第二行说明。
var _reason_label: Label

## [param entry] 提供短名、锚点和主次级别；[param canvas_size] 是同一原画尺寸；[param font] 决定字体。
func configure(entry: Dictionary, canvas_size: Vector2, font: Font) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = font
	_title = str(entry.get("label", entry.name))
	var label_anchor: Array = entry.get("label_anchor", entry.anchor) # 标签位置独立于原有制作锚点，不改命中多边形。
	_anchor = Vector2(label_anchor[0], label_anchor[1])
	_canvas_size = canvas_size
	_primary = bool(entry.get("primary", false))
	_resting = bool(entry.get("resting_label", false))
	_frame.set_corner_radius_all(5)
	_frame.set_border_width_all(1)
	_frame.shadow_color = Color(0.04, 0.035, 0.025, 0.28)
	_frame.shadow_size = 7
	_frame.shadow_offset = Vector2(0, 3)
	_name_label = _make_label(27 if _primary else 23)
	_reason_label = _make_label(15)
	_reason_label.add_theme_color_override("font_color", Color("c9c4b5"))
	_reason_label.hide()
	modulate.a = 0.0
	hide()

## [param font_size] 为原画像素字号；返回忽略鼠标的居中标签并加入当前节点。
func _make_label(font_size: int) -> Label:
	var label := Label.new() # 所有子控件同样穿透鼠标，避免覆盖稳定建筑命中。
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("ede0bf"))
	label.add_theme_color_override("font_outline_color", Color(0.08, 0.07, 0.05, 0.45))
	label.add_theme_constant_override("outline_size", 2)
	add_child(label)
	return label

## [param allowed] 与 [param reason] 均为真实门面结果；[param focused] 同时覆盖键盘和鼠标。
## [param pressed] 只改变视觉抬升；[param blocked] 为真时当帧隐藏牌匾，不让背景反馈穿过模态。
func set_state(allowed: bool, reason: String, focused: bool, pressed: bool, blocked: bool) -> void:
	_available = allowed
	_pressed = pressed and focused
	_focus_goal = 1.0 if focused and not blocked else 0.0
	_opacity_goal = (1.0 if focused else (0.96 if _primary else 0.82)) if not blocked and (focused or (_resting and allowed)) else 0.0
	var detail: String = "" if allowed else reason.strip_edges() # 不替换真实解锁条件或臆造不可用原因。
	if detail == "尚未开放":
		detail = "未开放"
	var key: String = str(allowed) + detail # 只在文字或权限改变时计算尺寸。
	if key != _content_key:
		_content_key = key
		_name_label.text = _title
		_reason_label.text = detail
		_reason_label.visible = not detail.is_empty()
		var font_size: int = 27 if _primary else 23 # 与名称标签保持同一字号。
		var title_width: float = _font.get_string_size(_title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x # 保持短名牌紧凑。
		var detail_width: float = _font.get_string_size(detail, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x if not detail.is_empty() else 0.0 # 原因只占所需宽度。
		size = Vector2(maxf(146.0 if _primary else 102.0, maxf(title_width + 40.0, detail_width + 32.0)), 51.0 if _primary else 43.0)
		if not detail.is_empty():
			size.y += 21.0
		_name_label.position = Vector2(8, 1)
		_name_label.size = Vector2(size.x - 16.0, 48.0 if _primary else 40.0)
		_reason_label.position = Vector2(10, size.y - 25)
		_reason_label.size = Vector2(size.x - 20, 21)
		queue_redraw()
	if blocked:
		_opacity = 0.0
		modulate.a = 0.0
		hide()

## [param delta] 是帧间秒数；[param guide_wave] 是当前呼吸强度，0 表示此入口不参与引导。
## 返回供场景轮廓同步使用的强度；聚焦时收敛到稳定亮度，锁定或遮挡时归零。
func advance(delta: float, guide_wave: float) -> float:
	var blend: float = 1.0 - exp(-maxf(delta, 0.0) * 13.0) # 约 0.2 秒完成主要视觉过渡。
	var previous_focus: float = _focus_amount # 判断焦点是否仍在变化。
	var previous_opacity: float = _opacity # 判断显隐是否仍在变化。
	_focus_amount = lerpf(_focus_amount, _focus_goal, blend)
	_opacity = lerpf(_opacity, _opacity_goal, blend)
	if absf(_focus_amount - _focus_goal) < 0.001:
		_focus_amount = _focus_goal
	if absf(_opacity - _opacity_goal) < 0.001:
		_opacity = _opacity_goal
	var previous_guide: float = _guide_strength # 呼吸只在边缘亮度变化时触发重绘。
	_guide_strength = lerpf(guide_wave, 0.78, _focus_amount) if guide_wave > 0.0 and _available and _opacity_goal > 0.0 else 0.0
	visible = _opacity > 0.005
	modulate.a = _opacity
	var lift: float = _focus_amount * (1.0 if _pressed else 3.0) # 仅聚焦时轻抬，不改变命中框。
	position = Vector2(clampf(_anchor.x - size.x * 0.5, 8.0, _canvas_size.x - size.x - 8.0), clampf(_anchor.y - lift, 8.0, _canvas_size.y - size.y - 8.0))
	if previous_focus != _focus_amount or previous_opacity != _opacity or previous_guide != _guide_strength:
		queue_redraw()
	return _guide_strength

## 框面沿用暖深色，呼吸光仅作用于牌匾边缘。
func _draw() -> void:
	var warmth: float = _focus_amount if _available else _focus_amount * 0.35 # 锁定入口不呈现可进入的金色强反馈。
	_frame.bg_color = Color("292b24").lerp(Color("38352a"), warmth)
	_frame.bg_color.a = 0.91
	var rim: float = maxf(warmth, _guide_strength) # 聚焦反馈优先，待机亮度随场景轮廓起伏。
	_frame.border_color = Color(0.65, 0.59, 0.43, 0.42).lerp(Color(0.93, 0.78, 0.44, 0.88), rim)
	draw_style_box(_frame, Rect2(Vector2.ZERO, size))
	if _primary and _available:
		draw_line(Vector2(20, 1), Vector2(size.x - 20, 1), Color(0.88, 0.71, 0.38, 0.45 + 0.25 * rim), 1.0, true)
