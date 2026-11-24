## 强化与转职规则的图文排版，概率和门槛直接取自结算规则。
extends RefCounted

## 图标和技能书复用游戏美术。
const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")
## 道具图标取自背包图录。
const ItemArt = preload("res://scripts/adventure/ui/inventory_item_art.gd")
## 基础概率、耗材系数和保星用量的权威规则。
const Enhancement = preload("res://scripts/adventure/research/research_enhancement_rules.gd")
## 各阶星级和费用的唯一来源。
const Promotions = preload("res://scripts/adventure/research/research_promotion_catalog.gd")
## 四页共用的字形和纸面样式。
const Style = preload("res://scripts/adventure/ui/research_rules_style.gd")
## 用引擎控件组装公式。
const MathText = preload("res://scripts/adventure/ui/research_rules_math.gd")
## 内容卡片之间的纸缝宽度。
const GUTTER := 22.0
## 基础率和保星结果的淡绿衬底。
const SAGE := Color("dfe9d4")
## 道具用量的温金色底。
const HONEY := Color("f4dfb6")
## 掉星标记的淡砖色底。
const CLAY := Color("f1d8c6")
## 四阶技能书的蓝、靛、紫、铜色卡面。
const TIER_COLORS := [Color("35566b"), Color("4b5077"), Color("643f65"), Color("71512d")]

## 在 [param parent] 绘制 [param mode] 的 [param chapter]；转职规则一页展示全部内容。
static func draw(parent: Control, mode: String, chapter: int) -> void:
	if mode == "promotion":
		_promotion(parent)
		return
	match chapter:
		0: _probability(parent)
		1: _materials(parent)
		2: _items(parent)

## 在 [param parent] 并排放置深底公式和浅底基础率表。
static func _probability(parent: Control) -> void:
	var width: float = floorf((parent.size.x - GUTTER) * 0.49) # 给公式和右侧概率表分配栏宽。
	var formula: Panel = Style.panel(parent, Rect2(0, 0, width, parent.size.y), Style.FOREST) # 深底适合暖白的数学符号。
	var rates: Panel = Style.panel(parent, Rect2(width + GUTTER, 0,
		parent.size.x - width - GUTTER, parent.size.y)) # 基础率和示例使用同一纸面。
	_formula(formula)
	_rates(rates)

## 在 [param card] 按结果、算式和符号说明的顺序展示成功率公式。
static func _formula(card: Panel) -> void:
	var width: float = card.size.x - 48.0 # 算式、注释和分隔线共用内距。
	Style.label(card, "强化成功率", Rect2(24, 11, width, 47), 34, Style.CREAM, Style.bold)
	Style.band(card, "（基础率 + 耗材加成） × 肥料倍率", Rect2(24, 64, width, 57), Style.GOLD, Style.INK, 30)
	Style.prose(card, "上限 [b]100%[/b]。适用的生长剂直接保底。", Rect2(26, 134, width, 38), 25, Style.CREAM)

	var denominator: MathText.Part = MathText.power(MathText.row([
		MathText.token("(1 + %s × " % Enhancement.BASE_STAR_COEFFICIENT, 28),
		MathText.token("S", 28, true), MathText.token(")", 28)]),
		MathText.token(str(Enhancement.BASE_EXPONENT), 19)) # 指数应用到括号内的整个分母。
	var base: MathText.Part = MathText.fraction(MathText.token("%.0f%%" % (Enhancement.BASE_RATE * 100.0), 28),
		denominator) # 把基础概率的除法排成上下分式。
	_formula_row(card, "基础率", base, 171, 87)
	var decay_power: MathText.Part = MathText.row([
		MathText.token("−%s × " % Enhancement.HIGH_STAR_PENALTY, 22),
		MathText.power(MathText.token("D", 22, true), MathText.token(str(Enhancement.BASE_EXPONENT), 16))]) # 数学上标内仍可含另一个幂。
	var decay: MathText.Part = MathText.power(MathText.token("e", 41, true), decay_power) # 高星折减项取自然指数。
	_formula_row(card, "高星折减", decay, 259, 67)
	var normalized: MathText.Part = MathText.fraction(MathText.token("W", 24, true),
		MathText.token(str(Enhancement.MAX_MATERIAL_CARDS), 24)) # 耗材总权重按满槽数归一。
	var squared: MathText.Part = MathText.power(MathText.parentheses(normalized),
		MathText.token(str(Enhancement.FODDER_EXPONENT).trim_suffix(".0"), 21)) # 幂作用于整个分式。
	var bonus: MathText.Part = MathText.row([
		MathText.token("%.0f%% × " % (Enhancement.FODDER_RATE * 100.0), 31),
		MathText.token("高星折减", 26, false, Style.bold), MathText.token(" × ", 31), squared]) # 概率系数、折减和幂项相乘。
	_formula_row(card, "耗材加成", bonus, 327, 84)
	Style.prose(card, "[i]S[/i] 是主卡当前星级。[i]D[/i] 为超出 %d 星的部分，最低取 0。\n[i]W[/i] 是耗材总权重。[i]e[/i] 为自然常数。" % Enhancement.HIGH_STAR_START,
		Rect2(24, 424, width, 66), 23, Color("eee4c3"))

