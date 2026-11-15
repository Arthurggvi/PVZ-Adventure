## 图书馆纯表现层；只接收展示快照并派发意图，不保存或扣除任何资产。
extends Control

## [param action] 是交互名称，[param data] 仅携带选择 ID、索引或货架版本。
signal action_requested(action: String, data: Variant)
## 共用木框、羊皮纸与按钮素材。
const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")
## 四阶书本与植物封面组合。
const BookArt = preload("res://scripts/adventure/ui/promotion_book_visual.gd")
## 书架只装配可见书本，其他页和滚动区外条目保持轻量按钮。
const VisualQueue = preload("res://scripts/adventure/ui/prepared_visual_queue.gd")
## 书本依赖由物品与卡牌权威目录解析。
const ResourcePaths = preload("res://scripts/adventure/ui/ui_resource_paths.gd")
## 当前书架的唯一预览装配队列。
var _visual_queue: VisualQueue

## 首屏书本准备结束后通知模态宿主。
func is_content_ready() -> bool:
	return _visual_queue != null and _visual_queue.is_content_ready()

## 在 [param target] 的 [param bounds] 装配 [param id]，只准备该本书对应植物。
func _queue_book(target: Control, id: String, bounds: Rect2) -> void:
	var paths := PackedStringArray() # 书皮、底图和植物头像来自共享目录。
	ResourcePaths.inventory_rows(paths, [{"id": id, "category": "promotion_book"}])
	_visual_queue.enqueue(target, paths, BookArt.draw.bind(target, id, bounds))
## 本地化植物名投影。
const Names = preload("res://scripts/adventure/ui/inventory_data.gd")
## 技能定义与图书馆规则。
const Rules = preload("res://scripts/adventure/library/library_rules.gd")
## 等比缩放的设计画布尺寸。
const DESIGN := Vector2(1440, 820)
## 沿用任务簿与研究室的中文字体。
const FONT = preload("res://assets/fonts/方正少儿_GBK.ttf")
## 四阶书籍的辅助标记颜色。
const TIER_COLORS: Array[Color] = [Color("507b43"), Color("397b96"), Color("8457a4"), Color("af7227")]
## 顶部当前余额。
var _coins: Label
## 切页按钮，保留焦点和统一选中反馈。
var _tabs: Dictionary = {}
## 页签互斥且不可取消当前选择。
var _tab_group := ButtonGroup.new()
## 动态正文节点，重绘不触及标题与关闭按钮。
var _body: Control
## 当前材料滚动容器，刷新数量时保留滚动位置。
var _scroll: ScrollContainer
## 仅用于判断切页是否需要复位滚动。
var _last_mode := ""
## 重绘后按稳定交互身份恢复材料按钮焦点。
var _focus_targets: Dictionary = {}
## 材料满槽时供键盘焦点自然跳至确认操作。
var _submit: Button

## 构造固定外框；所有内容绘制采用设计坐标。
func _ready() -> void:
	_visual_queue = VisualQueue.new()
	add_child(_visual_queue)
	size = DESIGN
	theme = Theme.new()
	theme.default_font = FONT
	Art.panel(self, "panels/wood_ninepatch.png", Vector2.ZERO, DESIGN, 35)
	Art.panel(self, "panels/outer_frame_ninepatch.png", Vector2.ZERO, DESIGN, 42)
	Art.image(self, "res://assets/adventure/ui/bottom_bar/icons/icon_deck.png", Vector2(42, 29), Vector2(60, 60))
	Art.label(self, "图书馆", Vector2(115, 27), Vector2(320, 62), 40, Color("ffe8b0"))
	_coins = Art.label(self, "", Vector2(1020, 34), Vector2(270, 48), 25, Color("ffe8b0"))
	_coins.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	Art.button(self, "controls/close", Vector2(1336, 27), Vector2(62, 62), _emit.bind("close", null))
	var modes: Array[String] = ["today", "convert", "synthesize"] # 固定分页顺序与交互 ID。
	var captions: Array[String] = ["今日书籍", "书籍转换", "书籍合成"] # 简短页签避免大段规则占位。
	for index: int in modes.size(): # 每页沿用素材按钮，当前页使用绿金色强调。
		_tabs[modes[index]] = Art.action_button(self, captions[index], "buttons/action_neutral",
			Vector2(46 + index * 236, 108), Vector2(222, 60), _emit.bind("mode", modes[index]))
		_tabs[modes[index]].toggle_mode = true
		_tabs[modes[index]].button_group = _tab_group
	_body = Control.new()
	_body.position = Vector2(0, 184)
	_body.size = Vector2(1440, 600)
	add_child(_body)

