## 商店全屏纯表现层：戴夫舞台、货架、页签和确认单，不读写玩家状态。
extends Control

## 交互意图与稳定商品/分类 ID，由窗口解释。
signal action_requested(action: String, id: String)
## 共用暖木、羊皮纸和绿金色主题。
const Style = preload("res://scripts/adventure/shop/shop_skin.gd")
## 三类商品元信息。
const Catalog = preload("res://scripts/adventure/shop/shop_catalog.gd")
## 可复用商品卡。
const ProductCard = preload("res://scripts/adventure/shop/shop_product_card.gd")
## 原版常驻戴夫封装。
const Dave = preload("res://scripts/adventure/shop/shop_dave.gd")
## 戴夫交互由窗口驱动。
var dave: Dave
## 余额只读显示。
var _coins: Label
## 分类相关的简短提示。
var _category_hint: Label
## 当前选中商品名称。
var _title: Label
## 当前商品效果和期限说明。
var _description: Label
## 购买结果或临时业务错误。
var _notice: Label
## 统一购买按钮。
var _buy: Button
## 分类按钮列表。
var _tabs: Dictionary = {}
## 当前分类商品卡，选择与余额变化时原地更新，保留键盘焦点。
var _cards: Dictionary = {}
## 货架子容器，仅切页时重建。
var _shelf: Control
## 当前已绘制分类。
var _category := ""
## 确认单覆盖右侧货架，左侧戴夫继续描述此次交易。
var _confirmation: Control
## 确认时保存焦点，取消后返回原按钮。
var _previous_focus: Control

## 构建固定布局，内容节点按报价快照更新。
func _ready() -> void:
	size = Style.DESIGN
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = Theme.new()
	theme.default_font = Style.FONT
	Style.image(self, preload("res://assets/image/store/Store_Bg_New.png"), Rect2(Vector2.ZERO, size)).stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var wash := ColorRect.new() # 暖色透明层统一背景与木质货架，不降低商品文字对比。
	wash.color = Color(0.21, 0.18, 0.10, 0.22)
	wash.size = size
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wash)
	Style.Art.panel(self, "panels/wood_ninepatch.png", Vector2(28, 24), Vector2(400, 106), 28)
	Style.label(self, "戴夫的小店", Rect2(54, 35, 348, 53), 42, Style.CREAM)
	Style.label(self, "好东西，留给好邻居。", Rect2(57, 87, 335, 28), 20, Style.GOLD)
	Style.Art.panel(self, "panels/wood_ninepatch.png", Vector2(442, 24), Vector2(968, 754), 32)
	Style.label(self, "邻 居 专 属  ·  精 选 好 物", Rect2(470, 43, 480, 43), 24, Style.CREAM)
	_coins = Style.label(self, "", Rect2(925, 42, 262, 43), 27, Style.GOLD)
	_coins.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	Style.button(self, "返回", Rect2(1223, 38, 155, 52), _emit.bind("close", ""))
	var canopy := Control.new() # 条纹遮阳棚只作为装饰，无输入命中。
	canopy.set_script(preload("res://scripts/adventure/shop/shop_canopy.gd"))
	canopy.position = Vector2(454, 101)
	canopy.size = Vector2(944, 26)
	canopy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canopy)
	for index: int in Catalog.CATEGORIES.size(): # 页签从目录生成，名称和顺序保持统一。
		var category: String = Catalog.CATEGORIES[index] # 按钮携带稳定分类 ID。
		_tabs[category] = Style.button(self, str(Catalog.CATEGORY_NAMES[category]), Rect2(466 + index * 310, 145, 294, 56), _emit.bind("category", category))
	_category_hint = Style.label(self, "", Rect2(473, 210, 870, 30), 20, Style.CREAM)
	_shelf = Control.new()
	_shelf.position = Vector2(466, 250)
	_shelf.size = Vector2(914, 382)
	_shelf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shelf)
	Style.Art.panel(self, "panels/parchment_ninepatch.png", Vector2(466, 649), Vector2(914, 106), 24)
	_title = Style.label(self, "挑一件喜欢的吧", Rect2(485, 655, 565, 37), 25)
	_description = Style.label(self, "", Rect2(485, 697, 582, 48), 18, Style.MUTED)
	_buy = Style.button(self, "购买", Rect2(1100, 674, 257, 61), _emit.bind("buy", ""), true)
	dave = Dave.new()
	add_child(dave)
	Style.Art.panel(self, "panels/wood_ninepatch.png", Vector2(22, 700), Vector2(405, 78), 24)
	Style.label(self, "疯狂戴夫", Rect2(46, 710, 180, 40), 29, Style.CREAM)
	Style.label(self, "店主 · 信誉全靠邻居", Rect2(48, 749, 330, 24), 17, Style.GOLD)
	_notice = Style.label(self, "选中商品，听听戴夫怎么说。", Rect2(467, 779, 914, 28), 18, Style.CREAM)
	_notice.add_theme_color_override("font_shadow_color", Color("302418"))
	_notice.add_theme_constant_override("shadow_offset_y", 1)

