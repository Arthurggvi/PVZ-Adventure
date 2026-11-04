## Shared modal window driven by the authoritative adventure inventory and UID order.
extends Control
class_name AdventureInventoryWindow
signal closed
const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")
const Data = preload("res://scripts/adventure/ui/inventory_data.gd")
const Builder = preload("res://scripts/adventure/ui/inventory_builder.gd")
const Tile = preload("res://scripts/adventure/ui/inventory_tile.gd")
const PAGE_SIZE := 66
var category := "plants"
var search := ""
var sort_mode := 0
var page := 0
var selected: Dictionary = {}
var ui: Dictionary = {}
var closing := false
var _anim: Tween
var _dialog: ConfirmationDialog
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui = Builder.build(self)
	resized.connect(_fit)
	_fit()
	_render()
	modulate.a = 0.0
	ui.canvas.scale *= 0.965
	_anim = create_tween().set_parallel(true)
	_anim.tween_property(self, "modulate:a", 1.0, 0.22)
	_anim.tween_property(ui.canvas, "scale", ui.canvas.scale / 0.965, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	SoundManager.play_other_SFX(&"buttonclick")
func _fit() -> void:
	if ui.is_empty():
		return
	var canvas: Control = ui.canvas
	# Reserve the bottom strip for the shared sliding toolbar in both map scenes.
	var factor := minf(size.x / 2070.0, size.y / 1200.0)
	canvas.scale = Vector2.ONE * factor
	# Account for the centered pivot used by the entrance / exit scale tween.
	canvas.position = Vector2((size.x - Builder.DESIGN.x) * 0.5,
		size.y * 0.015 - (1.0 - factor) * Builder.DESIGN.y * 0.5)
func _input(event: InputEvent) -> void:
	if closing or not visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		if is_instance_valid(_dialog) and _dialog.visible:
			return
		request_close()
		get_viewport().set_input_as_handled()
func request_close() -> void:
	if closing:
		return
	closing = true
	SoundManager.play_other_SFX(&"buttonclick")
	if is_instance_valid(_anim):
		_anim.kill()
	_anim = create_tween().set_parallel(true)
	_anim.tween_property(self, "modulate:a", 0.0, 0.17)
	_anim.tween_property(ui.canvas, "scale", ui.canvas.scale * 0.965, 0.17)
	_anim.chain().tween_callback(func(): closed.emit(); queue_free())
func choose_category(value: String) -> void:
	if category == value:
		return
	category = value
	page = 0
	selected = {}
	SoundManager.play_other_SFX(&"tap")
	_render()
func search_changed(value: String) -> void:
	search = value
	page = 0
	selected = {}
	_render()
func cycle_sort() -> void:
	sort_mode = (sort_mode + 1) % 3
	page = 0
	SoundManager.play_other_SFX(&"bleep")
	_render()
func change_page(delta: int) -> void:
	var total: int = Data.rows(category, search, sort_mode).size()
	page = clampi(page + delta, 0, maxi(0, (total - 1) / PAGE_SIZE))
	SoundManager.play_other_SFX(&"bleep")
	_render()
func _render() -> void:
	if ui.is_empty():
		return
	ui.coin.text = "$" + GlobalUtils.format_number_with_commas(Global.global_game_state.coin_value)
	for key: String in ui.tabs:
		var button: TextureButton = ui.tabs[key]
		button.texture_normal = Art.texture("tabs/tab_selected.png" if key == category else "tabs/tab_normal.png")
	ui.sort_label.text = ["自定义排序", "名称排序", "星级排序"][sort_mode]
	var rows: Array[Dictionary] = Data.rows(category, search, sort_mode)
	page = mini(page, maxi(0, (rows.size() - 1) / PAGE_SIZE))
	ui.page_label.text = "%d / %d" % [page + 1, maxi(1, ceili(float(rows.size()) / PAGE_SIZE))]
	var grid: Control = ui.cells
	for child: Node in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	for i in PAGE_SIZE:
		var position_index: int = page * PAGE_SIZE + i
		var entry: Dictionary = rows[position_index] if position_index < rows.size() else {}
		var tile: Control = Tile.new()
		tile.position = Vector2((i % 11) * 92.0, (i / 11) * 103.0)
		grid.add_child(tile)
		tile.setup(entry, position_index, category == "plants" and sort_mode == 0 and search.is_empty())
		tile.chosen.connect(_select)
		tile.reorder_requested.connect(_reorder)
	if selected.is_empty() and not rows.is_empty():
		selected = rows[0].duplicate(true)
	_render_detail()
func _select(record: Dictionary) -> void:
	selected = record.duplicate(true)
	SoundManager.play_other_SFX(&"tap")
	_render_detail()
func _reorder(uid: String, target: int) -> void:
	if category != "plants" or sort_mode != 0 or not search.is_empty():
		return
	var before: Array[String] = Global.adventure_inventory.get_card_order()
	if before.is_empty() or not Global.adventure_inventory.move_card(uid, mini(target, before.size() - 1)):
		return
	if not Global.save_service.save_now():
		Global.adventure_inventory.set_card_order(before)
		_show_message("排列保存失败，已恢复原顺序。")
	else:
		SoundManager.play_other_SFX(&"tap")
	_render()
func _render_detail() -> void:
	var root: Control = ui.detail
	for child: Node in root.get_children():
		root.remove_child(child)
		child.queue_free()
	if selected.is_empty():
		Art.label(root, "暂无物品", Vector2(25, 58), Vector2(340, 60), 27)
		return
	Art.label(root, str(selected.get("title", "")), Vector2(24, 12), Vector2(367, 54), 29)
	if str(selected.get("kind", "")) == "plant":
		var reference := ResourceCardReference.create(ResourceCardReference.CardType.Plant, int(selected["plant_type"]))
		var card: Card = AllCards.create_card(reference, Card.CardContext.Catalog)
		if card != null:
			card.battle_card_data = selected.duplicate(true)
			root.add_child(card)
			card.visible = true
			card.position = Vector2(138, 95)
			card.scale = Vector2(2.35, 2.35)
			card.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		Art.label(root, "星级  ★%s" % selected.get("stars", 1), Vector2(38, 290), Vector2(325, 46), 28)
		Art.label(root, "身份  %s" % selected.get("uid", ""), Vector2(38, 343), Vector2(334, 43), 23)
		Art.label(root, "转职一  %s" % str(("未转职" if str(selected.get("promotion_1", "")).is_empty() else str(selected.get("promotion_1")))), Vector2(38, 403), Vector2(338, 35), 21)
		Art.label(root, "转职二  %s" % str(("未转职" if str(selected.get("promotion_2", "")).is_empty() else str(selected.get("promotion_2")))), Vector2(38, 447), Vector2(338, 35), 21)
		var discard: Button = Button.new()
		discard.text = "丢弃植物…"
		discard.position = Vector2(68, 540)
		discard.size = Vector2(277, 65)
		discard.disabled = Global.adventure_inventory.get_card_order().size() <= 1
		discard.pressed.connect(_confirm_discard)
		root.add_child(discard)
	else:
		Art.image(root, Data.item_icon(selected), Vector2(104, 85), Vector2(182, 170))
		Art.label(root, "持有数量  ×%d" % int(selected.get("qty", 0)), Vector2(31, 294), Vector2(346, 55), 28)
		Art.label(root, "使用与消耗功能将在下一轮开放", Vector2(24, 420), Vector2(366, 68), 19)
func _confirm_discard() -> void:
	var uid: String = str(selected.get("uid", ""))
	if uid.is_empty() or Global.adventure_inventory.get_card_order().size() <= 1:
		return
	_dialog = ConfirmationDialog.new()
	_dialog.title = "确认永久丢弃"
	_dialog.dialog_text = "%s\n%s · ★%s\n此操作将永久删除这张独立植物卡及其出战引用。" % [selected.get("title", ""), uid, selected.get("stars", 1)]
	_dialog.confirmed.connect(_discard.bind(uid))
	_dialog.confirmed.connect(_dialog.queue_free)
	_dialog.canceled.connect(func(): _dialog.queue_free())
	add_child(_dialog)
	_dialog.popup_centered(Vector2i(600, 220))
func _discard(uid: String) -> void:
	var state: AdventureState = Global.global_game_state.adventure_state
	if state.cards.size() <= 1 or not state.cards.has(uid):
		return
	var old_card: PlantCardInstance = state.cards[uid]
	var old_order: Array[String] = state.card_order_uids.duplicate()
	var old_deck: Array[String] = state.selected_card_uids.duplicate()
	if not Global.adventure_inventory.remove_card(uid):
		return
	if not Global.save_service.save_now():
		state.cards[uid] = old_card
		state.card_order_uids = old_order
		state.selected_card_uids = old_deck
		_show_message("丢弃保存失败，卡牌已恢复。")
	else:
		selected = {}
		SoundManager.play_other_SFX(&"tap")
	_render()
func _show_message(value: String) -> void:
	var popup := AcceptDialog.new()
	popup.dialog_text = value
	add_child(popup)
	popup.popup_centered(Vector2i(510, 160))
	popup.confirmed.connect(popup.queue_free)
