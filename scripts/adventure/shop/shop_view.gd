## 全屏商店表现层：货架独立扩展，标题、价格和操作保持清楚的视觉层级。
extends Control

## 交互意图与稳定商品/分类 ID，由窗口解释。
signal action_requested(action: String, id: String)
## 商店统一字体、颜色和原图解析。
const Style = preload("res://scripts/adventure/shop/shop_skin.gd")
## 分类与商品内容，不包含布局坐标。
const Catalog = preload("res://scripts/adventure/shop/shop_catalog.gd")
## 自动换行和滚动的独立货架。
const Shelf = preload("res://scripts/adventure/shop/shop_shelf.gd")
## 原版戴夫常驻演出。
const Dave = preload("res://scripts/adventure/shop/shop_dave.gd")
## 供窗口驱动原版台词和成交动画。
var dave: Dave
## 玩家余额。
var _coins: Label
## 只有每日分类显示简短补货时间。
var _refresh_time: Label
## 底部当前选中商品，不重复说明正文。
var _selection: Label
## 底部选中图标。
var _selection_icon: TextureRect
## 唯一购买动作。
var _buy: Button
## 固定分类导航，外观独立于普通操作按钮。
var _tabs: Dictionary = {}
## 展示任意数量报价的货架。
var _shelf: Shelf
## 暂时反馈，仅在交易结果或错误发生时显示。
var _notice: Label
## 反馈自动收起，避免常驻说明文字。
var _notice_timer: Timer
## 防止余额刷新重复展示同一反馈。
var _last_notice := ""
## 右侧确认单不遮挡正在询问成交的戴夫。
var _confirmation: Control
## 确认前的焦点，关闭时交还原操作。
var _previous_focus: Control
## 分类下划线的平滑导航标识。
var _tab_marker: Panel
## 最近分类，普通报价更新不重播导航过渡。
var _category := ""
## 分类标识的唯一补间。
var _navigation_motion: Tween
## 确认单入场补间，取消时立即终止。
var _dialog_motion: Tween

## 构建固定框架；商品排布完全交给货架容器。
func _ready() -> void:
	size = Style.DESIGN
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = Theme.new()
	theme.default_font = Style.BODY_FONT
	Style.image(self, preload("res://assets/image/store/Store_Bg_New.png"), Rect2(Vector2.ZERO, size)).stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var wash := ColorRect.new() # 环境退后，让商品原图成为最高饱和度的视觉内容。
	wash.color = Color(0.055, 0.105, 0.075, 0.72)
	wash.size = size
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wash)
	Style.panel(self, Rect2(0, 0, 1440, 94), Color(0.055, 0.09, 0.065, 0.85), Color(0, 0, 0, 0), 0)
	var title: Label = Style.label(self, "戴夫的小店", Rect2(38, 24, 380, 50), 37) # 手写字体只保留在店名，避免所有信息都像标题。
	title.add_theme_font_override("font", Style.FONT)
	Style.label(self, "●", Rect2(1072, 31, 30, 32), 25, Style.GOLD)
	_coins = Style.label(self, "", Rect2(1110, 28, 158, 40), 29, Style.GOLD)
	_coins.add_theme_font_override("font", Style.NUMBER_FONT)
	_coins.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	Style.button(self, "返回", Rect2(1302, 24, 104, 48), _emit.bind("close", ""))
	Style.panel(self, Rect2(366, 110, 1040, 590), Style.SURFACE, Style.LINE, 22)
	for index: int in Catalog.CATEGORIES.size(): # 导航从分类目录生成，不为商品数量增加按钮。
		var category: String = Catalog.CATEGORIES[index] # 当前分类的稳定 ID。
		var tab: Button = Style.button(self, str(Catalog.CATEGORY_NAMES[category]), Rect2(390 + index * 178, 126, 162, 46), _emit.bind("category", category)) # 页签低于商品名和价格的视觉层级。
		tab.add_theme_font_size_override("font_size", 20)
		_tabs[category] = tab
	_tab_marker = Style.panel(self, Rect2(408, 174, 126, 2), Style.GOLD, Color(0, 0, 0, 0), 1)
	_refresh_time = Style.label(self, "00:00 补货", Rect2(1211, 135, 164, 28), 16, Style.MUTED)
	_refresh_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_shelf = Shelf.new()
	_shelf.position = Vector2(390, 190)
	_shelf.size = Vector2(988, 508)
	add_child(_shelf)
	_shelf.selected.connect(_select)
	Style.panel(self, Rect2(366, 716, 1040, 66), Color("203127"), Style.LINE, 18)
	_selection_icon = Style.image(self, null, Rect2(386, 726, 44, 44))
	_selection = Style.label(self, "", Rect2(447, 731, 590, 34), 21)
	_buy = Style.button(self, "购买", Rect2(1114, 724, 278, 50), _emit.bind("buy", ""), true)
	dave = Dave.new()
	add_child(dave)
	_notice = Style.label(self, "", Rect2(668, 73, 600, 30), 17, Style.CREAM)
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_notice.hide()
	_notice_timer = Timer.new()
	_notice_timer.one_shot = true
	_notice_timer.wait_time = 3.5
	_notice_timer.timeout.connect(_notice.hide)
	add_child(_notice_timer)

