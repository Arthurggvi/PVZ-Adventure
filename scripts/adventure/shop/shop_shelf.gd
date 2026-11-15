## 数据驱动商品货架：固定尺寸卡片自动换行，纵向滚动容纳任意数量，不依赖分类商品数。
extends Control

## 只派发稳定商品 ID，由窗口决定选择行为。
signal selected(id: String)
## 独立商品卡组件。
const ProductCard = preload("res://scripts/adventure/shop/shop_product_card.gd")
## 共用滚动条颜色。
const Style = preload("res://scripts/adventure/shop/shop_skin.gd")
## 卡片间距不随商品数量变化。
const GAP := 18
## 固定保留滚动条区域，避免内容增加时货架抖动。
const SCROLL_GUTTER := 22
## 原生滚动容器，负责鼠标滚轮和键盘焦点可见性。
var _scroll: ScrollContainer
## 原生网格，列数只由可用宽度决定。
var _grid: GridContainer
## 依稳定商品 ID 复用卡片，余额变化不重新构造节点。
var _cards: Dictionary = {}
## 上次货架的顺序签名；只在商品集合变化时回到顶部。
var _ids: Array[String] = []
## 换页淡入只作用于新货架，切页或关闭自动中断旧补间。
var _transition: Tween
## 键盘聚焦使用与鼠标相同的详情卡，不增加常驻说明区域。
var _focus_hint: PanelContainer
## 提示跟随的当前商品卡；离焦、锁定或切页即清理。
var _hint_card: Button

## 构造没有固定货位数量的滚动网格。
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	add_child(_scroll)
	var alignment := CenterContainer.new() # 单排垂直居中；内容超过视口时自然撑高并交给滚动容器。
	alignment.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	alignment.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(alignment)
	_grid = GridContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_grid.add_theme_constant_override("h_separation", GAP)
	_grid.add_theme_constant_override("v_separation", GAP)
	alignment.add_child(_grid)
	var bar: VScrollBar = _scroll.get_v_scroll_bar() # 滚动条低对比，但保证可发现、可拖动。
	bar.custom_minimum_size.x = 10
	bar.add_theme_stylebox_override("scroll", Style.box(Color("18241e"), Color(0, 0, 0, 0), 5))
	bar.add_theme_stylebox_override("grabber", Style.box(Color("687958"), Color(0, 0, 0, 0), 5))
	bar.add_theme_stylebox_override("grabber_highlight", Style.box(Style.GOLD, Color(0, 0, 0, 0), 5))
	bar.add_theme_stylebox_override("grabber_pressed", Style.box(Style.GOLD, Color(0, 0, 0, 0), 5))
	bar.value_changed.connect(_scroll_hint)
	resized.connect(_fit_columns)
	_fit_columns()

## 更新 [param offers] 的卡片；[param selected_id] 为选中商品，[param locked] 决定交互权限。
func render(offers: Array[Dictionary], selected_id: String, locked: bool) -> void:
	if locked:
		_hide_focus_hint()
	var incoming: Array[String] = [] # 以目录顺序组织节点，不按标题或价格重新排序。
	for offer: Dictionary in offers: # 展示层只消费报价，不读取存档。
		incoming.append(str(offer.id))
	for id: String in _cards.keys(): # 先移除过期节点，余额更新不会进入这个分支。
		if not incoming.has(id):
			if _hint_card == _cards[id]:
				_hide_focus_hint()
			_grid.remove_child(_cards[id])
			_cards[id].queue_free()
			_cards.erase(id)
	for index: int in offers.size(): # 新增任何数量商品都只创建对应卡片。
		var offer: Dictionary = offers[index] # 当前卡片的只读报价。
		var id: String = str(offer.id) # 唯一节点身份不使用数组下标。
		if not _cards.has(id):
			var card := ProductCard.new() # 网格负责位置，卡片负责内部构图。
			_grid.add_child(card)
			card.configure(offer)
			card.pressed.connect(_select.bind(id))
			card.focus_entered.connect(_show_focus_hint.bind(card))
			card.focus_exited.connect(_hide_focus_hint)
			card.mouse_entered.connect(_hide_focus_hint)
			_cards[id] = card
		_grid.move_child(_cards[id], index)
		_cards[id].update_offer(offer, id == selected_id, locked)
	if incoming != _ids:
		_ids = incoming
		_scroll.scroll_vertical = 0
		if is_instance_valid(_transition):
			_transition.kill()
		_grid.modulate.a = 0.0
		_transition = create_tween()
		_transition.tween_property(_grid, "modulate:a", 1.0, 0.20).set_trans(Tween.TRANS_SINE)
	_fit_columns()

## 按可容纳宽度计算行数，再均衡分列；四件商品在宽屏货架上为居中的两行两列。
func _fit_columns() -> void:
	if _grid == null:
		return
	var capacity: int = maxi(1, floori((size.x - SCROLL_GUTTER + GAP) / (ProductCard.CARD_SIZE.x + GAP))) # 一行最多能放下的卡片。
	var rows: int = maxi(1, ceili(float(_ids.size()) / capacity)) # 宽度不足时仍保持最少行数。
	_grid.columns = maxi(1, ceili(float(_ids.size()) / rows))

## 点击 [param id] 仅发出选择意图。
func _select(id: String) -> void:
	selected.emit(id)

## 非鼠标点击的聚焦 [param card] 显示相同完整规则，键盘和手柄不依赖悬停。
func _show_focus_hint(card: Button) -> void:
	_hide_focus_hint()
	if card.disabled or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	_hint_card = card
	_focus_hint = card._make_custom_tooltip(card.tooltip_text) as PanelContainer
	_focus_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_focus_hint)
	_focus_hint.minimum_size_changed.connect(_position_focus_hint)
	_position_focus_hint.call_deferred()

## 焦点提示不抢焦点、不截获按键，离开商品时随节点释放。
func _hide_focus_hint() -> void:
	if is_instance_valid(_focus_hint):
		_focus_hint.hide()
		_focus_hint.queue_free()
	_focus_hint = null
	_hint_card = null

## [param _value] 是滚动偏移；保持焦点提示贴近商品且不越过货架边缘。
func _scroll_hint(_value: float) -> void:
	_position_focus_hint()

## 提示作为滚动区的同级节点绘制，不受卡片网格裁切；以货架坐标定位。
func _position_focus_hint() -> void:
	if not is_instance_valid(_focus_hint) or not is_instance_valid(_hint_card):
		return
	_focus_hint.size = _focus_hint.get_combined_minimum_size()
	var origin: Vector2 = get_global_transform().affine_inverse() * _hint_card.global_position # 适配外层全屏缩放。
	var top: float = origin.y + _hint_card.size.y + 10.0 # 优先显示在商品下方。
	if top + _focus_hint.size.y > size.y:
		top = origin.y - _focus_hint.size.y - 10.0
	_focus_hint.position = Vector2(clampf(origin.x, 0.0, maxf(0.0, size.x - _focus_hint.size.x)), clampf(top, 0.0, maxf(0.0, size.y - _focus_hint.size.y)))
