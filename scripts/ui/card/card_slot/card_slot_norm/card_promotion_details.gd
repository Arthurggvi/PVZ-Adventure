## 冒险选卡与研究室共用的植物预览，展示实际星级、阳光费用和转职路线。
extends Panel

## 植物名称和基础能力沿用冒险背包的查询入口。
const InventoryData = preload("res://scripts/adventure/ui/inventory_data.gd")
## 与选卡板共用的中文字体。
const FONT = preload("res://assets/fonts/方正少儿_GBK.ttf")
## 按配方保存顺序对应一至四转。
const TIER_NAMES := ["一转", "二转", "三转", "四转"]
## 预览卡设计宽度，单位为选卡画布像素。
const PANEL_WIDTH := 264.0
## 纸卡四周的内边距，单位为选卡画布像素。
const PAPER_PADDING := 8.0
## 页首和转职条目在纸卡内的可用宽度，单位为选卡画布像素。
const CONTENT_WIDTH := PANEL_WIDTH - 2.0 * PAPER_PADDING
## 页首、转职区标题和首条路线之间的间距，单位为选卡画布像素。
const SECTION_GAP := 7.0
## 相邻转职条目之间的间距，单位为选卡画布像素。
const ROUTE_GAP := 5.0
## 页首预留给卡面和星章的区域，单位为选卡画布像素。
const PACKET_SLOT_SIZE := Vector2(76, 100)
## 卡面按原比例放大，星章和费用跟随卡面一起缩放。
const PACKET_SCALE := 1.32
## 淡入时上移的距离，单位为选卡画布像素。
const REVEAL_OFFSET := 5.0
## 预览与选卡板或研究槽之间的距离，单位为预览父节点的局部像素。
const ANCHOR_GAP := 10.0
## 悬停控件携带的实际植物卡，随当前格子一起释放。
const HOVER_CARD_META := &"promotion_preview_card"
## 悬停控件可指定整组槽位作为预览的水平参照。
const HOVER_SIDE_META := &"promotion_preview_side"

## 候选板用于将预览锚定在选卡区域右侧。
var chooser: Control
## 研究室只跟踪此内容区内登记的卡格；选卡板使用候选板布局。
var hover_scope: Control
## 上次显示的真实卡实例，同种植物的不同 UID 分别处理。
var _shown_card: Card
## 已展示的冻结配方；同一张卡更换配方时也刷新。
var _shown_profile: PlantSpawnProfile
## 触屏最近选入的卡，供指针已释放时查看。
var _touch_choice: Card
## 页首和转职区的共同绘制层；切卡时整体过渡透明度。
var _content: Control
## 唯一有效的预览过渡，快速切卡或重新悬停时从当前姿态接续。
var _motion: Tween
## 是否已开始收起；退场完成前保留旧卡面以便续接动画。
var _dismissing := false

## 初始化被动显示层，等待调用方启用跟踪。
func _ready() -> void:
	name = "CardPromotionDetails"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_DISABLED
	focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
	z_index = 5
	var paper: StyleBoxFlat = _surface(Color("f4e2be"), Color("553922"), 11, PAPER_PADDING) # 木边和投影呼应选卡板。
	paper.set_border_width_all(2)
	paper.shadow_color = Color("21170fb3")
	paper.shadow_size = 5
	paper.shadow_offset = Vector2(0, 3)
	add_theme_stylebox_override("panel", paper)

	_content = Control.new()
	_content.position = Vector2(PAPER_PADDING, PAPER_PADDING)
	add_child(_content)
	modulate.a = 0.0
	set_process(false)
	hide()

## 登记 [param target] 上的 [param card]，空卡清除关联。
## [param side_anchor] 可用整组槽位的左右边界，默认使用当前格子。
static func set_hover_card(target: Control, card: Card, side_anchor: Control = null) -> void:
	target.set_meta(HOVER_CARD_META, card)
	target.set_meta(HOVER_SIDE_META, side_anchor)

## 根据 [param enabled] 启停跟踪；停止时立即释放预览和触屏选择。
func set_tracking_enabled(enabled: bool) -> void:
	set_process(enabled)
	if not enabled:
		_touch_choice = null
		dismiss()