## 返回 [param mode] 对应的固定页签，未知模式返回 null。
func tab_control(mode: String) -> Control:
	return _tabs.get(mode)

## 用 [param model] 的只读快照更新书卡、材料槽与结果；不接收可写玩家状态。
func render(model: Dictionary) -> void:
	_coins.text = "金币  %s" % money(int(model.coins))
	var previous_focus: Control = get_viewport().gui_get_focus_owner() # 重绘前记录输入身份，避免连续键盘选择中断。
	var focus_key: String = str(previous_focus.get_meta("library_focus", "")) if is_instance_valid(previous_focus) else "" # 不恢复外部或页签焦点。
	_focus_targets.clear()
	_submit = null
	var scroll_position: int = _scroll.scroll_vertical if is_instance_valid(_scroll) and _last_mode == model.mode else 0 # 选择后维持背包位置。
	_scroll = null
	for child: Node in _body.get_children(): # 移出树后延迟销毁，避免同帧旧按钮继续覆盖新内容。
		_body.remove_child(child)
		child.queue_free()
	for mode: String in _tabs: # 使用按下态而非禁用态，选中页文字仍清晰可读。
		var tab: Button = _tabs[mode] # 同一页签始终复用控件。
		tab.modulate = Color("fff2c8") if mode == model.mode else Color("bba98f")
		tab.set_pressed_no_signal(mode == model.mode)
	if model.mode == "today":
		_today(model)
	else:
		_workbench(model)
		_scroll.set_deferred("scroll_vertical", scroll_position)
	_last_mode = model.mode
	if not focus_key.is_empty():
		_restore_focus.call_deferred(focus_key)