## 在 [param card] 的 [param top] 和 [param height] 内绘制 [param title] 与公式 [param part]。
static func _formula_row(card: Panel, title: String, part: MathText.Part, top: float, height: float) -> void:
	Style.label(card, title, Rect2(25, top, 142, height), 27, Style.GOLD, Style.bold)
	MathText.place(card, part, Rect2(176, top, card.size.x - 200, height))
	Style.rule(card, Rect2(24, top + height, card.size.x - 48, 2), Color("f8e0a84d"))

## 在 [param card] 展示基础概率和同条件下一张、三张耗材的概率条。
static func _rates(card: Panel) -> void:
	var width: float = card.size.x - 48.0 # 表格与对比图共用边距。
	_heading(card, "各星级基础率", Style.FOREST)
	var guide: Label = Style.label(card, "当前星级 → 目标星级", Rect2(24, 15, width, 42), 22,
		Style.MUTED, Style.italic) # 解读表格中的升星箭头。
	guide.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var tiers: Array[Array] = [] # 数据包括首次升星和升满星的基础率。
	for stars: int in range(Enhancement.MAX_STARS): # 按当前星级顺序排列。
		tiers.append(["%d → %d 星" % [stars, stars + 1], "%.2f%%" % (100.0 * Enhancement.base_probability(stars))])
	_metrics(card, Rect2(24, 64, width, 169), tiers, 5, SAGE, Style.FOREST)
	Style.rule(card, Rect2(24, 249, width, 2), Style.EDGE)
	Style.label(card, "为什么三张更高？", Rect2(24, 262, width, 41), 30, Style.FOREST, Style.bold)
	Style.prose(card, "同质量耗材的权重相加。[b]总权重 ×3[/b]，平方后[b]耗材加成 ×9[/b]。",
		Rect2(24, 311, width, 37), 24)
	var sample_stars: int = Enhancement.HIGH_STAR_START # 此星级尚未出现高星折减。
	var base: float = Enhancement.base_probability(sample_stars) # 一张和满槽用同一主卡基础率。
	Style.label(card, "%d 星主卡 · 同星耗材 · 原始阳光 %d · 无肥料" % [sample_stars, Enhancement.STANDARD_SUN_COST_MIN],
		Rect2(24, 345, width, 37), 22, Style.MUTED, Style.italic)
	_rate_bar(card, Rect2(24, 389, width, 40), "1 张", minf(1.0, base + Enhancement.material_bonus(sample_stars, 1.0)),
		Color("886229"))
	_rate_bar(card, Rect2(24, 437, width, 40), "%d 张" % Enhancement.MAX_MATERIAL_CARDS,
		minf(1.0, base + Enhancement.material_bonus(sample_stars, float(Enhancement.MAX_MATERIAL_CARDS))), Style.FOREST)

## 在 [param card] 的 [param bounds] 用同一标尺展示 [param caption] 的 [param rate]。
## [param ink] 用于条形填充和成功率数字。
static func _rate_bar(card: Panel, bounds: Rect2, caption: String, rate: float, ink: Color) -> void:
	Style.label(card, caption, Rect2(bounds.position, Vector2(94, bounds.size.y)), 26, Style.INK, Style.bold)
	var track := Rect2(bounds.position + Vector2(95, 12), Vector2(bounds.size.x - 230, 16)) # 数值在右侧对齐。
	Style.panel(card, track, Color("e0cfa6"), Color.TRANSPARENT, 8)
	Style.panel(card, Rect2(track.position, Vector2(track.size.x * rate, track.size.y)), ink, Color.TRANSPARENT, 8)
	var value: Label = Style.label(card, "%.2f%%" % (100.0 * rate),
		Rect2(bounds.end.x - 125, bounds.position.y, 125, bounds.size.y), 31, ink, Style.bold) # 对齐小数部分。
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

