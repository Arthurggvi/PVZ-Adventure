## 按肥料/生长剂级别或技能书阶数绘制道具文字，四转使用流动渐变。
extends RefCounted

## 复用羊皮纸面板的普通名称样式。
const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")
## 四转标题和描述共用的流动文字效果。
const FlowingRainbow = preload("res://scripts/adventure/ui/flowing_rainbow_text.gd")
## 索引 0 为普通道具，1 至 5 依次为白、绿、蓝、紫、金。
const NAME_COLORS := [Color("382719"), Color.WHITE, Color("246333"),
	Color("205da8"), Color("71368e"), Color("a36a0d")]

## 在 [param parent] 的 [param bounds] 中以 [param font_size] 显示 [param caption]，由 [param item_id] 决定颜色。
## [param allow_wrap] 启用自动换行，让容器为长文本分配所需高度。
static func draw(parent: Node, caption: String, item_id: String, bounds: Rect2, font_size: int, allow_wrap: bool = false) -> void:
	var item: Dictionary = ItemRegistry.get_item_definition(item_id) # 从目录元数据取阶数，不解析显示名称。
	var promotion: int = int(item.get("promotion_tier", 0)) # 四转用彩色，其余转职从蓝色起。
	var level: int = promotion + 2 if promotion > 0 else int(item.get(
		"fertilizer_level", item.get("growth_agent_level", 0))) # 两种消耗品共用级别配色。
	var color: Color = NAME_COLORS[clampi(level, 0, NAME_COLORS.size() - 1)] # 其他道具用普通文字色。
	_draw_label(parent, caption, bounds, font_size, color, allow_wrap, promotion == 4)

## 在 [param parent] 的 [param bounds] 内以 [param font_size] 显示可换行的 [param caption]。
## [param item_id] 对应四转技能书时启用流动渐变，其余描述沿用 [param color]。
static func draw_description(parent: Node, caption: String, item_id: String, bounds: Rect2,
		font_size: int, color: Color = NAME_COLORS[0]) -> void:
	var item: Dictionary = ItemRegistry.get_item_definition(item_id) # 用同一目录判定书的转职阶数。
	_draw_label(parent, caption, bounds, font_size, color, true, int(item.get("promotion_tier", 0)) == 4)

## 在 [param parent] 的 [param bounds] 内用 [param font_size] 和 [param color] 绘制 [param caption]。
## [param allow_wrap] 使长文本自动换行，[param rainbow] 启用四转的流动色带。
static func _draw_label(parent: Node, caption: String, bounds: Rect2, font_size: int,
		color: Color, allow_wrap: bool, rainbow: bool) -> void:
	var label: Label = Art.label(parent, caption, bounds.position, bounds.size, font_size, color) # 沿用羊皮纸的字体和布局。
	if allow_wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.clip_text = false
		label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		label.size = bounds.size # 换行后用面板宽度布局，VBoxContainer 内由容器分配宽度。
	if rainbow:
		FlowingRainbow.apply_to(label, 0.10 if allow_wrap else 0.24) # 描述的扫光比单行标题柔和。
	elif color == Color.WHITE:
		label.add_theme_color_override("font_outline_color", Color("382719"))
		label.add_theme_constant_override("outline_size", 2)
