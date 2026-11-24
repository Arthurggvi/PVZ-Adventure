## Research shared panel renderer. All input records are service-owned read-only snapshots.
extends RefCounted
const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")
const ItemArt = preload("res://scripts/adventure/ui/inventory_item_art.gd")
const Names = preload("res://scripts/adventure/ui/inventory_data.gd")
const ModeView = preload("res://scripts/adventure/ui/research_mode_view.gd")
## 信息区文字相对于面板边界布局。
const Layout = preload("res://scripts/adventure/ui/research_panel_skin.gd")
## 研究槽位和选择区使用同一套背包格。
const Slots = preload("res://scripts/adventure/ui/research_slot_view.gd")
## 选择区使用的临时槽位状态。
const Picker = preload("res://scripts/adventure/ui/research_slot_picker.gd")

## 在 [param target] 中刷新 [param mode] 的选择、工作、信息区。[param owner] 接收交互。
## [param options] 是过滤后的展示行，[param preview] 为服务报价，[param picker] 与 [param inventory] 用于显示槽位。
## [param coin_balance] 为用于价格提示的当前金币余额。
static func render(owner: Control, target: Control, mode: String,
		options: Array[Dictionary], preview: Dictionary, picker: Picker,
		inventory: AdventureInventoryService, coin_balance: int) -> void:
	for child: Node in target.get_children():
		target.remove_child(child)
		child.queue_free()
	match mode:
		"craft":
			_craft(target, preview, coin_balance)
		"upgrade":
			ModeView.upgrade(owner, target, preview, picker, inventory, coin_balance)
		"promotion":
			ModeView.promotion(owner, target, preview, picker, inventory, coin_balance)
	# 强化主卡属性排在可见候选卡面之前，避免详情等完整候选网格装配。
	Slots.choices(owner, target, options, picker)

## 在 [param parent] 显示 [param preview] 的产物和材料。产物居于上排，材料按固定位置放在下排。
## 右侧显示配方卷轴用量及金币费用，[param coin_balance] 不足时价格标红。
static func _craft(parent: Control, preview: Dictionary, coin_balance: int) -> void:
	var slots: Array = preview.get("slots", []) # 材料与库存状态由合成报价提供。
	var top_bounds: Rect2 = Slots.work_cell(1, 2, 0) # 上排跨工作区全宽，产物独立居中。
	var result_size: Vector2 = Slots.work_cell(2, 1, 1).size * 0.5 # 以上一版右侧预览的尺寸为基准，宽高各缩小一半。
	var plant_type: int = int(preview.get("plant_type", 0)) # 由配方指定的产物物种。
	ModeView.plant(parent, plant_type, top_bounds.get_center() - result_size * 0.5, result_size)
	for index: int in range(3):
		var slot: Dictionary = slots[index] if index < slots.size() else {} # 配方缺少对应材料时仍绘制空槽。
		_craft_material(parent, slot, Slots.work_cell(3, 2, 3 + index, Slots.COMPACT_SLOT_SCALE))
	if not preview.has("plant_type"):
		return
	var info_bounds: Rect2 = Layout.INFO_REGION.grow(-42.0) # 为名称、描述、卷轴和价格预留统一内边距。
	Art.label(parent, Names.plant_name(plant_type), info_bounds.position, Vector2(info_bounds.size.x, 52), 34)
	var description: Label = Art.label(parent, Names.plant_description(plant_type),
		info_bounds.position + Vector2(0, 72), Vector2(info_bounds.size.x, info_bounds.size.y - 184), 26) # 与背包共用植物描述。
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	var scroll: Dictionary = preview.scroll # 标明当前持有量和本次合成消耗量。
	Art.label(parent, "配方卷轴  %d / %d" % [scroll.owned, scroll.required],
		Vector2(info_bounds.position.x, info_bounds.end.y - 100), Vector2(info_bounds.size.x, 40), 26)
	ModeView.price(parent, info_bounds, int(preview.fee), coin_balance)

## 将 [param slot] 的素材等比放入 [param parent] 的 [param bounds]，数量显示在格内，名称放入悬停提示。
static func _craft_material(parent: Control, slot: Dictionary, bounds: Rect2) -> void:
	var side: float = minf(bounds.size.x, bounds.size.y) # 用缩放后的区域短边绘制方槽。
	var size := Vector2.ONE * side # 整个格子的绘制尺寸。
	var position: Vector2 = bounds.get_center() - size * 0.5 # 在工作槽范围内居中。
	if slot.is_empty():
		Art.image(parent, "slots/item_slot_normal.png", position, size)
		return
	var id: String = str(slot.id) # 用道具目录识别材料与图标。
	var backing: String = ItemArt.backing_uri(id) # 与背包共用材料分类底图。
	if backing.is_empty():
		Art.image(parent, "slots/item_slot_normal.png", position, size)
	else:
		# 补偿分类底图的透明留边和圆角，让图案覆盖槽框内沿。
		Art.image(parent, backing, position - size * 0.02, size * 1.04)
	var owned: int = int(slot.owned) # 当前持有数。
	var required: int = int(slot.required) # 本次合成所需数量。
	var enough: bool = owned >= required # 材料不足时降低图案亮度。
	var sprite: TextureRect = Art.image(parent, ItemArt.icon_uri(id), position + size * 0.16, size * 0.68) # 图标保持原比例。
	if not enough:
		sprite.modulate = Color(0.38, 0.38, 0.38, 0.68)
	var frame: TextureRect = Art.slot_frame(parent, position, size) # 原版边框压在底图和图标上层。
	frame.mouse_filter = Control.MOUSE_FILTER_PASS
	frame.tooltip_text = str(ItemRegistry.get_item_definition(id).get("name", id))
	Art.count_badge(parent, "%d / %d" % [owned, required], position + size - Vector2(12, 12),
		Color("fff4d6") if enough else Color("ffb8a2"), 22)
