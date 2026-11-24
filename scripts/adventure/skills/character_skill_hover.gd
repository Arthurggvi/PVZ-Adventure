## 战斗技能的只读浮卡，脱离头像缩放，锚定悬停入口并限制在视口内。
extends PanelContainer

## 逻辑画布宽度；长说明在此宽度内自动换行。
const CARD_WIDTH := 312.0
## 浮卡与锚点、视口边缘之间的最小间距，单位为逻辑像素。
const GAP := 10.0
## 防止指针快速扫过战斗 HUD 时闪出说明，使用实际秒数。
const DELAY_SECONDS := 0.35

## 使用技能实时的战局门禁，但允许在技能冷却期间阅读。
var can_show: Callable
## 神殿按钮复用同一张浮卡，前景色与蓝金框呼应。
var valhalla: bool = false
## 当前悬停入口，头像和技能按钮共用一份浮卡。
var _anchor: Control
## 单次悬停延迟，退出入口后立即取消。
var _delay: Timer
## 当前技能及其静态说明，冷却计数刷新时不重排。
var _skill: CharacterSkillDefinition
## 浮卡背景和可根据技能切换的描边、分隔线、标题。
var _surface: StyleBoxFlat
## 页首的技能图标，与施放按钮共用纹理。
var _icon: TextureRect
## 页首技能名称。
var _title: Label
## 自动换行的完整技能说明。
var _body: Label
## 正文与冷却栏之间的细分隔线。
var _divider: ColorRect
## 静态冷却时长，实时剩余秒数仍在技能按钮上。
var _cooldown: Label

## 创建一次浮卡；只在等待或显示时运行计时和边界检查。
func _ready() -> void:
	name = "CharacterSkillHover"
	top_level = true
	z_index = 24
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size.x = CARD_WIDTH
	var font := SystemFont.new() # 桌面中文采用常见无衬线字形，缺字时由引擎回退。
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	theme = Theme.new()
	theme.default_font = font
	_surface = StyleBoxFlat.new()
	_surface.bg_color = Color("101e3bfa") if valhalla else Color("141e28fa")
	_surface.set_border_width_all(1)
	_surface.border_width_top = 2
	_surface.set_corner_radius_all(10)
	_surface.shadow_color = Color("05091099")
	_surface.shadow_size = 5
	_surface.shadow_offset = Vector2(0, 3)
	_surface.content_margin_left = 14
	_surface.content_margin_right = 14
	_surface.content_margin_top = 12
	_surface.content_margin_bottom = 10
	add_theme_stylebox_override("panel", _surface)
	var content := VBoxContainer.new() # 标题、正文和冷却栏按实际文本高度排列。
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 8)
	add_child(content)
	var header := HBoxContainer.new() # 技能图标和名称共用一行，长标题也可换行。
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_constant_override("separation", 9)
	content.add_child(header)
	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(30, 30)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(_icon)
	_title = _caption(header, 19, Color("f3f7fc"))
	var heading_font := font.duplicate() as SystemFont # 用真实粗体区分标题和长正文。
	heading_font.font_weight = 700
	_title.add_theme_font_override("font", heading_font)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body = _caption(content, 15, Color("dee8f1"))
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_constant_override("line_spacing", 4)
	_divider = ColorRect.new()
	_divider.custom_minimum_size.y = 1
	_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_divider)
	_cooldown = _caption(content, 13, Color("abc4d8"))
	_delay = Timer.new()
	_delay.one_shot = true
	_delay.wait_time = DELAY_SECONDS
	_delay.ignore_time_scale = true
	add_child(_delay)
	_delay.timeout.connect(_present)
	get_window().focus_exited.connect(dismiss)
	minimum_size_changed.connect(reset_size)
	resized.connect(_place)
	get_viewport().size_changed.connect(_place)
	hide()
	set_process(false)
	set_process_input(false)

## 在 [param parent] 添加使用 [param point_size] 和 [param ink] 的只读文字。
func _caption(parent: Control, point_size: int, ink: Color) -> Label:
	var label := Label.new() # 忽略鼠标，让底层按钮持续收到悬停和点击。
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", point_size)
	label.add_theme_color_override("font_color", ink)
	parent.add_child(label)
	return label