## 绘制 [param model] 中的五个独立货位，按钮携带当前货架版本。
func _today(model: Dictionary) -> void:
	Art.label(_body, "每日甄选", Vector2(54, 5), Vector2(300, 42), 28, Color("ffe8b0"))
	var period: Label = Art.label(_body, "每日 00:00 更新 · 换一批每日限 1 次", Vector2(54, 48), Vector2(450, 32), 20, Color("d7bc8c")) # 概率放入悬停，不占主要阅读空间。
	period.mouse_filter = Control.MOUSE_FILTER_STOP
	period.tooltip_text = "一阶 39.5% · 二阶 27.6% · 三阶 19.4% · 四阶 13.5%"
	var is_current_day: bool = model.shelf.day == model.today # 只有当天生成的货架可手动换书。
	var refresh_used: bool = is_current_day and model.shelf.refresh_used # 已用状态只对应本机今天。
	var refresh_caption: String = "今日已换一批" if refresh_used else "换一批 · %s" % money(Rules.REFRESH_COST) # 显示当日用量或金币费用。
	var refresh_button: Button = Art.action_button(_body, refresh_caption, "buttons/action_neutral",
		Vector2(1090, 9), Vector2(290, 62), _emit.bind("refresh", int(model.shelf.revision))) # 提交货架版本以拦截过期操作。
	refresh_button.disabled = not is_current_day or refresh_used or int(model.coins) < Rules.REFRESH_COST or model.shelf.offers.is_empty()
	if model.shelf.offers.is_empty():
		_centered(_body, "书架暂未就绪", Vector2(300, 220), Vector2(840, 80), 28)
		Art.action_button(_body, "重新加载", "buttons/action_neutral", Vector2(610, 325), Vector2(220, 60), _emit.bind("retry", null))
		return
	for index: int in model.shelf.offers.size(): # 同书重复货位仍分别呈现已售出状态。
		var offer: Dictionary = model.shelf.offers[index] # 持久化货位快照。
		var book: Dictionary = Rules.Books.definition(str(offer.id)) # 技能及阶级始终读取唯一目录。
		var origin := Vector2(52 + index * 268, 100) # 五本书等间距排布。
		var card := Control.new() # 单张书卡承载美术、标题和购买按钮。
		card.position = origin
		card.size = Vector2(248, 434)
		_body.add_child(card)
		Art.panel(card, "panels/parchment_ninepatch.png", Vector2.ZERO, card.size, 24)
		_centered(card, tier_name(int(book.tier)), Vector2(20, 15), Vector2(208, 35), 22, TIER_COLORS[int(book.tier) - 1])
		_queue_book(card, str(offer.id), Rect2(29, 58, 190, 190))
		_centered(card, str(book.title), Vector2(14, 250), Vector2(220, 44), 28)
		_centered(card, Names.plant_name(int(book.plant_type)), Vector2(14, 294), Vector2(220, 34), 21, Color("806442"))
		var price: int = Rules.PRICES[int(book.tier) - 1] # 价格由等阶映射，不信任 UI 或存档中的任意数值。
		var purchase: Button = Art.action_button(card, "已售出" if offer.sold else "%s 金币" % money(price), "buttons/action_confirm",
			Vector2(20, 348), Vector2(208, 60), _emit.bind("buy", {"revision": model.shelf.revision, "slot": index})) # 点击只提交货位身份。
		purchase.disabled = bool(offer.sold) or int(model.coins) < price
		card.tooltip_text = tooltip(str(offer.id))
		if offer.sold:
			card.modulate = Color(0.8, 0.76, 0.68)

