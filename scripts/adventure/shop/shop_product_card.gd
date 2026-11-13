## 固定尺寸商品卡；网格负责排布，商品数量不会改变单卡的信息层级或尺寸。
extends Button

## 字体、颜色和图像来自同一视觉目录。
const Style = preload("res://scripts/adventure/shop/shop_skin.gd")
## 所有分类共用的卡片尺寸；每屏可展示三列两行。
const CARD_SIZE := Vector2(308, 238)
## 唯一商品身份，仅用于选择事件。
var product_id := ""
## 商品图标与悬停动画。
var _art: TextureRect
## 未悬停时的图像位置。
var _art_origin := Vector2.ZERO
## 左下价格不重复打印“金币”单位。
var _price: Label
## 仅显示余量、七天或永久，不重复功能说明。
var _badge: Label
## 文字颜色根据已拥有/售罄状态变化。
var _title: Label
## 当前卡片的柔和图像光晕。
var _accent := Color.WHITE
## 当前选中态只影响表现。
var _selected := false
## 售罄卡仍然可以选中查看详情。
var _sold := false
## 本地悬停动画，不改变布局占位。
var _motion: Tween
## 鼠标与焦点的视觉状态，模型刷新不会重播悬停动画。
var _hovered := false
## 根按钮各状态共用同一独立样式，颜色变化可以连续补间。
var _surface: StyleBoxFlat
## 背景和描边补间与图像动画独立管理。
var _surface_motion: Tween

## 从 [param offer] 构造商品卡；只配置内容，位置由父 GridContainer 管理。
func configure(offer: Dictionary) -> void:
	product_id = str(offer.id)
	name = "Product_" + product_id
	custom_minimum_size = CARD_SIZE
	size = CARD_SIZE
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_accent = Style.product_accent(offer)
	_surface = Style.box(Style.CARD, Style.LINE)
	for state: String in ["normal", "hover", "pressed", "disabled"]: # 由本组件控制连续高亮，原生按钮继续处理命中和按键。
		add_theme_stylebox_override(state, _surface)
	add_theme_stylebox_override("focus", Style.box(Color(0, 0, 0, 0), Style.GOLD))
	_badge = Style.label(self, "", Rect2(190, 12, 102, 26), 15, Style.MUTED)
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_art = Style.image(self, Style.product_texture(offer, bool(offer.get("unique", false))), Rect2(62, 8, 184, 146))
	_art_origin = _art.position
	_title = Style.label(self, str(offer.title), Rect2(20, 154, 268, 32), 22)
	_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_price = Style.label(self, "", Rect2(42, 193, 240, 33), 29, Style.GOLD)
	_price.add_theme_font_override("font", Style.NUMBER_FONT)
	mouse_entered.connect(_hover.bind(true))
	mouse_exited.connect(_hover.bind(false))
	focus_entered.connect(_update_highlight)
	focus_exited.connect(_update_highlight)
	button_down.connect(_press.bind(true))
	button_up.connect(_press.bind(false))
	update_offer(offer, false, false)