## 立即收起当前预览，供内容区重绘或切换时调用。
func dismiss() -> void:
	if _motion != null:
		_motion.kill()
	_hide_preview()

## 在触屏上记录刚选入上方卡栏的 [param card]，闲置时保留其预览。
func remember_touch_choice(card: Card) -> void:
	if OS.has_feature("mobile"):
		_touch_choice = card

## 研究室跟踪悬停槽位，选卡板还接收焦点和最近一次触屏选卡。
## [param _delta] 为帧间隔，预览过渡由补间计时。
func _process(_delta: float) -> void:
	var viewport: Viewport = get_viewport() # 只查看当前视口的前景控件。
	var hovered: Control = viewport.gui_get_hovered_control() # 实际鼠标目标优先。
	if hover_scope != null:
		var target: Control = _hover_target(hovered) # 候选格、工作槽或合成产物的预览锚点。
		# 卡面数据来自格子中已经装配的实例。
		var slot_card: Card = target.get_meta(HOVER_CARD_META) as Card if target != null else null
		_show_card(slot_card)
		if target != null:
			_align_preview(target)
		return
	var card: Card = _card_for(hovered) # 鼠标直接指向另一张卡时优先切换。
	if card == null:
		card = _card_for(viewport.gui_get_focus_owner())
	if card == null and is_instance_valid(_touch_choice) and _touch_choice.is_choosed_pre_card \
			and _touch_choice.is_visible_in_tree():
		card = _touch_choice
	_show_card(card)
	_align_preview()

## 从 [param control] 向上寻找当前内容区登记的卡格；触屏点击层也能找到所属格子。
func _hover_target(control: Control) -> Control:
	if not is_instance_valid(control) or not control.is_visible_in_tree() or not hover_scope.is_ancestor_of(control):
		return null
	var target: Control = control # 鼠标可能命中卡格内的按钮或其他子控件。
	while target != null and target != hover_scope:
		if target.has_meta(HOVER_CARD_META):
			return target
		target = target.get_parent_control()
	return null

## 从 [param control] 找到本选卡板的真实植物卡；其他窗口、战斗卡和空卡位返回 null。
func _card_for(control: Control) -> Card:
	if not is_instance_valid(control) or not control is Button or not control.is_visible_in_tree():
		return null
	var card := control.get_parent() as Card # 可交互按钮是候选卡或上方已选卡的直属子节点。
	if card != null and card.card_context == Card.CardContext.Selection \
			and card.card_reference != null and card.card_reference.card_type == ResourceCardReference.CardType.Plant \
			and get_parent().is_ancestor_of(card):
		return card
	return null

## 跟随 [param card]，同卡重新悬停时保留已构造的内容；没有植物可查看时淡出。
func _show_card(card: Card) -> void:
	if card == null:
		if visible and not _dismissing:
			_animate_visibility(false)
		return
	var profile: PlantSpawnProfile = card.plant_spawn_profile # 卡面和路线共用本实例的只读配方。
	var changed: bool = _shown_card != card or _shown_profile != profile # 同种不同 UID 也重新读取。
	if changed:
		_shown_card = card
		_shown_profile = profile
		_rebuild_preview(card)
	if not visible or _dismissing:
		_animate_visibility(true)
	elif changed and modulate.a >= 1.0:
		# 连续换卡时卡框保持可见，只给新内容一段很短的过渡。
		_begin_motion(Tween.EASE_OUT)
		_content.modulate.a = 0.86
		_motion.tween_property(_content, "modulate:a", 1.0, 0.13)

