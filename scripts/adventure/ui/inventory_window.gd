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
## 道具名称颜色由共享的品质文字样式负责。
const ItemName = preload("res://scripts/adventure/ui/item_name_style.gd")
## 集中处理移除、保存与失败回滚，界面不再内联资产修改。
const DiscardAction = preload("res://scripts/adventure/inventory_discard_action.gd")
const PAGE_SIZE := 66
## 单帧格子装配预算，单位微秒；轻量空格不会再占用固定等待帧。
const BUILD_BUDGET_USEC := 4000
## 所属窗口的首屏资源路径，不预建其他分类或后续页。
const ResourcePaths = preload("res://scripts/adventure/ui/ui_resource_paths.gd")
## 所有资源准备共用同一批次实现。
const ResourceBatch = preload("res://scripts/ui/transitions/resource_load_batch.gd")
## 每次重绘递增，旧页分帧任务不得继续追加格子。
var _render_revision := 0
## 初始内容完成后才向工具栏公开真实窗口。
var _content_ready := false
## 当前页准备期间持有的请求，换页或关闭时移交宿主回收。
var _page_batch: ResourceBatch
## 当前页资源强引用随窗口存在，避免构造时再次读盘。
var _page_resources: Array[Resource] = []
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
## 准备现有皮肤、第一页 UID 卡；身份和排序仍来自原数据服务。
static func get_initial_resource_paths() -> PackedStringArray:
	var paths: PackedStringArray = ResourcePaths.frame() # 本窗口实际使用的公共皮肤。
	paths.append_array(ResourcePaths.skin(PackedStringArray(["sidebar/sidebar_wood.png", "controls/search_field.png",
		"controls/filter_field.png", "icons/search_magnifier.png", "slots/empty_plant_symbol.png",
		"slots/plant_slot_hover_frame.png", "slots/plant_slot_selected_frame.png",
		"slots/item_slot_hover_frame.png", "slots/item_slot_selected_frame.png",
		"icons/category_plants.png", "icons/category_recipes.png", "icons/category_materials.png", "icons/category_items.png"]),
		PackedStringArray(["tabs/tab", "controls/arrow", "slots/plant_slot", "slots/item_slot", "buttons/action_danger"])))
	ResourcePaths.inventory_rows(paths, Data.rows("plants", "", 0).slice(0, PAGE_SIZE))
	return paths

## 首屏所有格子和详情完成后释放入口反馈。
func is_content_ready() -> bool:
	return _content_ready

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
	_render_revision += 1
	_retire_page_batch()
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
	page = clampi(page + delta, 0, maxi(0, floori(float(total - 1) / float(PAGE_SIZE))))
	SoundManager.play_other_SFX(&"bleep")
	_render()