## 在 [param parent] 展示每张耗材的星差、阳光系数与选卡条件。
static func _materials(parent: Control) -> void:
	var cards: Array[Panel] = _columns(parent, 0, parent.size.y - 60) # 底部单列放置耗材限制。
	var stars: Panel = cards[0] # 左栏按星差排列。
	var sun: Panel = cards[1] # 右栏按原始阳光费用分段。
	var width: float = sun.size.x - 48 # 两栏使用相同内距。
	_heading(stars, "星差系数", Style.FOREST)
	Style.label(stars, "以主卡当前星级为基准", Rect2(24, 61, width, 36), 25, Style.MUTED, Style.italic)
	_stat_row(stars, "比主卡高", "每高 1 星 +%.2f，最高 ×%.2f" % [
		Enhancement.HIGHER_STAR_BONUS, Enhancement.HIGHER_STAR_CAP], 108)
	_stat_row(stars, "同星", "×1.00", 170)
	_stat_row(stars, "比主卡低 1 星", "×%.2f" % Enhancement.ONE_STAR_BELOW_MULTIPLIER, 232)
	_stat_row(stars, "比主卡低 2 星", "×%.2f" % Enhancement.TWO_STARS_BELOW_MULTIPLIER, 294)
	_stat_row(stars, "比主卡低 %d 星及以上" % (Enhancement.MAX_LOWER_STAR_GAP + 1), "不可放入", 356, Style.RUST)
	_heading(sun, "阳光系数", Color("765023"))
	Style.label(sun, "以耗材植物的原始阳光费用为准", Rect2(24, 61, width, 36), 25, Style.MUTED, Style.italic)
	_stat_row(sun, "少于 %d 阳光" % Enhancement.STANDARD_SUN_COST_MIN, "×%.2f" % Enhancement.LOW_COST_MULTIPLIER, 108)
	_stat_row(sun, "%d–%d 阳光" % [Enhancement.STANDARD_SUN_COST_MIN, Enhancement.STANDARD_SUN_COST_MAX], "×1.00", 170)
	_stat_row(sun, "超过 %d 阳光" % Enhancement.STANDARD_SUN_COST_MAX, "×%.2f" % Enhancement.HIGH_COST_MULTIPLIER, 232)
	Style.band(sun, "单张耗材权重 = 星差系数 × 阳光系数", Rect2(24, 335, width, 69), Color("704e2a"), Style.CREAM, 29)
	Style.band(parent, "每次使用 1–%d 张不同的耗材卡。若消耗向日葵，背包须至少留一张。" % Enhancement.MAX_MATERIAL_CARDS,
		Rect2(0, parent.size.y - 48, parent.size.x, 48), SAGE, Style.FOREST, 25)