## 观察 [param target] 的悬停，保留按钮原有的键鼠与触摸行为。
func watch(target: Control) -> void:
	target.mouse_entered.connect(_queue.bind(target))
	target.mouse_exited.connect(_leave.bind(target))
	target.visibility_changed.connect(_leave.bind(target))

## 使用 [param skill] 更新颜色和说明；同一技能的实时状态刷新不打断阅读。
func set_skill(skill: CharacterSkillDefinition) -> void:
	if skill == _skill:
		return
	dismiss()
	_skill = skill
	if _skill == null:
		return
	var accent: Color = Color("f7d696") if valhalla else _skill.cut_in_accent.lerp(Color("deecfa"), 0.42) # 统一色调，在深底保持正文对比度。
	_surface.border_color = accent.darkened(0.24)
	_divider.color = Color(accent, 0.25)
	_title.add_theme_color_override("font_color", accent)
	_icon.texture = _skill.icon
	_title.text = _skill.display_name
	_body.text = _skill.description
	_body.visible = not _body.text.is_empty()
	_cooldown.text = "冷却  %s 秒" % String.num(_skill.cooldown_seconds, 1).trim_suffix(".0")

## [param target] 开始悬停时绑定锚点，离开后不会延迟弹出。
func _queue(target: Control) -> void:
	dismiss()
	if _skill == null or not target.is_visible_in_tree():
		return
	_anchor = target
	_delay.start()
	set_process_input(true)

## [param target] 离开或隐藏时，只取消由这个入口触发的浮卡。
func _leave(target: Control) -> void:
	if _anchor == target:
		dismiss()

## 停止等待并收起，避免旧的说明留在弹窗或切场画面上。
func dismiss() -> void:
	_anchor = null
	_delay.stop()
	hide()
	set_process(false)
	set_process_input(false)

## 单次延迟结束后核对当前入口和战局，再开始显示。
func _present() -> void:
	if not _allowed():
		dismiss()
		return
	modulate.a = 0.0
	show()
	reset_size()
	set_process(true)

## 只在浮卡可见时检查战局，[param _delta] 不参与说明显示。
func _process(_delta: float) -> void:
	if not _allowed():
		dismiss()
		return
	if modulate.a == 0.0:
		# 等容器按实际宽度排完换行，再显示首帧，避免瞬间按零宽度排成竖条。
		reset_size()
		_place()
		modulate.a = 1.0

## [param event] 触发施放或打开其他界面时先收起，仍交给原按钮处理。
func _input(event: InputEvent) -> void:
	if (event is InputEventMouseButton or event is InputEventKey) and event.is_pressed():
		dismiss()

## 核对悬停仍属于同一入口，且真实战局没有被弹窗或暂停占用。
func _allowed() -> bool:
	return (is_instance_valid(_anchor) and _anchor.is_visible_in_tree()
		and get_viewport().gui_get_hovered_control() == _anchor
		and get_window().has_focus() and can_show.is_valid() and can_show.call())

## 优先在入口下方显示，空间不足时移到上方；边缘和极小视口都保持完整。
func _place() -> void:
	if not visible or not is_instance_valid(_anchor) or size.x <= 0.0 or size.y <= 0.0:
		return
	var viewport_rect: Rect2 = get_viewport_rect() # 锚点和浮卡使用同一逻辑视口坐标。
	var margin: float = minf(GAP, minf(viewport_rect.size.x, viewport_rect.size.y) * 0.1) # 极窄窗口仍留出可用面积。
	var bounds: Rect2 = viewport_rect.grow(-margin) # 保留浮卡外沿与投影所需的留白。
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return
	var fit: float = minf(1.0, minf(bounds.size.x / size.x, bounds.size.y / size.y)) # 极小视口整体缩小，正文仍完整。
	var extent: Vector2 = size * fit # 限位依据实际显示尺寸。
	var target: Rect2 = _anchor.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, _anchor.size) # 包含头像原有的缩放。
	var corner := Vector2(target.position.x, target.end.y + GAP) # 默认左对齐并留出入口与正文间距。
	if corner.y + extent.y > bounds.end.y:
		corner.y = target.position.y - GAP - extent.y
	scale = Vector2.ONE * fit
	position = get_canvas_transform().affine_inverse() * corner.clamp(bounds.position, bounds.end - extent)