## 用 [param model] 的只读快照更新内容；同分类增减商品也会由货架自动重排。
func render(model: Dictionary) -> void:
	_coins.text = Style.money(int(model.coins))
	var locked: bool = bool(model.locked) # 进场、确认或发疯期间锁定选购。
	for category: String in _tabs: # 页签用轻色块标识当前分类，不套厚边框。
		var tab: Button = _tabs[category] # 保留同一节点以维持键盘焦点。
		var active: bool = category == str(model.category) # 表现判断不修改页面状态。
		var normal: StyleBoxFlat = Style.box(Color("40583b") if active else Style.SURFACE, Color("7d9763") if active else Color(0, 0, 0, 0), 11) # 非激活页签融入货架。
		normal.shadow_size = 0
		Style.set_button_disabled(tab, locked)
		tab.add_theme_stylebox_override("normal", normal)
		tab.add_theme_stylebox_override("disabled", normal)
		tab.add_theme_color_override("font_color", Style.CREAM if active else Style.MUTED)
		tab.add_theme_color_override("font_disabled_color", Style.CREAM if active else Style.MUTED)
	_refresh_time.visible = str(model.category) == "daily"
	if _category != str(model.category):
		_category = str(model.category)
		if is_instance_valid(_navigation_motion):
			_navigation_motion.kill()
		_navigation_motion = create_tween()
		_navigation_motion.tween_property(_tab_marker, "position:x", 408.0 + Catalog.CATEGORIES.find(_category) * 178.0, 0.20).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_shelf.render(model.offers, str(model.selected), locked)
	var selected: Dictionary = model.offer # 选购条只显示当前选择与实际购买动作。
	Style.set_button_disabled(_buy, locked or selected.is_empty() or not bool(selected.get("can_buy", false)))
	_selection.text = str(selected.get("title", ""))
	_selection_icon.texture = Style.product_texture(selected) if not selected.is_empty() else null
	_buy.text = str(selected.message) if not selected.is_empty() and not selected.can_buy else ("购买  ·  " + Style.money(int(selected.get("price", 0))))
	_show_notice(str(model.notice))

## 展示 [param message] 的短暂结果；空闲时不显示教程或口号。
func _show_notice(message: String) -> void:
	if message == _last_notice:
		return
	_last_notice = message
	_notice.text = message
	_notice.visible = not message.is_empty()
	if _notice.visible:
		_notice_timer.start()
	else:
		_notice_timer.stop()

## 商品 [param id] 的选择只发送意图。
func _select(id: String) -> void:
	_emit("select", id)