## 在 [param parent] 分别展示肥料、生长剂与保育花盆。
static func _items(parent: Control) -> void:
	var width: float = (parent.size.x - GUTTER) / 2.0 # 肥料和生长剂共用左列。
	var height: float = parent.size.y - 60 # 两列底部留出费用提示。
	var fertilizer: Panel = Style.panel(parent, Rect2(0, 0, width, 215), Color("fff0d0")) # 温金色与肥料插图呼应。
	var agent: Panel = Style.panel(parent, Rect2(0, 230, width, height - 230), Color("e8edd8")) # 保底道具使用淡绿卡。
	var pot: Panel = Style.panel(parent, Rect2(width + GUTTER, 0, width, height)) # 花盆保护和用量集中在右列。
	var inner: float = width - 48 # 三张卡的图文共用内距。
	_item_title(fertilizer, "肥料", Enhancement.FERTILIZERS[0], Color("765023"))
	Style.prose(fertilizer, "将[b]基础率与耗材加成之和[/b]乘上对应倍率。", Rect2(24, 74, inner, 35), 25)
	var multipliers: Array[Array] = [] # 依次展示各级肥料的真实倍率。
	for index: int in range(Enhancement.FERTILIZERS.size()): # 道具级别从一级开始。
		multipliers.append([ItemRegistry.FERTILIZER_NAMES[index],
			"×%.2f" % Enhancement.fertilizer_multiplier(Enhancement.FERTILIZERS[index])])
	_metrics(fertilizer, Rect2(24, 111, inner, 84), multipliers, multipliers.size(), HONEY, Color("765023"))
	_item_title(agent, "生长剂", Enhancement.GROWTH_AGENTS[0], Style.FOREST)
	Style.prose(agent, "使用与星级匹配的生长剂，成功率直接变为 [b]100%[/b]。", Rect2(24, 72, inner, 42), 25)
	Style.prose(agent, "一级适用 [b]0 → 1 星[/b]，最高适用 [b]%d → %d 星[/b]。" % [
		Enhancement.GROWTH_AGENTS.size() - 1, Enhancement.GROWTH_AGENTS.size()], Rect2(24, 112, inner, 41), 25)
	Style.label(agent, "每次仍需合格的耗材卡和金币。", Rect2(24, 153, inner, 40), 24, Style.MUTED, Style.italic)
	_item_title(pot, "保育花盆", "seedling_pot", Style.RUST)
	Style.band(pot, "放足花盆，失败时保留主卡星级和耗材卡。", Rect2(24, 75, inner, 48), Style.FOREST, Style.CREAM, 25)
	Style.label(pot, "未使用花盆时", Rect2(24, 130, inner, 30), 22, Style.MUTED, Style.italic)
	_protection_row(pot, Rect2(24, 165, inner, 52), "0–%d 星" % (Enhancement.STAR_LOSS_START - 1),
		"强化失败后[b]保留原星级[/b]。", SAGE, Style.FOREST)
	_protection_row(pot, Rect2(24, 226, inner, 52), "%d–%d 星" % [
		Enhancement.STAR_LOSS_START, Enhancement.MAX_STARS - 1],
		"强化失败会[b]掉 1 星[/b]。", CLAY, Style.RUST)
	Style.rule(pot, Rect2(24, 287, inner, 2), Style.EDGE)
	Style.label(pot, "各目标星级的花盆用量", Rect2(24, 293, inner, 39), 29, Style.RUST, Style.bold)
	var quantities: Array[Array] = [["1–%d 星" % Enhancement.POT_SINGLE_MAX_STAR,
		"%d 个" % Enhancement.protection_count(1)]] # 初级升星也能保护耗材，相同用量合为一格。
	for target: int in range(Enhancement.POT_SINGLE_MAX_STAR + 1, Enhancement.MAX_STARS + 1): # 用量变化后逐星列出。
		quantities.append(["%d 星" % target, "%d 个" % Enhancement.protection_count(target)])
	_metrics(pot, Rect2(24, 337, inner, 85), quantities, quantities.size(), HONEY, Style.RUST)
	Style.band(parent, "每次强化花费 %d 金币并消耗所选道具。成功或未使用花盆时，耗材卡也会消耗。" % Enhancement.COST,
		Rect2(0, parent.size.y - 48, parent.size.x, 48), Color("714733"), Style.CREAM, 25)

## 在 [param pot] 的 [param bounds] 内展示 [param stars] 对应的 [param copy]，用 [param fill] 和 [param ink] 区分结果。
static func _protection_row(pot: Panel, bounds: Rect2, stars: String, copy: String, fill: Color, ink: Color) -> void:
	var strip: Panel = Style.panel(pot, bounds, fill, Color.TRANSPARENT, 8) # 低星和高星使用不同底色。
	Style.label(strip, stars, Rect2(16, 0, 133, bounds.size.y), 28, ink, Style.bold)
	Style.prose(strip, copy, Rect2(156, 8, bounds.size.x - 176, bounds.size.y - 8), 26)

## 在 [param parent] 依次显示四阶门槛、选择技能书和确认后的结果。
static func _promotion(parent: Control) -> void:
	var count: int = Promotions.REQUIREMENTS.size() # 门槛同时决定技能书牌数量。
	var width: float = (parent.size.x - GUTTER * (count - 1)) / count # 四牌保持等宽。
	for index: int in range(count): # 各阶从蓝色过渡到铜金色。
		var tier: Panel = Style.panel(parent, Rect2(index * (width + GUTTER), 0, width, 168),
			TIER_COLORS[index], Style.EDGE) # 技能书置于带铜边的专属底色上。
		Style.panel(tier, Rect2(23, 29, 109, 109), Color("fff1d21b"), Color("ffe2a273"), 54)
		Art.image(tier, ItemArt.promotion_tier_uri(index + 1), Vector2(32, 38), Vector2(91, 91))
		Style.label(tier, ItemRegistry.PROMOTION_NAMES[index], Rect2(149, 24, width - 166, 42), 32, Style.GOLD, Style.bold)
		Style.label(tier, "至少 %d 星" % Promotions.REQUIREMENTS[index], Rect2(147, 73, width - 165, 65),
			40, Style.CREAM, Style.bold)
	var cards: Array[Panel] = _columns(parent, 189, parent.size.y - 189) # 双栏说明与门槛卡留出间距。
	var route: Panel = cards[0] # 路线选择与预览方式。
	var confirm: Panel = cards[1] # 费用与永久后果。
	var inner: float = route.size.x - 48 # 两列说明的统一内距。
	_heading(route, "选择路线", Style.PLUM)
	Style.prose(route, "依次完成一转到四转，每阶从该植物的技能书中[b]二选一[/b]。\n已学技能一同保留。",
		Rect2(24, 74, inner, 100), 27)
	Style.rule(route, Rect2(24, 179, inner, 2), Style.EDGE)
	Style.prose(route, "[i]选中主卡可查看下一阶。放入技能书即可预览效果，开放的路线随植物而异。[/i]",
		Rect2(24, 200, inner, 85), 25, Style.MUTED)
	_heading(confirm, "确认转职", Style.RUST)
	Style.prose(confirm, "每次消耗[b]本阶技能书 1 本[/b]和 [b]%d 金币[/b]。转职保留星级。" % Promotions.COST,
		Rect2(24, 74, inner, 67), 27)
	Style.prose(confirm, "强化掉星后，[b]已学技能继续生效[/b]。下一转仍按当前星级判断。",
		Rect2(24, 147, inner, 73), 26)
	Style.band(confirm, "转职不可撤销，所选路线永久固定。", Rect2(24, 237, inner, 50), Style.RUST, Style.CREAM, 26)

