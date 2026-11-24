## 以研究所的羊皮纸呈现当前档案的强化日志，按结算顺序倒序分页。
extends Control

## 日志退出动效结束后由研究室恢复操作区。
signal closed

## 植物名称、纸边、字体和底栏都复用研究室已有资源。
const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")
## 纸面范围与研究室工作区一致。
const Layout = preload("res://scripts/adventure/ui/research_panel_skin.gd")
## 与规则页共用纸色、墨色、圆角和文字比例。
const Style = preload("res://scripts/adventure/ui/research_rules_style.gd")
## 使用原有短动效过渡到工作区和返回。
const Motion = preload("res://scripts/ui/transitions/modal_motion.gd")
## 只查询当前页的植物名称，避免长日志加载卡面或重建所有行。
const Names = preload("res://scripts/adventure/ui/inventory_data.gd")
## 固定一页容纳六行，档案记录增长只增加页数。
const PAGE_SIZE := 6
## 每行的可见高度，不含下方的留白。
const ROW_HEIGHT := 62.0
## 相邻行顶部之间的距离，留出均匀的纸面间隙。
const ROW_STEP := 70.0

## 打开时绑定当前档案，读取已冻结的记录，不复制整个数组。
var entries: Array[Dictionary] = []
## 当前页的零基索引，零表示最近结算的记录。
var _page := 0
## 至少一页；历史为空时直接展示空态。
var _page_count := 1
## 只容纳当前页的动态行，翻页时清空。
var _rows: Control
## 页码标签；只有多页时创建。
var _page_label: Label
## 向更新的记录翻页，第一页禁用。
var _previous: Button
## 向更早的记录翻页，最后一页禁用。
var _next: Button
## 日志页与返回按钮的共同过渡。
var _motion: Motion

## 建立整张日志页，只绘制第一页和共用页眉。
func _ready() -> void:
	name = "ResearchHistory"
	size = Layout.DESIGN
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Style.prepare()
	var surface := Control.new() # 动画只移动日志页，研究室的画布适配照常工作。
	surface.size = size
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(surface)
	var area := Rect2(Layout.SELECTION_REGION.position,
		Layout.INFO_REGION.end - Layout.SELECTION_REGION.position) # 一张纸面横跨原来的三个工作槽面板。
	var paper: NinePatchRect = Art.panel(surface, "panels/parchment_ninepatch.png", area.position, area.size, 30) # 沿用规则页的纸边。
	var sheet_width: float = area.size.x - 76.0 # 页眉、行卡与页脚共用的内宽。
	var header: Panel = Style.panel(paper, Rect2(38, 20, sheet_width, 76), Style.FOREST, Style.EDGE) # 深绿色封面延续强化规则的主色。
	Art.image(header, "overlays/star_filled.png", Vector2(22, 14), Vector2(48, 48))
	Style.label(header, "强化历史", Rect2(88, 0, 480, 76), 40, Style.CREAM, Style.bold)
	var total: Label = Style.label(header, "共 %d 条" % entries.size(),
		Rect2(sheet_width - 315, 0, 280, 76), 26, Style.GOLD, Style.bold) # 总数常驻页眉，翻页时无需重复计算。
	total.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if entries.is_empty():
		var empty: Panel = Style.panel(paper, Rect2(38, 132, sheet_width, 468),
			Color("f6e6c9"), Color("cfb78b")) # 用单张浅纸承接空态，不绘制空表头和无效翻页。
		Style.band(empty, "暂无强化记录", Rect2(36, 175, sheet_width - 72, 54),
			Color.TRANSPARENT, Style.FOREST, 38)
		Style.band(empty, "完成一次强化后，结算结果会显示在这里。",
			Rect2(36, 236, sheet_width - 72, 44), Color.TRANSPARENT, Style.MUTED, 25)
	else:
		_build_list(paper, sheet_width)
	var back: Button = Art.action_button(surface, "返回强化", "buttons/action_neutral",
		Layout.ACTION_REGION.position, Layout.ACTION_REGION.size, dismiss) # 与强化按钮使用同一个底栏位置。
	back.name = "ResearchHistoryReturn"
	back.add_theme_font_size_override("font_size", 30)
	back.add_theme_font_override("font", Style.bold)
	_motion = Motion.new()
	_motion.target = surface
	_motion.hidden_scale = 0.988
	_motion.hidden_offset = Vector2(0, 22)
	_motion.close_seconds = 0.17
	_motion.closed.connect(_on_motion_closed)
	add_child(_motion)
	_motion.play_open()