func _render() -> void:
	if ui.is_empty():
		return
	_render_revision += 1
	var revision: int = _render_revision # 重绘身份阻止快速翻页或搜索的旧结果入树。
	_content_ready = false
	_retire_page_batch()
	ui.coin.text = "$" + GlobalUtils.format_number_with_commas(Global.global_game_state.coin_value)
	for key: String in ui.tabs:
		var button: TextureButton = ui.tabs[key]
		button.texture_normal = Art.texture("tabs/tab_selected.png" if key == category else "tabs/tab_normal.png")
	var rows: Array[Dictionary] = Data.rows(category, search, sort_mode)
	page = mini(page, maxi(0, floori(float(rows.size() - 1) / float(PAGE_SIZE))))
	ui.page_label.text = "%d / %d" % [page + 1, maxi(1, ceili(float(rows.size()) / PAGE_SIZE))]
	var grid: Control = ui.cells
	for child: Node in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	var paths := PackedStringArray() # 后续分类同样只准备当前可见页。
	ResourcePaths.inventory_rows(paths, rows.slice(page * PAGE_SIZE, (page + 1) * PAGE_SIZE))
	_page_batch = ResourceBatch.new()
	if _page_batch.start(paths) != OK:
		_retire_page_batch()
		Art.label(grid, "暂时无法加载，请重新选择分类。", Vector2(12, 12), Vector2(900, 60), 24)
		_content_ready = true
		return
	while _page_batch != null and _page_batch.poll() == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
		if revision != _render_revision or closing:
			return
	if revision != _render_revision or _page_batch == null:
		return
	if _page_batch.poll() != ResourceLoader.THREAD_LOAD_LOADED:
		_retire_page_batch()
		Art.label(grid, "暂时无法加载，请重新选择分类。", Vector2(12, 12), Vector2(900, 60), 24)
		_content_ready = true
		return
	_page_resources = _page_batch.resources.duplicate()
	_page_batch = null
	var frame_started: int = Time.get_ticks_usec() # 只累计当前帧实际装配时间，首格立即开始。
	for i in PAGE_SIZE:
		if Time.get_ticks_usec() - frame_started >= BUILD_BUDGET_USEC:
			await get_tree().process_frame
			if revision != _render_revision or closing:
				return
			frame_started = Time.get_ticks_usec()
		var position_index: int = page * PAGE_SIZE + i
		var entry: Dictionary = rows[position_index] if position_index < rows.size() else {}
		var tile: Control = Tile.new()
		tile.position = Vector2((i % 11) * 92.0, floori(float(i) / 11.0) * 103.0)
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
	_content_ready = true

## 关闭或重绘时撤销旧准备；已经发出的请求由工具栏轮询回收。
func _retire_page_batch() -> void:
	if _page_batch != null:
		AdventureToolbar.retire_resource_batch(_page_batch)
		_page_batch = null

## 退出只取消呈现资格，不同步等待线程。
func _exit_tree() -> void:
	_render_revision += 1
	_retire_page_batch()

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
	ItemName.draw(root, str(selected.get("title", "")), str(selected.get("id", "")), Rect2(24, 12, 367, 54), 29)
	var preview_bounds: Rect2 = Builder.DETAIL_PREVIEW_BOUNDS # 所有分类共用的等比预览区域。
	var description_top: float = preview_bounds.end.y + 18.0 # 描述框紧接预览图，不受转职数量影响。
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

## 在 [param root] 的 [param top] 处绘制描述框，植物的已学技能按阶数排列在基础描述之后。
func _render_description(root: Control, top: float) -> void:
	var bottom: float = root.size.y - 65.0 - 12.0 - 18.0 # 所有分类为统一丢弃按钮留出空间。
	var box_size := Vector2(367, bottom - top) # 填满预览下方剩余空间。
	var box: NinePatchRect = Art.panel(root, "panels/parchment_ninepatch.png", Vector2(24, top), box_size, 18) # 沿用背包的羊皮纸方框样式。
	var scroll := ScrollContainer.new() # 说明过长时可滚动，丢弃按钮留在框外。
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	scroll.position = Vector2(18, 14)
	scroll.size = box_size - Vector2(36, 28)
	var content := VBoxContainer.new() # 按文字实际换行高度排列，不使用固定行高。
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)
	var description: String = str(selected.get("description", "")) # 基础描述始终排在最上方。
	if not description.is_empty():
		var description_item_id: String = str(selected.get("id", "")) # 技能书的描述与标题共用实际转职阶数。
		ItemName.draw_description(content, description, description_item_id, Rect2(), 22)
	if str(selected.get("kind", "")) != "plant":
		return
	for field: String in PlantCardInstance.PROMOTION_FIELDS: # 按一转至四转读取实际已学技能。
		var book_id: String = str(selected.get(field, "")) # 用内部 ID 查技能名称和描述，界面只显示可读文本。
		if book_id.is_empty():
			continue
		var skill: Dictionary = AdventurePromotionCatalog.definition(book_id) # 与研究室共用技能定义。
		if not skill.is_empty():
			var caption: String = "%s：%s" % [skill.title, skill.summary] # 整条描述使用同一转职阶数的配色。
			ItemName.draw(content, caption, book_id, Rect2(), 21, true)

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
