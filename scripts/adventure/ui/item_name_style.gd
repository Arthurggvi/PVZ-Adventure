## 按肥料/生长剂级别或技能书阶数绘制道具名称，配色仅应用于文字。
extends RefCounted

## 复用羊皮纸面板的普通名称样式。
const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")
## 索引 0 为普通道具，1 至 5 依次为白、绿、蓝、紫、金。
const NAME_COLORS := [Color("382719"), Color.WHITE, Color("246333"),
	Color("205da8"), Color("71368e"), Color("a36a0d")]
## 四转名称按字从暖色过渡到冷色，保留羊皮纸上的对比度。
const RAINBOW_COLORS := [Color("a32824"), Color("a65a0d"), Color("8e6c09"),
	Color("246333"), Color("205da8"), Color("71368e")]

## 在 [param parent] 的 [param bounds] 中以 [param font_size] 显示 [param caption]，由 [param item_id] 决定颜色。
## [param allow_wrap] 启用自动换行，让容器为长文本分配所需高度。
static func draw(parent: Node, caption: String, item_id: String, bounds: Rect2, font_size: int, allow_wrap: bool = false) -> void:
	var item: Dictionary = ItemRegistry.get_item_definition(item_id) # 从目录元数据取阶数，不解析显示名称。
	var promotion: int = int(item.get("promotion_tier", 0)) # 四转用彩色，其余转职从蓝色起。
	if promotion == 4:
		_draw_rainbow(parent, caption, bounds, font_size, allow_wrap)
		return
	var level: int = promotion + 2 if promotion > 0 else int(item.get(
		"fertilizer_level", item.get("growth_agent_level", 0))) # 两种消耗品共用级别配色。
	var color: Color = NAME_COLORS[clampi(level, 0, NAME_COLORS.size() - 1)] # 其他道具用普通文字色。
	var label: Label = Art.label(parent, caption, bounds.position, bounds.size, font_size, color) # 沿用已有位置与字体。
	if allow_wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.clip_text = false
		label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	if color == Color.WHITE:
		label.add_theme_color_override("font_outline_color", Color("382719"))
		label.add_theme_constant_override("outline_size", 2)

## 在 [param parent] 的 [param bounds] 内以 [param font_size] 逐字为 [param caption] 配色。
## [param allow_wrap] 启用自动换行与内容高度适配。
static func _draw_rainbow(parent: Node, caption: String, bounds: Rect2, font_size: int, allow_wrap: bool) -> void:
	var label := RichTextLabel.new() # 每个字独立上色，名称仍保留可访问的纯文本内容。
	label.position = bounds.position
	label.size = bounds.size
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if allow_wrap else TextServer.AUTOWRAP_OFF
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP if allow_wrap else VERTICAL_ALIGNMENT_CENTER
	label.fit_content = allow_wrap
	label.add_theme_font_size_override("normal_font_size", font_size)
	var span: int = maxi(caption.length() - 1, 1) # 单字符名称也有确定颜色。
	for index: int in range(caption.length()): # 按名称长度均匀分配色带。
		var color_index: int = roundi(float(index) / span * (RAINBOW_COLORS.size() - 1)) # 从首色过渡到尾色。
		label.push_color(RAINBOW_COLORS[color_index])
		label.add_text(caption.substr(index, 1))
		label.pop()
	parent.add_child(label)
