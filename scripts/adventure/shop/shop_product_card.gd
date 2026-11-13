## 单张商品卡，负责美术、鼠标反馈与选中展示；不拥有库存或购买权限。
extends Button

## 商店视觉原语。
const Style = preload("res://scripts/adventure/shop/shop_skin.gd")
## 商品身份仅供派发选择意图。
var product_id := ""
## 商品底图和描边，保持跨状态的尺寸稳定。
var _frame: Panel
## 商品图像，用轻微上浮反馈鼠标悬停。
var _art: TextureRect
## 商品图标的静止位置。
var _art_origin := Vector2.ZERO
## 限购、已拥有或当前槽位状态。
var _stock: Label
## 价格标签。
var _price: Label
## 商品卡右上角的选中状态。
var _check: Label
## 当前图标补间，退出卡片时不会留下悬挂回调。
var _motion: Tween

## 根据只读 [param offer] 和 [param rect] 构造一次；后续状态通过 update_offer 更新。
func configure(offer: Dictionary, rect: Rect2) -> void:
	product_id = str(offer.id)
	name = "Product_" + product_id
	position = rect.position
	size = rect.size
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = str(offer.description)
	for state: String in ["normal", "hover", "pressed", "disabled"]: # 根按钮只提供输入，不覆盖素材。
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	add_theme_stylebox_override("focus", Style.box(Color(0, 0, 0, 0), Style.GOLD))
	_frame = Panel.new()
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)
	Style.Art.panel(_frame, "panels/parchment_ninepatch.png", Vector2(4, 4), size - Vector2(8, 8), 22)
	Style.label(self, str(offer.tag), Rect2(20, 15, size.x - 54, 28), 19, Style.GREEN)
	_check = Style.label(self, "✓", Rect2(size.x - 39, 14, 25, 28), 24, Style.GREEN)
	var portrait: bool = bool(offer.get("unique", false)) # 永久时装展示整身立绘，其他商品使用大图标。
	_art = Style.image(self, Style.product_texture(offer, portrait), Rect2(24, 49, size.x - 48, 168))
	_art_origin = _art.position
	var title: Label = Style.label(self, str(offer.title), Rect2(10, 225, size.x - 20, 57), 25) # 长商品名可自然分两行。
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_price = Style.label(self, "", Rect2(8, 288, size.x - 16, 37), 28, Style.INK)
	_price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stock = Style.label(self, "", Rect2(8, 327, size.x - 16, 44), 17, Style.MUTED)
	_stock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mouse_entered.connect(_hover.bind(true))
	mouse_exited.connect(_hover.bind(false))
	update_offer(offer, false, false)

## 用 [param offer] 更新价格与库存；[param selected] 表示选中，[param locked] 锁定成交交互。
func update_offer(offer: Dictionary, selected: bool, locked: bool) -> void:
	disabled = locked
	_check.visible = selected
	_frame.add_theme_stylebox_override("panel", Style.box(Style.GREEN if selected else Color("9d7547"), Style.GOLD if selected else Color("8c673e")))
	_price.text = "售罄" if offer.sold else "%s 金币" % Style.money(int(offer.price))
	_stock.text = str(offer.status)
	_art.modulate = Color("b8ad97") if offer.sold else Color.WHITE
	_stock.add_theme_color_override("font_color", Color("9f4e37") if offer.sold else Style.MUTED)
	set_meta("selected", selected)

## [param entering] 控制图标轻微上浮；不改变按钮命中范围。
func _hover(entering: bool) -> void:
	if disabled:
		return
	if is_instance_valid(_motion):
		_motion.kill()
	_motion = create_tween()
	_motion.tween_property(_art, "position", _art_origin + Vector2(0, -5 if entering else 0), 0.14).set_trans(Tween.TRANS_SINE)