## 在 [param paper] 的 [param sheet_width] 可用宽度内布置表头和分页区。
func _build_list(paper: Control, sheet_width: float) -> void:
	Style.label(paper, "植物", Rect2(70, 106, 470, 42), 23, Style.MUTED, Style.bold)
	Style.label(paper, "星级变化", Rect2(592, 106, 224, 42), 23, Style.MUTED, Style.bold)
	Style.label(paper, "结果", Rect2(934, 106, 190, 42), 23, Style.MUTED, Style.bold)
	Style.label(paper, "本机时间", Rect2(1248, 106, 310, 42), 23, Style.MUTED, Style.bold)
	_rows = Control.new()
	_rows.position = Vector2(38, 150)
	_rows.size = Vector2(sheet_width, ROW_STEP * PAGE_SIZE)
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper.add_child(_rows)
	_page_count = ceili(float(entries.size()) / PAGE_SIZE)
	if _page_count > 1:
		Style.rule(paper, Rect2(38, 578, sheet_width, 1), Style.EDGE)
		_previous = _page_button(paper, "上一页", sheet_width - 400, -1)
		_next = _page_button(paper, "下一页", sheet_width - 109, 1)
		_page_label = Style.label(paper, "", Rect2(sheet_width - 253, 586, 144, 42), 24, Style.MUTED, Style.bold)
		_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_draw_page()

## 在 [param parent] 的 [param x] 位置创建题签式按钮，[param caption] 标明 [param offset] 的翻页方向。
func _page_button(parent: Control, caption: String, x: float, offset: int) -> Button:
	var button := Button.new() # 紧凑的纸面导航使用细描边，区别于木条上的返回按钮。
	button.text = caption
	button.position = Vector2(x, 586)
	button.size = Vector2(147, 42)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", Style.bold)
	button.add_theme_font_size_override("font_size", 23)
	button.add_theme_color_override("font_color", Style.FOREST)
	button.add_theme_color_override("font_hover_color", Style.CREAM)
	button.add_theme_color_override("font_pressed_color", Style.CREAM)
	button.add_theme_color_override("font_focus_color", Style.FOREST)
	button.add_theme_color_override("font_disabled_color", Color("826e53"))
	button.add_theme_stylebox_override("normal", Style.box(Color("f9ebcd"), Style.EDGE, 9))
	button.add_theme_stylebox_override("hover", Style.box(Style.FOREST, Style.GOLD, 9))
	button.add_theme_stylebox_override("pressed", Style.box(Color("1e362a"), Style.GOLD, 9))
	button.add_theme_stylebox_override("disabled", Style.box(Color("eee0c0"), Color("c4ad83"), 9))
	var focus: StyleBoxFlat = Style.box(Color.TRANSPARENT, Color("9b672b"), 9) # 键盘焦点在浅纸与墨绿上都有描边。
	focus.set_border_width_all(2)
	button.add_theme_stylebox_override("focus", focus)
	button.pressed.connect(_change_page.bind(offset))
	parent.add_child(button)
	return button

