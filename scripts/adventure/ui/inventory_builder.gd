## Desktop-oriented 11x6 inventory layout, authored from reusable transparent source art.
extends RefCounted
const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")
const DESIGN := Vector2(1840, 950)
## 物品网格与详情区的内部上下边界，保留顶部控件和外框内沿。
const BODY_BOUNDS := Rect2(22, 112, 1796, 814)
## 分类栏原图顶部包含叶片和透明区域；补偿石沿与右侧面板可见上沿之间的偏差。
const SIDEBAR_TOP_OFFSET := 36.0
## 分类栏上移并向上延展，保持底部与右侧面板对齐。
const SIDEBAR_BOUNDS := Rect2(BODY_BOUNDS.position - Vector2(0, SIDEBAR_TOP_OFFSET), Vector2(246, BODY_BOUNDS.size.y + SIDEBAR_TOP_OFFSET))
## 原版格子的实际占用尺寸，包含 11 列、6 行及其间距。
const GRID_NATIVE_SIZE := Vector2(1006, 611)
## 搜索栏与翻页栏之间的网格可用区域。
const GRID_BOUNDS := Rect2(276, 204, 1038, 654)
## 详情原始坐标系及扩大后的可用区域，内容统一等比适配。
const DETAIL_NATIVE_SIZE := Vector2(408, 644)
## 详情标题下方至面板底沿的内容区域。
const DETAIL_BOUNDS := Rect2(1350, 202, 448, 700)
## 详情预览图使用的最大区域，不侵占描述和操作按钮。
const DETAIL_PREVIEW_BOUNDS := Rect2(24, 76, 360, 220)
const CATEGORIES := ["plants", "recipes", "materials", "items"]
const CAPTIONS := ["植物", "配方", "材料", "道具"]
const ICONS := ["category_plants", "category_recipes", "category_materials", "category_items"]

static func build(owner: Control) -> Dictionary:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.05, 0.07, 0.06, 0.62)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	owner.add_child(backdrop)
	var canvas := Control.new()
	canvas.size = DESIGN
	canvas.pivot_offset = DESIGN * 0.5
	canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	owner.add_child(canvas)
	Art.panel(canvas, "panels/outer_frame_ninepatch.png", Vector2.ZERO, DESIGN, 40)
	Art.panel(canvas, "panels/parchment_ninepatch.png", Vector2(250, BODY_BOUNDS.position.y), Vector2(1568, BODY_BOUNDS.size.y))
	# 只延展中间木板，保留顶部装饰与底部石块，不再因等比适配而缩短分类栏。
	var sidebar: NinePatchRect = Art.panel(canvas, "sidebar/sidebar_wood.png", SIDEBAR_BOUNDS.position, SIDEBAR_BOUNDS.size, 32) # 填满左侧可用高度。
	sidebar.patch_margin_top = 140
	sidebar.patch_margin_bottom = 128
	Art.panel(canvas, "panels/parchment_ninepatch.png", Vector2(1330, BODY_BOUNDS.position.y), Vector2(488, BODY_BOUNDS.size.y))
	var coin: Label = Art.label(canvas, "0", Vector2(1481, 46), Vector2(226, 48), 30, Color("fae6b8"))
	coin.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var close := Art.button(canvas, "controls/close", Vector2(1732, 24), Vector2(82, 82), Callable(owner, "request_close"))
	close.name = "InventoryCloseButton"
	var tabs: Dictionary = {}
	for i in CATEGORIES.size():
		var idx: int = i
		var tab := TextureButton.new()
		tab.size = Vector2(220, 220.0 * 118.0 / 320.0)
		tab.position = Vector2(35, SIDEBAR_BOUNDS.position.y + 142.0 + i * (tab.size.y + 18.0)) # 从顶部按固定间距顺序排列。
		tab.ignore_texture_size = true
		tab.stretch_mode = TextureButton.STRETCH_SCALE
		tab.texture_normal = Art.texture("tabs/tab_normal.png")
		tab.texture_hover = Art.texture("tabs/tab_hover.png")
		tab.texture_pressed = Art.texture("tabs/tab_pressed.png")
		tab.pressed.connect(Callable(owner, "choose_category").bind(CATEGORIES[idx]))
		canvas.add_child(tab)
		Art.image(tab, "icons/" + ICONS[idx] + ".png", Vector2(12, (tab.size.y - 58.0) * 0.5), Vector2(58, 58))
		Art.label(tab, CAPTIONS[idx], Vector2(78, (tab.size.y - 64.0) * 0.5), Vector2(130, 64), 30)
		tabs[CATEGORIES[idx]] = tab
	Art.label(canvas, "搜索", Vector2(283, 132), Vector2(83, 49), 21)
	Art.panel(canvas, "controls/search_field.png", Vector2(366, 136), Vector2(430, 50), 12)
	var search := LineEdit.new()
	search.placeholder_text = "名称 / UID"
	search.position = Vector2(382, 144)
	search.size = Vector2(395, 37)
	search.flat = true
	search.add_theme_font_size_override("font_size", 22)
	search.text_changed.connect(Callable(owner, "search_changed"))
	canvas.add_child(search)
	var cells := Control.new()
	canvas.add_child(cells)
	fit_content(cells, GRID_NATIVE_SIZE, GRID_BOUNDS)
	var previous := Art.button(canvas, "controls/arrow", Vector2(670, 866), Vector2(46, 52), Callable(owner, "change_page").bind(-1))
	previous.flip_h = true
	var page_text := Art.label(canvas, "1 / 1", Vector2(725, 866), Vector2(140, 52), 24)
	page_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Art.button(canvas, "controls/arrow", Vector2(873, 866), Vector2(46, 52), Callable(owner, "change_page").bind(1))
	Art.label(canvas, "物品详情", Vector2(1360, 126), Vector2(428, 66), 34)
	var detail := Control.new()
	canvas.add_child(detail)
	fit_content(detail, DETAIL_NATIVE_SIZE, DETAIL_BOUNDS)
	return {"canvas": canvas, "coin": coin, "tabs": tabs, "search": search,
		"page_label": page_text, "cells": cells, "detail": detail}

## 将 [param node] 按 [param native_size] 的比例最大化放入 [param bounds] 并居中，不改变内部坐标。
static func fit_content(node: Control, native_size: Vector2, bounds: Rect2) -> void:
	var factor: float = minf(bounds.size.x / native_size.x, bounds.size.y / native_size.y) # 统一缩放，防止卡牌、图标或文字变形。
	node.size = native_size
	node.pivot_offset = Vector2.ZERO
	node.scale = Vector2.ONE * factor
	node.position = bounds.position + (bounds.size - native_size * factor) * 0.5