## 根据 [param model] 同步分类、报价、余额和锁定状态；不持有可写业务对象。
func render(model: Dictionary) -> void:
	_coins.text = "%s 金币" % Style.money(int(model.coins))
	var locked: bool = bool(model.locked) # 进场、确认和发疯期间都不接受第二次商品选择。
	for category: String in _tabs: # 当前页保持明确的绿金色高亮。
		var button: Button = _tabs[category] # 固定节点不重建，键盘焦点稳定。
		button.disabled = locked
		button.add_theme_stylebox_override("normal", Style.box(Style.GREEN if category == model.category else Color("eddbb2"), Style.GOLD))
		button.add_theme_color_override("font_color", Style.CREAM if category == model.category else Style.INK)
	match str(model.category):
		"daily":
			_category_hint.text = "每日补货  /  本机时间 00:00 更新限购数量"
		"permanent":
			_category_hint.text = "随时补给  /  购买起7天有效，请到角色页装备"
		"special":
			_category_hint.text = "永久珍藏  /  时装与卡槽升级"
	if _category != str(model.category):
		_rebuild_cards(model.offers)
		_category = str(model.category)
	for offer: Dictionary in model.offers: # 报价已由服务重算，UI 不重复价格算法。
		if _cards.has(str(offer.id)):
			_cards[str(offer.id)].update_offer(offer, str(offer.id) == str(model.selected), locked)
	var selected: Dictionary = model.offer # 当前选中商品的报价投影。
	if selected.is_empty():
		_buy.disabled = true
		return
	_title.text = str(selected.title)
	_description.text = str(selected.description)
	_buy.disabled = locked or not selected.can_buy
	_buy.text = str(selected.message) if not selected.can_buy else "购买 · %s" % Style.money(int(selected.price))
	_notice.text = str(model.notice) if not str(model.notice).is_empty() else "选中商品，听听戴夫怎么说。"

## 切页时按 [param offers] 自动均分货位；商品超过四个时可横向滚动扩展。
func _rebuild_cards(offers: Array[Dictionary]) -> void:
	for child: Node in _shelf.get_children(): # 先移出树，阻止旧商品继续拦截鼠标。
		_shelf.remove_child(child)
		child.queue_free()
	_cards.clear()
	if offers.is_empty():
		return
	var count: int = mini(4, offers.size()) # 一屏最多四张，保持标题最低可读宽度。
	var width: float = (914.0 - 16.0 * (count - 1)) / count # 货位均分右侧可用空间。
	var scroll := ScrollContainer.new() # 后续新增商品无需改变窗口布局。
	scroll.size = _shelf.size
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_shelf.add_child(scroll)
	var content := Control.new() # 自由布局容器，最小宽度决定横向滚动范围。
	content.custom_minimum_size = Vector2(offers.size() * (width + 16) - 16, 378)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(content)
	for index: int in offers.size(): # 每张卡只派发稳定商品 ID。
		var offer: Dictionary = offers[index] # 只读报价数据。
		var card := ProductCard.new() # 独立视觉组件，不附带存档服务。
		content.add_child(card)
		card.configure(offer, Rect2(index * (width + 16), 0, width, 378))
		card.pressed.connect(_emit.bind("select", str(offer.id)))
		_cards[str(offer.id)] = card

## 为 [param offer] 展示确认单；询价后由戴夫询问成交，确认按钮是唯一提交入口。
func show_confirmation(offer: Dictionary) -> void:
	hide_confirmation(false)
	_previous_focus = get_viewport().gui_get_focus_owner()
	_confirmation = Control.new()
	_confirmation.name = "PurchaseConfirmation"
	_confirmation.size = Style.DESIGN
	_confirmation.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_confirmation)
	var shade := ColorRect.new() # 覆盖货架，但不遮住左边提出成交询问的戴夫。
	shade.position = Vector2(450, 130)
	shade.size = Vector2(952, 638)
	shade.color = Color(0.12, 0.08, 0.04, 0.73)
	_confirmation.add_child(shade)
	Style.Art.panel(_confirmation, "panels/parchment_ninepatch.png", Vector2(626, 249), Vector2(600, 349), 28)
	Style.label(_confirmation, "成交？", Rect2(663, 270, 510, 57), 40, Style.INK)
	Style.image(_confirmation, Style.product_texture(offer), Rect2(659, 343, 115, 114))
	Style.label(_confirmation, str(offer.title), Rect2(800, 346, 392, 45), 29)
	Style.label(_confirmation, "%s 金币" % Style.money(int(offer.price)), Rect2(800, 396, 380, 39), 31, Style.GREEN)
	Style.label(_confirmation, str(offer.status), Rect2(663, 458, 526, 36), 19, Style.MUTED)
	Style.button(_confirmation, "再想想", Rect2(659, 515, 246, 56), _emit.bind("cancel", ""))
	var confirm_button: Button = Style.button(_confirmation, "成交！", Rect2(929, 515, 262, 56), _emit.bind("confirm", ""), true) # 键盘初始焦点落在明确确认操作。
	confirm_button.grab_focus()

## 移除确认单；[param restore_focus] 决定是否将键盘焦点还给原入口。
func hide_confirmation(restore_focus: bool = true) -> void:
	if is_instance_valid(_confirmation):
		_confirmation.hide()
		_confirmation.queue_free()
	_confirmation = null
	if restore_focus and is_instance_valid(_previous_focus) and _previous_focus.is_visible_in_tree():
		_previous_focus.grab_focus()
	_previous_focus = null

## 对外只发送 [param action] 和 [param id]，不在回调里执行任何资产变更。
func _emit(action: String, id: String) -> void:
	action_requested.emit(action, id)
