## Desktop-oriented 11x6 inventory layout, authored from reusable transparent source art.
extends RefCounted
const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")
const DESIGN := Vector2(1840, 950)
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
	Art.panel(canvas, "panels/parchment_ninepatch.png", Vector2(250, 110), Vector2(1562, 806))
	Art.image(canvas, "sidebar/sidebar_wood.png", Vector2(22, 125), Vector2(231, 775))
	Art.panel(canvas, "panels/parchment_ninepatch.png", Vector2(1335, 143), Vector2(454, 757))
	Art.label(canvas, "背包", Vector2(66, 26), Vector2(350, 85), 53, Color("f7e5af"))
	Art.image(canvas, "icons/currency_unified.png", Vector2(1427, 43), Vector2(54, 54))
	var coin: Label = Art.label(canvas, "0", Vector2(1481, 46), Vector2(226, 48), 30, Color("fae6b8"))
	coin.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var close := Art.button(canvas, "controls/close", Vector2(1732, 24), Vector2(82, 82), Callable(owner, "request_close"))
	close.name = "InventoryCloseButton"
	var tabs: Dictionary = {}
	for i in CATEGORIES.size():
		var idx: int = i
		var tab := TextureButton.new()
		tab.position = Vector2(45, 185 + i * 105)
		tab.size = Vector2(199, 85)
		tab.ignore_texture_size = true
		tab.stretch_mode = TextureButton.STRETCH_SCALE
		tab.texture_normal = Art.texture("tabs/tab_normal.png")
		tab.texture_hover = Art.texture("tabs/tab_hover.png")
		tab.texture_pressed = Art.texture("tabs/tab_pressed.png")
		tab.pressed.connect(Callable(owner, "choose_category").bind(CATEGORIES[idx]))
		canvas.add_child(tab)
		Art.image(tab, "icons/" + ICONS[idx] + ".png", Vector2(12, 12), Vector2(58, 58))
		Art.label(tab, CAPTIONS[idx], Vector2(78, 9), Vector2(112, 64), 30)
		tabs[CATEGORIES[idx]] = tab
	Art.label(canvas, "搜索", Vector2(303, 147), Vector2(83, 49), 21)
	Art.image(canvas, "controls/search_field.png", Vector2(386, 151), Vector2(430, 50))
	var search := LineEdit.new()
	search.placeholder_text = "名称 / UID"
	search.position = Vector2(402, 159)
	search.size = Vector2(395, 37)
	search.flat = true
	search.add_theme_font_size_override("font_size", 22)
	search.text_changed.connect(Callable(owner, "search_changed"))
	canvas.add_child(search)
	var sorter := Art.button(canvas, "controls/sort", Vector2(876, 149), Vector2(188, 53), Callable(owner, "cycle_sort"))
	var sort_text: Label = Art.label(canvas, "自定义排序", Vector2(893, 150), Vector2(164, 46), 21)
	Art.label(canvas, "11 × 6", Vector2(1130, 149), Vector2(172, 53), 22)
	var cells := Control.new()
	cells.position = Vector2(281, 219)
	cells.size = Vector2(1020, 635)
	canvas.add_child(cells)
	var previous := Art.button(canvas, "controls/arrow", Vector2(700, 862), Vector2(46, 52), Callable(owner, "change_page").bind(-1))
	previous.flip_h = true
	var page_text := Art.label(canvas, "1 / 1", Vector2(755, 862), Vector2(140, 52), 24)
	page_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Art.button(canvas, "controls/arrow", Vector2(903, 862), Vector2(46, 52), Callable(owner, "change_page").bind(1))
	Art.label(canvas, "物品详情", Vector2(1372, 161), Vector2(365, 66), 34)
	var detail := Control.new()
	detail.position = Vector2(1360, 230)
	detail.size = Vector2(408, 644)
	canvas.add_child(detail)
	return {"canvas": canvas, "coin": coin, "tabs": tabs, "search": search,
		"sort_label": sort_text, "page_label": page_text, "cells": cells,
		"detail": detail, "sort_button": sorter}