## 排版 [param card] 的页首和转职路线，让卡面和路线使用同一份冻结配方。
## 从纸卡设计宽度推导所有列宽，再累计已排版的高度；视口适配直接使用本次结果。
func _rebuild_preview(card: Card) -> void:
	_clear_preview()
	var snapshot: Dictionary = card.battle_card_data # 包含零星和未转职状态；没有配方时为空。
	var tier: int = card.promotion_tier() # 最高已选阶数为零时，只显示未转职标题。
	var heading_top: float = _build_header(card, int(snapshot.get("stars", 0))) + SECTION_GAP # 页首之后留出标题间距。
	var bottom: float = _build_route_heading(tier > 0, heading_top) # 下一个转职条目从已排版内容的底边开始。
	for index: int in range(tier - 1, -1, -1): # 当前转职优先，只展示这张卡选过的分支。
		var book_id: String = str(snapshot.get(PlantCardInstance.PROMOTION_FIELDS[index], "")) # 保存的稳定技能书 ID。
		if book_id.is_empty():
			continue
		var book: Dictionary = AdventurePromotionCatalog.definition(book_id) # 技能名称和说明与研究室共用。
		var current: bool = index == tier - 1 # 最高阶紧接标题，其余条目使用较小的行间距。
		bottom = _build_route_row(TIER_NAMES[index], book, current, bottom + (SECTION_GAP if current else ROUTE_GAP))
	size = Vector2(PANEL_WIDTH, bottom + 2.0 * PAPER_PADDING)

## 为 [param card] 排版左右两栏的页首，显示 [param stars] 并返回页首高度。
func _build_header(card: Card, stars: int) -> float:
	var skin := _surface(Color("2e4838"), Color("728765"), 7, 8) # 内框使卡面在不同背景上都容易辨认。
	var header := _add_section(0.0, skin) # 页首在纸卡内容区域的顶部。
	var padding: Vector2 = skin.get_offset() # 页首内侧起点。
	var copy_left: float = padding.x + PACKET_SLOT_SIZE.x + 10.0 # 卡面栏右侧留出文字间距。
	var copy_width: float = CONTENT_WIDTH - copy_left - padding.x # 名称和基础能力共享实际列宽。
	var plant_type: int = card.card_reference.content_id # 物种只用于查询基础资料。
	var title := _add_label(header, InventoryData.plant_name(plant_type), 23, Color("fff4d6"), copy_width) # 固定列宽下的植物名。
	var description: String = InventoryData.plant_description(plant_type) # 基础描述不包括转职效果。
	var copy_height: float = title.size.y # 有基础描述时加上标题间距和描述高度。
	var summary: Label # 有基础描述时的正文控件。
	if not description.is_empty():
		summary = _add_label(header, description, 14, Color("e1e9d2"), copy_width)
		copy_height += 5.0 + summary.size.y

	var inner_height: float = maxf(PACKET_SLOT_SIZE.y, copy_height) # 两栏按较高一侧定高，再各自垂直居中。
	title.position = Vector2(copy_left, padding.y + floorf((inner_height - copy_height) * 0.5))
	if summary != null:
		summary.position = title.position + Vector2(0, title.size.y + 5.0)
	_add_packet(header, card, stars, padding + Vector2(0, floorf((inner_height - PACKET_SLOT_SIZE.y) * 0.5)))
	header.size = Vector2(CONTENT_WIDTH, inner_height + 2.0 * padding.y)
	return header.size.y

## 在 [param top] 排版标题和分隔线，根据 [param has_route] 选用标题并返回底边。
func _build_route_heading(has_route: bool, top: float) -> float:
	var heading := _add_label(_content, "转职路线" if has_route else "未转职", 14, Color("684829")) # 标题按单行自然宽度占位。
	heading.position.y = top
	var divider := ColorRect.new() # 暖金细线填满标题右侧的剩余宽度。
	var divider_left: float = heading.size.x + 8.0 # 文字与细线之间留出阅读间距。
	divider.color = Color("c6a675")
	divider.position = Vector2(divider_left, top + floorf(heading.size.y * 0.5))
	divider.size = Vector2(CONTENT_WIDTH - divider_left, 1.0)
	_content.add_child(divider)
	return top + heading.size.y

## 从当前透明度向 [param appearing] 指定的方向过渡；离开时留出扫过相邻卡缝的短间隔。
func _animate_visibility(appearing: bool) -> void:
	_dismissing = not appearing
	_begin_motion(Tween.EASE_OUT if appearing else Tween.EASE_IN)
	_content.modulate.a = 1.0
	if appearing:
		show()
		_motion.tween_property(self, "modulate:a", 1.0, 0.17)
	else:
		_motion.tween_interval(0.05)
		_motion.tween_property(self, "modulate:a", 0.0, 0.12)
		_motion.tween_callback(_hide_preview)

