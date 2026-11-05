## Shared modal window driven by the authoritative adventure inventory and UID order.
extends Control
class_name AdventureInventoryWindow
signal closed
const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")
const Data = preload("res://scripts/adventure/ui/inventory_data.gd")
const Builder = preload("res://scripts/adventure/ui/inventory_builder.gd")
const Tile = preload("res://scripts/adventure/ui/inventory_tile.gd")
const ItemArt = preload("res://scripts/adventure/ui/inventory_item_art.gd")
const PromotionVisual = preload("res://scripts/adventure/ui/promotion_book_visual.gd")
## 只负责素材界面与数量确认，不操作玩家资产。
const InventoryDialog = preload("res://scripts/adventure/ui/inventory_dialog.gd")
## 集中处理移除、保存与失败回滚，界面不再内联资产修改。
const DiscardAction = preload("res://scripts/adventure/inventory_discard_action.gd")
const PAGE_SIZE := 66
var category := "plants"
var search := ""
var sort_mode := 0
var page := 0
var selected: Dictionary = {}
var ui: Dictionary = {}
var closing := false
var _anim: Tween
## 当前唯一的确认或提示弹窗。
var _dialog: InventoryDialog
## 打开背包时的玩家状态引用，用于拒绝跨档或重载后的旧界面请求。
var _opened_state: AdventureState
## 打开背包时的玩家名，不写入存档。
var _opened_profile: String
func _ready() -> void:
	_opened_state = Global.global_game_state.adventure_state
	_opened_profile = Global.user_manager.curr_user_name
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
		tile.setup(entry, position_index, category == "plants" and sort_mode == 0 and search.is_empty(), category == "plants", _row_key(entry) == _row_key(selected) and not selected.is_empty())
		tile.chosen.connect(_select)
		tile.reorder_requested.connect(_reorder)
	if not selected.is_empty():
		var selected_key: String = _row_key(selected) # 用当前库存刷新所选行，避免部分丢弃后沿用旧数量。
		selected = {}
		for row: Dictionary in rows:
			if _row_key(row) == selected_key:
				selected = row.duplicate(true)
				break
	if selected.is_empty() and not rows.is_empty():
		selected = rows[0].duplicate(true)
	_update_tile_selection()
	_render_detail()

func _row_key(value: Dictionary) -> String:
	return str(value.get("uid", value.get("id", "")))

func _update_tile_selection() -> void:
	var key: String = _row_key(selected)
	for node: Node in ui.cells.get_children():
		if node is Control and node.has_method("set_active"):
			node.set_active(not key.is_empty() and _row_key(node.record) == key)

func _select(record: Dictionary) -> void:
	selected = record.duplicate(true)
	SoundManager.play_other_SFX(&"tap")
	_update_tile_selection()
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
	var preview_bounds: Rect2 = Builder.DETAIL_PREVIEW_BOUNDS # 所有分类共用的等比预览区域。
	var description_top: float = preview_bounds.end.y + 18.0 # 紧接预览图显示描述；已转职时为其文字留出空间。
	if str(selected.get("kind", "")) == "plant":
		var reference := ResourceCardReference.create(ResourceCardReference.CardType.Plant, int(selected["plant_type"]))
		var card: Card = AllCards.create_card(reference, Card.CardContext.Catalog)
		if card != null:
			card.plant_spawn_profile = AdventureBattleAdapter.profile_for(selected)
			# 详情使用所选卡 UID 的真实星级，展示角标不改变卡牌数据。
			root.add_child(card)
			card.visible = true
			Builder.fit_content(card, card.get_combined_minimum_size(), preview_bounds)
			card.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for field: String in PlantCardInstance.PROMOTION_FIELDS: # Show only actual irreversible promotion choices.
			var promotion: String = str(selected.get(field, "")).strip_edges() # 当前卡的实际转职值。
			if not promotion.is_empty():
				Art.label(root, "%s  %s" % ["第%d次转职" % (PlantCardInstance.PROMOTION_FIELDS.find(field) + 1), promotion], Vector2(38, description_top), Vector2(338, 35), 21)
				description_top += 35.0
	else:
		# 道具底图、图标与配方组件共用预览中心，保持各组件原始长宽比。
		var preview_center: Vector2 = preview_bounds.get_center()
		var backing_size := Vector2.ONE * preview_bounds.size.y
		if str(selected.get("category", "")) == "promotion_book":
			PromotionVisual.draw(root, str(selected["id"]),
				Rect2(preview_center - backing_size * 0.5, backing_size))
		else:
			var backing: String = Data.item_backing(selected)
			if not backing.is_empty():
				Art.image(root, backing, preview_center - backing_size * 0.5, backing_size)
			var icon: String = Data.item_icon(selected)
			var is_recipe: bool = str(selected.get("category", "")) == "recipe"
			var icon_size: Vector2 = backing_size if is_recipe else backing_size * (170.0 / 200.0)
			if not icon.is_empty():
				Art.image(root, icon, preview_center - icon_size * 0.5, icon_size)
			if is_recipe:
				var recipe_scale: float = icon_size.y / 170.0
				ItemArt.add_recipe_portrait(root, int(selected.get("plant_type", 0)), preview_center, 1.15 * recipe_scale)
				var wax: String = ItemArt.recipe_overlay_uri(str(selected["id"]))
				if not wax.is_empty():
					Art.image(root, wax, preview_center + Vector2(29, 35) * recipe_scale, Vector2(48, 48) * recipe_scale)
	_render_description(root, description_top)
	var discard: Button = Art.action_button(root, "丢弃", "buttons/action_danger", Vector2((root.size.x - 277.0) * 0.5, root.size.y - 77.0), Vector2(277, 65), _confirm_discard) # 所有分类共用一个素材按钮。
	discard.disabled = not _is_current_profile() or (str(selected.get("kind", "")) == "plant" and _opened_state.cards.size() <= 1)