## 绘制 [param model] 的可选书库和材料工作台；结果区显示最近真实获得的书。
func _workbench(model: Dictionary) -> void:
	Art.panel(_body, "panels/parchment_ninepatch.png", Vector2(36, 0), Vector2(800, 590), 28)
	Art.panel(_body, "panels/parchment_ninepatch.png", Vector2(852, 0), Vector2(552, 590), 28)
	Art.label(_body, "我的技能书", Vector2(65, 18), Vector2(250, 42), 28)
	var tiers: int = 4 if model.mode == "convert" else 3 # 合成页不提供四阶筛选。
	for tier: int in range(0, tiers + 1): # 零表示全部，其余按阶筛选库存。
		var filter_button: Button = Art.action_button(_body, "全部" if tier == 0 else "%d阶" % tier, "buttons/action_neutral",
			Vector2(320 + tier * 94, 19), Vector2(88, 43), _emit.bind("tier", tier)) # 使用紧凑短文案。
		filter_button.add_theme_font_size_override("font_size", 20)
		filter_button.modulate = Color.WHITE if int(model.tier) == tier else Color("b8a78c")
	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(59, 82)
	_scroll.size = Vector2(750, 481)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(_scroll)
	var grid := GridContainer.new() # 目录滚动支持任意新增物种，无硬编码书目数量。
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	_scroll.add_child(grid)
	var required: int = 2 if model.mode == "convert" else 3 # 决定材料槽数量和确认文案。
	for entry: Dictionary in model.available: # 已按实际剩余数量过滤，已选材料仍显示在右侧。
		var tile: Button = _book_tile(grid, str(entry.id), Vector2(172, 176), "select", str(entry.id)) # 只选择一本，可按库存重复选择。
		tile.disabled = model.selected.size() >= required
		Art.count_badge(tile, "×%d" % int(entry.count), Vector2(154, 118))
	if model.available.is_empty():
		_centered(_body, "暂无符合条件的技能书", Vector2(110, 245), Vector2(650, 70), 25, Color("887353"))
	Art.label(_body, "投入书籍  %d / %d" % [model.selected.size(), required], Vector2(880, 17), Vector2(330, 45), 27)
	Art.action_button(_body, "清空", "buttons/action_neutral", Vector2(1260, 20), Vector2(112, 44), _emit.bind("clear", null))
	var hint: String = "同阶两本 → 同阶新书" if model.mode == "convert" else "同物种同阶三本 → 高一阶" # 唯一常驻规则行。
	Art.label(_body, hint, Vector2(882, 66), Vector2(486, 38), 22, Color("806442"))
	for slot: int in required: # 已选槽可点击移除，未选槽只提示可添加。
		var pos := Vector2(886 + slot * 166 + (83 if required == 2 else 0), 117) # 两槽居中，三槽等距。
		if slot < model.selected.size():
			var tile: Button = _book_tile(_body, str(model.selected[slot]), Vector2(152, 160), "remove", slot) # 不在选择时修改真实库存。
			tile.position = pos
		else:
			Art.panel(_body, "slots/item_slot_normal.png", pos, Vector2(152, 160), 16)
			_centered(_body, "+", pos + Vector2(0, 40), Vector2(152, 65), 42, Color("a28c65"))
	var result_id: String = str(model.result) # 只呈现已提交并保存成功的结果。
	if result_id.is_empty():
		var result_caption := "随机技能书" # 尚未投入时不推测结果物种或等阶。
		if not model.selected.is_empty():
			var first: Dictionary = Rules.Books.definition(str(model.selected[0])) # 首槽决定预期等阶与合成物种。
			result_caption = "%s · 随机技能" % tier_name(int(first.tier)) if model.mode == "convert" \
				else "%s · %s" % [Names.plant_name(int(first.plant_type)), tier_name(int(first.tier) + 1)]
		_centered(_body, "↓", Vector2(1044, 294), Vector2(168, 42), 30, Color("967a4c"))
		_centered(_body, result_caption, Vector2(903, 344), Vector2(450, 60), 28)
		_centered(_body, "保留等阶 · 不限物种" if model.mode == "convert" else "保留物种 · 提升一阶",
			Vector2(903, 405), Vector2(450, 34), 20, Color("806442"))
	else:
		var result_visual := Control.new() # 独立目标在下次重绘时销毁，旧加载回调不会画入新页面。
		result_visual.position = Vector2(899, 313)
		result_visual.size = Vector2(140, 140)
		_body.add_child(result_visual)
		_queue_book(result_visual, result_id, Rect2(Vector2.ZERO, result_visual.size))
		Art.label(_body, "已获得", Vector2(1056, 314), Vector2(300, 32), 20, Color("507b43"))
		Art.label(_body, str(Rules.Books.definition(result_id).title), Vector2(1056, 351), Vector2(310, 44), 28)
		Art.label(_body, "%s · %s" % [Names.plant_name(int(Rules.Books.definition(result_id).plant_type)), tier_name(int(Rules.Books.definition(result_id).tier))],
			Vector2(1056, 399), Vector2(310, 32), 20, Color("806442"))
	var submit: Button = Art.action_button(_body, "转换书籍" if model.mode == "convert" else "合成书籍", "buttons/action_confirm",
		Vector2(953, 482), Vector2(350, 68), _emit.bind("combine", null)) # 完整材料和足够库存才可执行。
	submit.disabled = not bool(model.quote.ready)
	submit.tooltip_text = str(model.quote.get("message", ""))
	submit.set_meta("library_focus", "combine")
	_focus_targets["combine"] = submit
	_submit = submit

