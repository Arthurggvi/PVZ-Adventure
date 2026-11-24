## 研究规则共用的纸面、墨色和字体。字体只在打开规则时创建。
extends RefCounted

## 阅读区的浅色羊皮纸。
const PAPER := Color("fff2d8e8")
## 纸面外沿的暖金细线。
const EDGE := Color("b99a64")
## 主体文字的深棕墨色。
const INK := Color("372a22")
## 注释、条件和次要说明用的淡墨。
const MUTED := Color("694c36")
## 强化相关的墨绿，用于标题、公式底和关键概率。
const FOREST := Color("284435")
## 转职的深紫墨色，用于书页和章节标题。
const PLUM := Color("41354d")
## 消耗或不可逆后果的红褐色。
const RUST := Color("863f30")
## 深色底上的高对比暖白正文。
const CREAM := Color("fff1d2")
## 深色底上的金色高亮。
const GOLD := Color("f2cf87")

## 中文、标点和数字共用的正文无衬线字体。
static var body: SystemFont
## 章节标题和关键数字使用的粗体。
static var bold: SystemFont
## 从同一正文字形生成的斜体，中文和拉丁字母的倾斜一致。
static var italic: FontVariation

## 首次打开规则时准备字体；系统字体不可用的字形使用项目自带字体。
static func prepare() -> void:
	if body != null:
		return
	body = SystemFont.new()
	body.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	body.fallbacks = [load("res://assets/fonts/方正少儿_GBK.ttf") as Font]
	bold = body.duplicate() as SystemFont
	bold.font_weight = 700
	italic = FontVariation.new()
	italic.base_font = body
	italic.variation_transform = Transform2D(Vector2.RIGHT, Vector2(-0.18, 1), Vector2.ZERO)

## 返回 [param fill]、[param edge] 及 [param radius] 指定的圆角纸面样式。
static func box(fill: Color, edge: Color, radius: int = 13) -> StyleBoxFlat:
	var style := StyleBoxFlat.new() # 细描边沿用研究室的铜色收边。
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	return style

## 在 [param parent] 的 [param bounds] 添加 [param fill] 底色、[param edge] 边线的纸面卡片。
## [param radius] 是角半径，面板本身不响应输入。
static func panel(parent: Control, bounds: Rect2, fill: Color = PAPER, edge: Color = EDGE, radius: int = 13) -> Panel:
	var surface := Panel.new() # 子控件按卡面的局部坐标布局。
	surface.position = bounds.position
	surface.size = bounds.size
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.add_theme_stylebox_override("panel", box(fill, edge, radius))
	parent.add_child(surface)
	return surface

## 在 [param parent] 的 [param bounds] 以 [param point_size] 和 [param ink] 绘制单行 [param copy]。
## [param font] 为空时使用正文，数字和标题可选用粗体。
static func label(parent: Control, copy: String, bounds: Rect2, point_size: int,
		ink: Color = INK, font: Font = null) -> Label:
	var text := Label.new() # 没有描边阴影，保证公式与小号数字轮廓干净。
	text.position = bounds.position
	text.size = bounds.size
	text.text = copy
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.clip_text = true
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.add_theme_font_override("font", body if font == null else font)
	text.add_theme_font_size_override("font_size", point_size)
	text.add_theme_color_override("font_color", ink)
	parent.add_child(text)
	return text

## 在 [param parent] 的 [param bounds] 内排版 [param copy]；[param point_size] 和 [param ink] 指定正文外观。
## 文字允许使用引擎的粗体和斜体标记，按字词换行。
static func prose(parent: Control, copy: String, bounds: Rect2, point_size: int = 26, ink: Color = INK) -> void:
	var text := RichTextLabel.new() # 用各自的真实字体绘制强调，段落不需要内部滚动。
	text.position = bounds.position
	text.size = bounds.size
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.scroll_active = false
	text.bbcode_enabled = true
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_font_override("normal_font", body)
	text.add_theme_font_override("bold_font", bold)
	text.add_theme_font_override("italics_font", italic)
	text.add_theme_font_size_override("normal_font_size", point_size)
	text.add_theme_font_size_override("bold_font_size", point_size)
	text.add_theme_font_size_override("italics_font_size", point_size)
	text.add_theme_color_override("default_color", ink)
	text.add_theme_constant_override("line_separation", 5)
	text.text = copy
	parent.add_child(text)

## 在 [param parent] 的 [param bounds] 放置 [param copy] 的粗体色带，[param fill]、[param ink] 和 [param point_size] 指定外观。
static func band(parent: Control, copy: String, bounds: Rect2, fill: Color, ink: Color, point_size: int) -> void:
	var surface: Panel = panel(parent, bounds, fill, Color.TRANSPARENT, 8) # 色带本身提供足够的层级。
	var text: Label = label(surface, copy, Rect2(10, 0, bounds.size.x - 20, bounds.size.y), point_size, ink, bold) # 两端避开圆角。
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

## 在 [param parent] 的 [param bounds] 绘制 [param ink] 分隔线或色标。
static func rule(parent: Control, bounds: Rect2, ink: Color) -> void:
	var line := ColorRect.new() # 保持纯色且不拦截交互。
	line.position = bounds.position
	line.size = bounds.size
	line.color = ink
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)