## 以 [param easing] 启动使用真实时间的过渡，同时停掉上一段过渡。
func _begin_motion(easing: Tween.EaseType) -> void:
	if _motion != null:
		_motion.kill()
	_motion = create_tween().set_ignore_time_scale(true).set_trans(Tween.TRANS_SINE).set_ease(easing)

## 收起预览并释放独立卡面和旧路线。
func _hide_preview() -> void:
	hide()
	modulate.a = 0.0
	_dismissing = false
	_motion = null
	_shown_card = null
	_shown_profile = null
	_clear_preview()

## 立即卸下旧页首和路线，节点释放安排在帧末。
func _clear_preview() -> void:
	for child: Node in _content.get_children(): # 每个子节点只属于当前展示的卡。
		_content.remove_child(child)
		child.queue_free()

## 在 [param header] 的 [param origin] 处摆放 [param card] 的独立卡面，零 [param stars] 时补充对应标记。
func _add_packet(header: Panel, card: Card, stars: int, origin: Vector2) -> void:
	var packet: Card = AllCards.create_card(card.card_reference, Card.CardContext.Catalog) # 图鉴模式的副本只用于展示。
	if packet != null:
		packet.plant_spawn_profile = _shown_profile
		header.add_child(packet)
		packet.show()
		packet.set_process(false)
		packet.sun_cost = card.sun_cost
		packet.size = packet.get_combined_minimum_size()
		packet.scale = Vector2.ONE * PACKET_SCALE
		packet.position = origin + (PACKET_SLOT_SIZE - packet.size * PACKET_SCALE) * 0.5
	if stars == 0:
		var badge_skin := _surface(Color("38493e"), Color("c9c3a5"), 5, 2) # 零星标记沿用页首的绿底。
		var badge := _add_label(header, "0 星", 12, Color("fff3d1"), 0.0, badge_skin) # 真实卡面没有普通零星标记。
		badge.position = origin + Vector2(3, 2)
		badge.size.x = maxf(badge.size.x, 31.0)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.z_index = 1

## 在 [param top] 排版 [param tier_name] 对应的 [param book]，高亮 [param current] 条目并返回底边。
func _build_route_row(tier_name: String, book: Dictionary, current: bool, top: float) -> float:
	var fill := Color("e6ecd3") if current else Color("fff0d1") # 最新转职用低饱和绿底，与页首呼应。
	var edge := Color("8c9d75") if current else Color("d7bb89") # 浅描边帮助区分相邻条目。
	var skin := _surface(fill, edge, 6, 6) # 统一条目的内边距与描边。
	var row := _add_section(top, skin) # 路线条目按已排版的内容依序放置。
	var padding: Vector2 = skin.get_offset() # 条目内侧起点。
	var row_width: float = CONTENT_WIDTH - skin.get_minimum_size().x # 技能说明使用条目的整行宽度。
	var tier_skin := _surface(Color("526e48") if current else Color("e8cd9d"), edge, 4, 2) # 以底色区分最高转职阶数。
	var tier := _add_label(row, tier_name, 12, Color("fff6db") if current else Color("603b20"), 0.0, tier_skin) # 阶数按单行自然宽度占位。
	var title_left: float = tier.size.x + 6.0 # 阶数和技能名之间留出阅读间距。
	var title_ink := Color("304a31") if current else Color("4e3520") # 当前技能使用深绿强调。
	var title := _add_label(row, str(book.get("title", "")), 16, title_ink, row_width - title_left) # 技能名按剩余宽度换行。
	var heading_height: float = maxf(tier.size.y, title.size.y) # 阶数与技能名在同一行内各自垂直居中。
	tier.position = padding + Vector2(0, floorf((heading_height - tier.size.y) * 0.5))
	title.position = padding + Vector2(title_left, floorf((heading_height - title.size.y) * 0.5))

	var inner_height: float = heading_height # 有说明时再累计说明的实排高度。
	var summary: String = str(book.get("summary", "")) # 缺少说明时仍完整展示阶数和技能名。
	if not summary.is_empty():
		var details := _add_label(row, summary, 13, Color("51452f"), row_width) # 效果说明与条目的内侧边缘对齐。
		details.position = padding + Vector2(0, heading_height + 2.0)
		inner_height += 2.0 + details.size.y
	row.size = Vector2(CONTENT_WIDTH, inner_height + 2.0 * padding.y)
	return top + row.size.y