## 以 [param offset] 翻至相邻页，越界和退出中的请求忽略。
func _change_page(offset: int) -> void:
	var destination: int = _page + offset # 页号递增表示向更早的记录浏览。
	if _motion.phase == Motion.Phase.CLOSING or destination < 0 or destination >= _page_count:
		return
	_page = destination
	_draw_page()
	if offset > 0 and _next.disabled:
		_previous.grab_focus()
	elif offset < 0 and _previous.disabled:
		_next.grab_focus()
	SoundManager.play_other_SFX(&"tap")

## 直接按追加顺序倒序索引，最多绘制一页；本机时间调整也不会打乱结算顺序。
func _draw_page() -> void:
	for previous: Node in _rows.get_children(): # 当帧移除旧行，保留静态页眉、导航及其焦点。
		_rows.remove_child(previous)
		previous.queue_free()
	var newest: int = entries.size() - 1 - _page * PAGE_SIZE # 只计算当前页的起点，不排序或反转档案。
	for row_index: int in range(mini(newest + 1, PAGE_SIZE)): # 末页仅绘制实际存在的记录。
		_draw_entry(entries[newest - row_index], row_index)
	if _page_count > 1:
		_page_label.text = "%d / %d" % [_page + 1, _page_count]
		_previous.disabled = _page == 0
		_next.disabled = _page + 1 == _page_count

## 在当前页的 [param row_index] 行绘制快照 [param entry]。
func _draw_entry(entry: Dictionary, row_index: int) -> void:
	var tint: Color = Color("fbefd7") if row_index % 2 == 0 else Color("f3e4c8") # 交替的浅纸底帮助横向阅读。
	var row: Panel = Style.panel(_rows, Rect2(0, row_index * ROW_STEP, _rows.size.x, ROW_HEIGHT),
		tint, Color("d5bd91"), 10) # 细铜边衔接页眉，保留各行间距。
	var plant_type: int = int(entry.plant_type) # 历史仍可显示已经用掉或不再注册的物种。
	var plant_name: String = Names.plant_name(plant_type) if CharacterRegistry.PlantInfo.has(plant_type) \
		else "植物 #%d" % plant_type # 已在图鉴移除的编号仍有可读标识。
	var outcome: int = int(entry.outcome) # 读档后的 JSON 数字先恢复为结果编号。
	var caption: String = "失败" # 普通失败使用红褐色，保星与成功有各自的文字。
	var ink: Color = Style.RUST # 徽记与行首色条共用同一结果色。
	var badge: Color = Color("f0d8c9") # 浅红徽记与深红文字保持对比。
	if outcome == AdventureState.EnhancementOutcome.SUCCESS:
		caption = "成功"
		ink = Style.FOREST
		badge = Color("dce7d1")
	elif outcome == AdventureState.EnhancementOutcome.PROTECTED:
		caption = "花盆保星"
		ink = Color("694e1f")
		badge = Color("f2e2b0")
	Style.panel(row, Rect2(12, 14, 5, 34), ink, Color.TRANSPARENT, 3)
	var title: Label = Style.label(row, plant_name, Rect2(32, 0, 496, ROW_HEIGHT), 30, Style.INK, Style.bold) # 长名称省略尾部，保留结果列宽。
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	Style.label(row, "%d 星  →  %d 星" % [int(entry.before_stars), int(entry.after_stars)],
		Rect2(554, 0, 270, ROW_HEIGHT), 27, Style.INK, Style.bold)
	Style.band(row, caption, Rect2(896, 11, 160, 40), badge, ink, 23)
	Style.label(row, str(entry.time), Rect2(1210, 0, 360, ROW_HEIGHT), 25, Style.MUTED)

## 关闭日志页；[param play_sound] 为 false 时由切换页签的一方负责音效。
func dismiss(play_sound: bool = true) -> void:
	if _motion.phase == Motion.Phase.CLOSING:
		return
	if play_sound:
		SoundManager.play_other_SFX(&"tap")
	_motion.play_close()

## 退场后通知宿主并释放展示控件，不修改任何档案数据。
func _on_motion_closed() -> void:
	hide()
	closed.emit()
	queue_free()
