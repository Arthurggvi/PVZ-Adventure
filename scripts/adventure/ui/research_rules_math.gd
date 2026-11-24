## 用引擎文字与线条排版规则公式，分数和指数均有独立的基线与字号。
extends RefCounted

## 公式与章节共用纸面墨色。
const Style = preload("res://scripts/adventure/ui/research_rules_style.gd")
## 数学数字、标点及运算符的衬线字体。
static var _roman: SystemFont
## 变量使用的数学斜体。
static var _italic: FontVariation

## 一个可参与行内对齐的排版元素。
class Part extends RefCounted:
	## 元素的实际绘制节点，宽高是其占用的逻辑像素。
	var view: Control
	## 从元素顶端量起的文字基线或数学轴换算位置。
	var baseline: float

	## 记录 [param node] 的尺寸和 [param baseline_y] 供组合公式排版使用。
	func _init(node: Control, baseline_y: float) -> void:
		view = node
		baseline = baseline_y

## 创建字号为 [param point_size] 的 [param value]；[param variable] 启用斜体，中文术语可指定 [param font]。
static func token(value: String, point_size: int, variable: bool = false, font: Font = null) -> Part:
	if _roman == null:
		_roman = SystemFont.new()
		_roman.font_names = PackedStringArray(["Cambria Math", "STIX Two Math", "DejaVu Serif", "serif"])
		_roman.fallbacks = [ThemeDB.fallback_font]
		_italic = FontVariation.new()
		_italic.base_font = _roman
		_italic.variation_transform = Transform2D(Vector2.RIGHT, Vector2(-0.23, 1), Vector2.ZERO)
	var face: Font = font if font != null else (_italic if variable else _roman) # 变量与运算符用不同字形。
	var text := Label.new() # 按引擎实测的进位宽度和字高摆放相邻元素。
	text.text = value
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_theme_font_override("font", face)
	text.add_theme_font_size_override("font_size", point_size)
	text.add_theme_color_override("font_color", Style.GOLD if variable else Style.CREAM)
	text.size = Vector2(ceilf(face.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, point_size).x) + 1.0,
		ceilf(face.get_height(point_size)))
	return Part.new(text, face.get_ascent(point_size))

## 把 [param parts] 从左到右排在共用基线上并返回组合元素。
static func row(parts: Array[Part]) -> Part:
	var baseline: float = 0.0 # 以最高元素的基线距离为准，保证没有负坐标。
	for part: Part in parts: # 确定本行的基线。
		baseline = maxf(baseline, part.baseline)
	var view := Control.new() # 作为整行的对齐和定位容器。
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for part: Part in parts: # 逐项累加进位宽度。
		part.view.position = Vector2(view.size.x, baseline - part.baseline)
		view.add_child(part.view)
		view.size = Vector2(part.view.position.x + part.view.size.x, maxf(view.size.y, part.view.position.y + part.view.size.y))
	return Part.new(view, baseline)

## 将 [param numerator] 和 [param denominator] 居中放在分数线两侧。
static func fraction(numerator: Part, denominator: Part) -> Part:
	var view := Control.new() # 分数线比两行中的较宽一行略长。
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var width: float = maxf(numerator.view.size.x, denominator.view.size.x) + 16.0 # 两端各留八像素。
	var bar_y: float = numerator.view.size.y + 3.0 # 上下各留出可分辨的纸面间距。
	numerator.view.position = Vector2((width - numerator.view.size.x) / 2.0, 0)
	denominator.view.position = Vector2((width - denominator.view.size.x) / 2.0, bar_y + 5)
	view.add_child(numerator.view)
	view.add_child(denominator.view)
	Style.rule(view, Rect2(0, bar_y, width, 2), Style.CREAM)
	view.size = Vector2(width, denominator.view.position.y + denominator.view.size.y)
	return Part.new(view, bar_y + 8.0)

## 把 [param part] 放入随内容高度伸展的圆括号，分子和分母一起纳入括号。
static func parentheses(part: Part) -> Part:
	var height: float = part.view.size.y # 括号由元素的总高度决定。
	return row([
		Part.new(_parenthesis(height, false), part.baseline), part,
		Part.new(_parenthesis(height, true), part.baseline)])

## 创建高为 [param height] 的圆括号；[param closing] 为真时向左开口。
static func _parenthesis(height: float, closing: bool) -> Control:
	var view := Control.new() # 按笔画宽度占位，不需要拉伸字体字形。
	view.size = Vector2(15, height)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var edge: float = 3.0 if closing else 12.0 # 括号上下端靠近公式项。
	var bend: float = 12.0 if closing else -12.0 # 左右括号的曲率镜像。
	var curve := Curve2D.new() # 中段向外弯曲，两端覆盖整个分式。
	curve.add_point(Vector2(edge, 2.0), Vector2.ZERO, Vector2(bend, height * 0.27))
	curve.add_point(Vector2(edge, height - 2.0), Vector2(bend, -height * 0.27), Vector2.ZERO)
	var stroke := Line2D.new() # 线宽与分数线接近，适应高低分辨率。
	stroke.points = curve.tessellate()
	stroke.default_color = Style.CREAM
	stroke.width = 2.6
	stroke.antialiased = true
	view.add_child(stroke)
	return view

## 将 [param exponent] 置于 [param base] 右上，组合元素仍以底数基线参与对齐。
static func power(base: Part, exponent: Part) -> Part:
	var view := Control.new() # 上标可以是小字号公式，包含另一层上标。
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var exponent_y: float = base.baseline * 0.44 - exponent.baseline # 按底数高度抬升指数基线。
	var base_y: float = maxf(0.0, -exponent_y) # 给上标超出底数顶部的部分留空间。
	exponent.view.position = Vector2(base.view.size.x, exponent_y + base_y)
	base.view.position = Vector2(0, base_y)
	view.add_child(base.view)
	view.add_child(exponent.view)
	view.size = Vector2(exponent.view.position.x + exponent.view.size.x,
		maxf(base_y + base.view.size.y, exponent.view.position.y + exponent.view.size.y))
	return Part.new(view, base.baseline + base_y)

## 在 [param parent] 的 [param bounds] 内左对齐、垂直居中放置 [param part]。
static func place(parent: Control, part: Part, bounds: Rect2) -> void:
	part.view.position = bounds.position + Vector2(0, (bounds.size.y - part.view.size.y) / 2.0)
	parent.add_child(part.view)