## 在 [param parent] 的 [param top] 开始添加等宽说明卡，卡高为 [param height]，按从左到右的顺序返回。
static func _columns(parent: Control, top: float, height: float) -> Array[Panel]:
	var width: float = (parent.size.x - GUTTER) / 2.0 # 为两栏预留一条纸缝。
	return [Style.panel(parent, Rect2(0, top, width, height)), Style.panel(parent, Rect2(width + GUTTER, top, width, height))]

## 在 [param parent] 左上绘制 [param title]，用 [param accent] 标记小节主题。
static func _heading(parent: Control, title: String, accent: Color) -> void:
	Style.rule(parent, Rect2(24, 20, 4, 29), accent)
	Style.label(parent, title, Rect2(38, 10, parent.size.x - 62, 49), 33, accent, Style.bold)

## 在 [param parent] 左上绘制 [param item_id] 的道具和使用 [param accent] 着色的 [param title]。
static func _item_title(parent: Control, title: String, item_id: String, accent: Color) -> void:
	Art.image(parent, ItemArt.icon_uri(item_id), Vector2(23, 12), Vector2(53, 53))
	Style.label(parent, title, Rect2(86, 13, parent.size.x - 110, 52), 34, accent, Style.bold)

## 在 [param parent] 的 [param y] 处左右对齐 [param title] 和 [param value]，用 [param ink] 强调数值。
static func _stat_row(parent: Control, title: String, value: String, y: float, ink: Color = Style.FOREST) -> void:
	var width: float = parent.size.x - 48 # 数值与分隔线右端对齐。
	Style.label(parent, title, Rect2(24, y, width * 0.43, 50), 28)
	var result: Label = Style.label(parent, value, Rect2(24 + width * 0.43, y, width * 0.57, 50), 28, ink, Style.bold) # 数值列用粗体。
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	Style.rule(parent, Rect2(24, y + 53, width, 2), Color("ac89576f"))

## 在 [param parent] 的 [param bounds] 内按 [param columns] 列排列 [param entries]。
## [param fill] 为数值格底色，[param ink] 为粗体数值的墨色。
static func _metrics(parent: Control, bounds: Rect2, entries: Array[Array], columns: int, fill: Color, ink: Color) -> void:
	var gap: float = 8.0 # 相邻格子的间距。
	var rows: int = ceili(float(entries.size()) / columns) # 基础概率共用两行版式。
	var tile_size := (bounds.size - Vector2(columns - 1, rows - 1) * gap) / Vector2(columns, rows) # 等分每格宽高。
	for index: int in range(entries.size()): # 从左到右、从上到下排列。
		var coord := Vector2(index % columns, floori(float(index) / columns)) # 数值格的列与行。
		var tile: Panel = Style.panel(parent, Rect2(bounds.position + coord * (tile_size + Vector2.ONE * gap), tile_size),
			fill, Color.TRANSPARENT, 8) # 数值格使用同组底色。
		var caption: Label = Style.label(tile, entries[index][0], Rect2(4, 0, tile_size.x - 8, tile_size.y * 0.44), 22,
			Style.MUTED) # 星级或等级说明放上方。
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var value: Label = Style.label(tile, entries[index][1], Rect2(4, tile_size.y * 0.40, tile_size.x - 8, tile_size.y * 0.58),
			31, ink, Style.bold) # 关键数字放在独立一行。
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