## 在 [param parent] 创建 [param id] 的书卡；[param dimensions] 为设计尺寸，[param action] 与 [param data] 为点击意图。
func _book_tile(parent: Node, id: String, dimensions: Vector2, action: String, data: Variant) -> Button:
	var tile := Button.new() # 原生按钮提供焦点、禁用与键盘操作。
	tile.custom_minimum_size = dimensions
	tile.size = dimensions
	tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]: # 焦点与悬停共用现有高亮素材。
		var style: StyleBoxTexture = Art.texture_style("slots/item_slot_%s.png" % ("hover" if state in ["hover", "focus"] else "normal"), 15) # 保留物品格边缘。
		tile.add_theme_stylebox_override(state, style)
	parent.add_child(tile)
	var book: Dictionary = Rules.Books.definition(id) # 标题与说明直接读取技能目录。
	var image_size: float = dimensions.y - 57 # 为技能名、等阶预留底部空间。
	_queue_book(tile, id, Rect2((dimensions.x - image_size) * 0.5, 5, image_size, image_size))
	_centered(tile, str(book.title), Vector2(7, dimensions.y - 51), Vector2(dimensions.x - 14, 29), 20)
	_centered(tile, tier_name(int(book.tier)), Vector2(7, dimensions.y - 26), Vector2(dimensions.x - 14, 22), 16, TIER_COLORS[int(book.tier) - 1])
	tile.tooltip_text = tooltip(id)
	tile.pressed.connect(_emit.bind(action, data))
	var focus_key: String = "%s:%s" % [action, str(data)] # 区分候选书 ID 和投入槽索引。
	tile.set_meta("library_focus", focus_key)
	_focus_targets[focus_key] = tile
	return tile

## 用 [param key] 恢复仍存在且可操作的按钮；材料满槽时聚焦确认，其他情况选择首个候选。
func _restore_focus(key: String) -> void:
	var target: Button = _focus_targets.get(key) # 相同书仍有余量时优先连续选择。
	if is_instance_valid(target) and not target.disabled:
		target.grab_focus()
	elif is_instance_valid(_submit) and not _submit.disabled:
		_submit.grab_focus()
	else:
		for candidate: Button in _focus_targets.values(): # 材料用尽或槽位删除后回到有效候选。
			if is_instance_valid(candidate) and not candidate.disabled:
				candidate.grab_focus()
				break

## 绘制居中文字 [param caption] 到 [param parent]；[param pos]、[param dimensions] 为布局，[param font_size]、[param color] 控制样式。
func _centered(parent: Node, caption: String, pos: Vector2, dimensions: Vector2, font_size: int, color: Color = Color("382719")) -> Label:
	var label: Label = Art.label(parent, caption, pos, dimensions, font_size, color) # 标题文字裁剪，完整书名在悬停中可读。
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label

## 发送 [param action] 和 [param data]，所有输入由宿主重新校验。
func _emit(action: String, data: Variant) -> void:
	action_requested.emit(action, data)

## [param tier] 为一至四阶，返回短标签。
static func tier_name(tier: int) -> String:
	return ["一阶", "二阶", "三阶", "四阶"][clampi(tier - 1, 0, 3)]

## 返回 [param id] 的植物、技能、等阶及简短效果，详情只在悬停展示。
static func tooltip(id: String) -> String:
	var book: Dictionary = Rules.Books.definition(id) # 未知书目不生成误导提示。
	if book.is_empty():
		return ""
	return "%s · %s\n%s\n%s" % [Names.plant_name(int(book.plant_type)), tier_name(int(book.tier)), book.title, book.summary]

## 将非负金币 [param amount] 格式化为易读的千位分隔数字。
static func money(amount: int) -> String:
	var digits: String = str(amount) # 原始数字不采用浮点缩写，避免十万与一万混淆。
	var result := "" # 从右往左插入分隔符。
	for index: int in digits.length(): # 按距右边界的位数分组。
		if index > 0 and (digits.length() - index) % 3 == 0:
			result += ","
		result += digits[index]
	return result