## 确认 [param offer]：只呈现商品、价格与两个动作；“成交？”由戴夫说。
func show_confirmation(offer: Dictionary) -> void:
	hide_confirmation(false)
	_previous_focus = get_viewport().gui_get_focus_owner()
	_confirmation = Control.new()
	_confirmation.name = "PurchaseConfirmation"
	_confirmation.size = Style.DESIGN
	_confirmation.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_confirmation)
	var shade: Panel = Style.panel(_confirmation, Rect2(366, 110, 1040, 672), Color(0.025, 0.05, 0.035, 0.88), Color(0, 0, 0, 0), 22) # 暗化货架，并沿用外框圆角。
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	Style.panel(_confirmation, Rect2(635, 227, 502, 390), Color("2c3d30"), Style.GOLD, 22)
	Style.image(_confirmation, Style.product_texture(offer), Rect2(808, 247, 156, 140))
	var title: Label = Style.label(_confirmation, str(offer.title), Rect2(663, 400, 446, 38), 25) # 确认单名称只出现一次。
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var price: Label = Style.label(_confirmation, Style.money(int(offer.price)), Rect2(663, 446, 446, 48), 39, Style.GOLD) # 价格单独成为确认单的强调信息。
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price.add_theme_font_override("font", Style.NUMBER_FONT)
	var cancel: Button = Style.button(_confirmation, "再想想", Rect2(661, 538, 210, 53), _emit.bind("cancel", "")) # 确认单的键盘焦点封闭循环。
	var confirm: Button = Style.button(_confirmation, "成交", Rect2(895, 538, 216, 53), _emit.bind("confirm", ""), true) # 唯一提交按钮。
	cancel.focus_next = cancel.get_path_to(confirm)
	cancel.focus_previous = cancel.get_path_to(confirm)
	confirm.focus_next = confirm.get_path_to(cancel)
	confirm.focus_previous = confirm.get_path_to(cancel)
	cancel.focus_neighbor_left = cancel.get_path_to(confirm)
	cancel.focus_neighbor_right = cancel.get_path_to(confirm)
	confirm.focus_neighbor_left = confirm.get_path_to(cancel)
	confirm.focus_neighbor_right = confirm.get_path_to(cancel)
	cancel.focus_neighbor_top = NodePath(".")
	cancel.focus_neighbor_bottom = NodePath(".")
	confirm.focus_neighbor_top = NodePath(".")
	confirm.focus_neighbor_bottom = NodePath(".")
	confirm.grab_focus()
	_confirmation.modulate.a = 0.0
	_dialog_motion = create_tween()
	_dialog_motion.tween_property(_confirmation, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_SINE)

## 移除确认单；[param restore_focus] 为 true 时延后到按钮解锁后恢复焦点。
func hide_confirmation(restore_focus: bool = true) -> void:
	if is_instance_valid(_dialog_motion):
		_dialog_motion.kill()
	if is_instance_valid(_confirmation):
		var departing: Control = _confirmation # 旧面板独立退场，不会由下一张确认单的补间持有。
		_disable_buttons(departing)
		var fade: Tween = departing.create_tween() # 与旧面板绑定，切场景时不会留下回调。
		fade.tween_property(departing, "modulate:a", 0.0, 0.10)
		fade.tween_callback(departing.queue_free)
	_confirmation = null
	if restore_focus:
		_restore_focus.call_deferred()
	else:
		_previous_focus = null

## 模型更新恢复购买按钮之后再交还焦点，避免把焦点给仍被禁用的控件。
func _restore_focus() -> void:
	if is_instance_valid(_previous_focus) and _previous_focus.is_visible_in_tree():
		_previous_focus.grab_focus()
	_previous_focus = null

## 退场中的 [param node] 不再接受确认，防止淡出期的重复提交。
func _disable_buttons(node: Node) -> void:
	if node is Button:
		Style.set_button_disabled(node, true)
	for child: Node in node.get_children(): # 遍历只影响即将释放的旧确认单。
		_disable_buttons(child)

## 派发 [param action] 与 [param id]，表现层不改动资产。
func _emit(action: String, id: String) -> void:
	action_requested.emit(action, id)