## 用 [param offer] 更新内容；[param selected] 表示当前选择，[param locked] 锁定确认或成交期间的交互。
func update_offer(offer: Dictionary, selected: bool, locked: bool) -> void:
	var changed: bool = selected != _selected or bool(offer.sold) != _sold or disabled != locked # 余额刷新只更新文字，不打断正在进行的高亮。
	disabled = locked
	_selected = selected
	_sold = bool(offer.sold)
	if locked:
		_hovered = false
	if changed:
		_update_highlight()
	_price.text = str(offer.message) if _sold else Style.money(int(offer.price))
	_price.add_theme_font_override("font", Style.BODY_FONT if _sold else Style.NUMBER_FONT)
	_price.add_theme_font_size_override("font_size", 20 if _sold else 29)
	_price.add_theme_color_override("font_color", Style.MUTED if _sold else Style.GOLD)
	_title.add_theme_color_override("font_color", Style.MUTED if _sold else Style.CREAM)
	if int(offer.get("daily_limit", 0)) > 0:
		_badge.text = "剩余 %d/%d" % [int(offer.remaining), int(offer.daily_limit)]
	elif str(offer.get("kind", "")) == "slots" and not _sold:
		_badge.text = str(offer.get("status", "")).trim_prefix("当前 ")
	else:
		_badge.text = "永久" if offer.category == "special" else "7天"
	_art.modulate = Color("7c8879") if _sold else Color.WHITE
	tooltip_text = "%s\n%s" % [offer.title, offer.description]
	if offer.category == "permanent":
		tooltip_text += "\n购买起7天有效，在角色页装备。"
	elif int(offer.get("daily_limit", 0)) > 0:
		tooltip_text += "\n每日限购%d个，00:00补货。" % int(offer.daily_limit)
	set_meta("selected", selected)
	queue_redraw()

## 悬停 [param for_text] 时才呈现完整规则；限制宽度，不让长句跨过整个货架。
func _make_custom_tooltip(for_text: String) -> Object:
	var panel := PanelContainer.new() # 系统负责延迟显示、贴边避让与关闭。
	var background: StyleBoxFlat = Style.box(Style.SURFACE, Style.LINE, 10) # 提示沿用商店色板。
	background.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", background)
	var text := Label.new() # 详细文案不进入卡片的固定布局。
	text.text = for_text
	text.custom_minimum_size.x = 300
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_theme_font_override("font", Style.BODY_FONT)
	text.add_theme_font_size_override("font_size", 18)
	text.add_theme_color_override("font_color", Style.CREAM)
	panel.add_child(text)
	return panel

## 绘制图像后方的柔和光晕和价格旁的金币符号，不增加文字标签。
func _draw() -> void:
	for layer: int in range(6, 0, -1): # 低透明同心圆形成不喧宾夺主的光晕。
		draw_circle(Vector2(154, 85), 34.0 + layer * 8.0, Color(_accent, 0.012 if _sold else 0.024))
	if not _sold:
		draw_circle(Vector2(27, 210), 7, Style.GOLD)
		draw_arc(Vector2(27, 210), 4.5, 0.0, TAU, 24, Color("9f783b"), 1.2, true)
	if _selected:
		draw_circle(Vector2(17, 17), 4, Style.GOLD)

## [param entering] 控制原图轻微上浮，命中矩形和网格占位保持不变。
func _hover(entering: bool) -> void:
	if disabled:
		return
	_hovered = entering
	_update_highlight()

## 背景、边线和原图同步过渡；同一卡片永远只有一个正在运行的同类补间。
func _update_highlight() -> void:
	var engaged: bool = not disabled and (_hovered or has_focus()) # 键盘和鼠标获得一致反馈。
	if is_instance_valid(_motion):
		_motion.kill()
	_motion = create_tween()
	_motion.tween_property(_art, "position", _art_origin + Vector2(0, -4 if engaged else 0), 0.16).set_trans(Tween.TRANS_SINE)
	if is_instance_valid(_surface_motion):
		_surface_motion.kill()
	_surface_motion = create_tween().set_parallel(true)
	_surface_motion.tween_property(_surface, "bg_color", Color("3b4f3c") if engaged else (Color("354936") if _selected else Style.CARD), 0.16)
	_surface_motion.tween_property(_surface, "border_color", Style.GOLD if engaged or _selected else Style.LINE, 0.16)

## [param down] 只给图像短促按压反馈，价格与名称不移动。
func _press(down: bool) -> void:
	if is_instance_valid(_motion):
		_motion.kill()
	_motion = create_tween()
	_motion.tween_property(_art, "position", _art_origin + Vector2(0, 1 if down else (-4 if not disabled and (_hovered or has_focus()) else 0)), 0.08)