## 在 [param root] 的 [param top] 处绘制唯一描述框；空描述保留空框，不显示字段标题或占位说明。
func _render_description(root: Control, top: float) -> void:
	var bottom: float = root.size.y - 65.0 - 12.0 - 18.0 # 所有分类为统一丢弃按钮留出空间。
	var box_size := Vector2(367, bottom - top) # 填满预览下方剩余空间。
	var box: NinePatchRect = Art.panel(root, "panels/parchment_ninepatch.png", Vector2(24, top), box_size, 18) # 沿用背包的羊皮纸方框样式。
	var description: Label = Art.label(box, str(selected.get("description", "")), Vector2(18, 14), box_size - Vector2(36, 28), 22) # 描述只读展示，不改变卡实例或道具定义。
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.vertical_alignment = VERTICAL_ALIGNMENT_TOP

## 确认界面使用所选行的独立快照；只读取当前数量，不提前扣除。
func _confirm_discard() -> void:
	if selected.is_empty() or is_instance_valid(_dialog):
		return
	if not _is_current_profile():
		_show_message("玩家状态已变更，请关闭并重新打开背包。")
		return
	var record: Dictionary = selected.duplicate(true) # 固定确认对象，回调不依赖后续选择状态。
	var is_plant: bool = str(record.get("kind", "")) == "plant" # 单卡与堆叠物品分别给出数量上限。
	var limit: int = 1 if is_plant else Global.adventure_inventory.get_item_count(str(record.get("id", ""))) # 不使用界面缓存数量。
	if is_plant and _opened_state.cards.size() <= 1:
		_show_message("至少需要保留一张植物卡。")
		return
	if limit < 1:
		_show_message("物品已不存在，请重新选择。")
		_render()
		return
	var prompt: String = "确定丢弃这张植物卡？" if is_plant else ("请选择要丢弃的数量。" if limit > 1 else "确定丢弃这件物品？") # 只有堆叠数量大于一才要求输入。
	var message: String = "%s\n%s\n丢弃后无法恢复。" % [record.get("title", ""), prompt] # 不展示内部 UID 或开发说明。
	var dialog: InventoryDialog = _open_dialog("丢弃", message, limit) # 弹窗仅派发确认，不直接修改状态。
	dialog.confirmed.connect(_discard.bind(record))

## [param quantity] 来自弹窗，[param record] 是打开确认时的快照；执行前再次核对当前玩家。
func _discard(quantity: int, record: Dictionary) -> void:
	if closing or not _is_current_profile():
		_show_message("玩家状态已变更，本次丢弃已取消。")
		return
	var error: String = DiscardAction.execute(Global.adventure_inventory, _opened_state, record, quantity, Global.save_service.save_now) # 同步操作及保存，失败由操作对象回滚。
	if error.is_empty():
		SoundManager.play_other_SFX(&"tap")
	else:
		_show_message(error)
	_render()

## 只允许本窗口打开时的玩家状态继续执行写操作，换档或重载后拒绝旧确认。
func _is_current_profile() -> bool:
	return Global.save_service != null and Global.save_service.is_current_profile_loaded() \
		and Global.user_manager.curr_user_name == _opened_profile \
		and Global.global_game_state.adventure_state == _opened_state \
		and Global.adventure_inventory != null and _opened_state != null

## 创建唯一素材弹窗，参数 [param heading]、[param message]、[param limit] 原样交给只读界面。
func _open_dialog(heading: String, message: String, limit: int = 0) -> InventoryDialog:
	var dialog: InventoryDialog = InventoryDialog.new() # 使用独立弹窗，不复用系统灰色默认窗口。
	dialog.setup(heading, message, limit)
	_dialog = dialog
	dialog.closed.connect(_on_dialog_closed.bind(dialog))
	add_child(dialog)
	return dialog

## 仅清理 [param dialog] 对应的引用，不覆盖回调中新打开的提示框。
func _on_dialog_closed(dialog: InventoryDialog) -> void:
	if _dialog == dialog:
		_dialog = null

## [param value] 的错误提示也复用同一素材弹窗，不显示系统默认 AcceptDialog。
func _show_message(value: String) -> void:
	if is_instance_valid(_dialog):
		_dialog.dismiss()
	_open_dialog("提示", value)