## 在内容区的 [param top] 处添加使用 [param skin] 的底板，由排版方设置其最终高度。
func _add_section(top: float, skin: StyleBoxFlat) -> Panel:
	var section := Panel.new() # 底板只绘制由内容排版确定的矩形。
	section.position.y = top
	section.add_theme_stylebox_override("panel", skin)
	_content.add_child(section)
	return section

## 将预览放在 [param target] 旁；目标为空时跟随候选板。长路线按可用视口避让。
func _align_preview(target: Control = null) -> void:
	if not visible or size.y <= 0.0:
		return
	# 将锚点和边界换算到预览父节点的坐标系。
	var viewport_to_parent: Transform2D = get_parent().get_global_transform_with_canvas().affine_inverse()
	var bounds: Rect2 = (viewport_to_parent * get_viewport_rect()).grow(-8.0) # 给描边和投影留出边距。
	if not bounds.has_area():
		return
	var fit: float = minf(1.0, minf(bounds.size.x / size.x, bounds.size.y / size.y)) # 仅在视口容不下原尺寸时缩小。
	var anchor: Vector2 # 淡入位移前的预览左上角。
	if target == null:
		anchor = Vector2(chooser.position.x + chooser.size.x + ANCHOR_GAP, chooser.position.y + 32.0)
	else:
		var side_anchor: Control = target.get_meta(HOVER_SIDE_META, target) as Control # 候选区使用整个滚动列表的左右边界。
		var side_bounds: Rect2 = (viewport_to_parent * side_anchor.get_global_transform_with_canvas()) \
			* Rect2(Vector2.ZERO, side_anchor.size) # 将水平参照的实际范围换算到预览父节点坐标。
		# 纵向对齐当前悬停的格子。
		var top: float = (viewport_to_parent * target.get_global_transform_with_canvas().origin).y
		anchor = Vector2(side_bounds.end.x + ANCHOR_GAP, top)
		if anchor.x + size.x * fit > bounds.end.x:
			anchor.x = side_bounds.position.x - ANCHOR_GAP - size.x * fit
	anchor.y += (1.0 - modulate.a) * REVEAL_OFFSET
	scale = Vector2.ONE * fit
	position = anchor.clamp(bounds.position, bounds.end - size * fit)

## 向 [param parent] 添加使用 [param font_size] 和 [param ink] 的 [param caption]。
## [param width] 为正时先固定换行宽度，再读取实排高度；为零时测量单行自然尺寸。[param skin] 为可选底板。
func _add_label(parent: Control, caption: String, font_size: int, ink: Color, width: float = 0.0, skin: StyleBoxFlat = null) -> Label:
	var label := Label.new() # 保持文字绘制与高度测量使用同一个控件。
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", ink)
	label.add_theme_constant_override("outline_size", 0)
	label.add_theme_constant_override("line_spacing", 2)
	if skin != null:
		label.add_theme_stylebox_override("normal", skin)
	parent.add_child(label)
	if width > 0.0:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size.x = width
	label.text = caption
	var measured: Vector2 = label.get_minimum_size().ceil() # 使用已排版的文本尺寸，向上取整保留完整字形。
	label.size = Vector2(width if width > 0.0 else measured.x, measured.y)
	return label

## 创建圆角底板；[param fill]、[param edge] 为底色与边色，[param radius]、[param padding] 以画布像素表示。
func _surface(fill: Color, edge: Color, radius: int, padding: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new() # 正文、页首和阶数徽标各自持有样式。
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = padding
	style.content_margin_top = padding
	style.content_margin_right = padding
	style.content_margin_bottom = padding
	return style
