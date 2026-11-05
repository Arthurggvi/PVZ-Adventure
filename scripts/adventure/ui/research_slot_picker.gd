## 研究室槽位的界面状态与候选查询。只有研究服务能执行资产操作。
extends RefCounted

## 每种槽位对应一种候选集合。
enum Slot { RECIPE, MAIN_CARD, MATERIAL_CARD, POT, FERTILIZER, PROMOTION_BOOK }

## 复用背包格的展示数据格式。
const Data = preload("res://scripts/adventure/ui/inventory_data.gd")
## 强化槽位数量、候选资格与肥料目录取自现有规则。
const Enhancement = preload("res://scripts/adventure/research/research_enhancement_rules.gd")
## 当前在左侧选择区筛选的槽位。
var active_slot: Slot = Slot.RECIPE
## 当前耗材槽的固定位置，其他槽位使用零。
var active_index: int = 0
## 选中的制作书 ID。
var _recipe_id: String = ""
## 选中的独立主卡 UID。
var _main_uid: String = ""
## 固定位置的耗材槽，空字符串表示空槽。
var _materials: Array[String] = []
## 当前是否填入育苗花盆。
var _use_pot: bool = false
## 当前填入的肥料 ID。
var _fertilizer: String = ""
## 当前填入的转职书 ID。
var _book_id: String = ""

## 初始化固定槽数，使替换或清空某一槽时其他槽位保持原位。
func _init() -> void:
	_materials.resize(Enhancement.MAX_MATERIAL_CARDS)
	_materials.fill("")

## 切换 [param mode] 时重置界面。强化完成可用 [param retained_uid] 保留主卡，消耗槽重新选择。
func reset(mode: String, retained_uid: String = "") -> void:
	active_slot = Slot.RECIPE if mode == "craft" else Slot.MAIN_CARD
	active_index = 0
	_recipe_id = ""
	_main_uid = retained_uid
	_materials.fill("")
	_use_pot = false
	_fertilizer = ""
	_book_id = ""

## 复用 [param mode] 的默认选择行为，当前主选择消失时从 [param primary] 选第一项。
func ensure_primary(mode: String, primary: Array[Dictionary]) -> void:
	var key_field: String = "id" if mode == "craft" else "uid" # 制作书按类型，植物按实例识别。
	var current: String = _recipe_id if mode == "craft" else _main_uid # 当前主选择。
	var first: String = "" # 默认选择第一张可用主卡或制作书。
	for entry: Dictionary in primary:
		var key: String = str(entry[key_field]) # 主选择的真实库存身份。
		if key == current and (mode != "promotion" or meets_promotion_minimum(entry)):
			return
		if first.is_empty() and _is_primary_candidate(mode, entry):
			first = key
	_set_primary(mode, first)

## 按 [param mode] 检查 [param entry] 是否可自动选为主卡。
func _is_primary_candidate(mode: String, entry: Dictionary) -> bool:
	if mode == "promotion":
		return meets_promotion_minimum(entry)
	return mode != "upgrade" or int(entry.get("stars", 0)) < Enhancement.MAX_STARS

## 返回 [param card] 是否达到进入转职工作区的最低星级；各阶要求仍由研究服务校验。
static func meets_promotion_minimum(card: Dictionary) -> bool:
	return int(card.get("stars", 0)) >= AdventurePromotionCatalog.REQUIREMENTS[0]

## 更换 [param mode] 的主选择 [param key]，清除依赖旧主卡的耗材、保护和转职书。
func _set_primary(mode: String, key: String) -> void:
	reset(mode)
	if mode == "craft":
		_recipe_id = key
	else:
		_main_uid = key

## [param slot] 和 [param index] 在 [param mode] 中可以操作时，返回 true。
func can_focus(mode: String, slot: Slot, index: int = 0) -> bool:
	if slot == Slot.RECIPE:
		return mode == "craft"
	if slot == Slot.MAIN_CARD:
		return mode == "upgrade" or mode == "promotion"
	if _main_uid.is_empty():
		return false
	if slot == Slot.PROMOTION_BOOK:
		return mode == "promotion"
	return mode == "upgrade" and (slot in [Slot.POT, Slot.FERTILIZER] \
		or (slot == Slot.MATERIAL_CARD and index >= 0 and index < _materials.size()))

## 将 [param mode] 中合法的 [param slot]、[param index] 设为当前候选来源。
func focus(mode: String, slot: Slot, index: int = 0) -> bool:
	if not can_focus(mode, slot, index):
		return false
	active_slot = slot
	active_index = index
	return true

## 把当前候选 [param row] 放入 [param mode] 下正在选取的槽位。重选主卡自身时保留其余槽位。
func pick(mode: String, row: Dictionary) -> void:
	match active_slot:
		Slot.RECIPE:
			_recipe_id = str(row.id)
		Slot.MAIN_CARD:
			if str(row.uid) != _main_uid:
				_set_primary(mode, str(row.uid))
		Slot.MATERIAL_CARD:
			_materials[active_index] = str(row.uid)
		Slot.POT:
			_use_pot = true
		Slot.FERTILIZER:
			_fertilizer = str(row.id)
		Slot.PROMOTION_BOOK:
			_book_id = str(row.id)

## 清空已聚焦的附加槽。主卡和制作书通过选择其他候选替换。
func clear_active() -> void:
	match active_slot:
		Slot.MATERIAL_CARD:
			_materials[active_index] = ""
		Slot.POT:
			_use_pot = false
		Slot.FERTILIZER:
			_fertilizer = ""
		Slot.PROMOTION_BOOK:
			_book_id = ""

## 返回 [param slot]、[param index] 所选的稳定 ID 或 UID，供候选高亮和填充预览使用。
func key_for(slot: Slot, index: int = 0) -> String:
	match slot:
		Slot.RECIPE: return _recipe_id
		Slot.MAIN_CARD: return _main_uid
		Slot.MATERIAL_CARD: return _materials[index]
		Slot.POT: return "seedling_pot" if _use_pot else ""
		Slot.FERTILIZER: return _fertilizer
		Slot.PROMOTION_BOOK: return _book_id
	return ""

## 返回 [param slot] 是否显示为植物卡格，空槽也保留对应样式。
static func is_plant_slot(slot: Slot) -> bool:
	return slot in [Slot.MAIN_CARD, Slot.MATERIAL_CARD]

## 返回 [param inventory] 中对应 [param slot]、[param index] 的展示行；空槽返回空字典。
func slot_row(inventory: AdventureInventoryService, slot: Slot, index: int = 0) -> Dictionary:
	var key: String = key_for(slot, index) # 按当前实时库存刷新预览。
	if inventory == null or key.is_empty():
		return {}
	if is_plant_slot(slot):
		return Data.plant_row(inventory.get_card(key))
	return Data.item_row(key, inventory.get_item_count(key))

## 基于 [param mode]、[param service] 库存、[param primary] 主选项与 [param preview] 报价筛选候选。
func candidates(mode: String, service: AdventureResearchService, primary: Array[Dictionary], preview: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = [] # 当前网格只持有展示副本。
	if service == null:
		return rows
	match active_slot:
		Slot.RECIPE:
			for recipe: Dictionary in primary:
				_append_owned_item(rows, service.inventory, str(recipe.id))
		Slot.MAIN_CARD:
			for card: Dictionary in primary:
				# 转职保留低星候选供点击时说明原因，但不会自动选中。
				if mode == "promotion" or _is_primary_candidate(mode, card):
					rows.append(Data.plant_row(card))
		Slot.MATERIAL_CARD:
			for card: Dictionary in primary:
				var uid: String = str(card.uid) # 正在替换的槽可保留原卡，其余已填槽不能重复占用。
				if _materials.has(uid) and uid != _materials[active_index]:
					continue
				if Enhancement.validate(service.state, _main_uid, [uid], false, "").is_empty():
					rows.append(Data.plant_row(card))
		Slot.POT:
			if int(preview.get("pot_required", 0)) > 0:
				# 库存不足时仍提供可点选的花盆格，工作槽的填入由窗口校验。
				rows.append(Data.item_row("seedling_pot", service.inventory.get_item_count("seedling_pot")))
		Slot.FERTILIZER:
			for id: String in Enhancement.FERTILIZERS:
				_append_owned_item(rows, service.inventory, id)
		Slot.PROMOTION_BOOK:
			for branch: Dictionary in preview.get("branches", []):
				_append_owned_item(rows, service.inventory, str(branch.id))
	return rows

## 仅将 [param inventory] 持有的 [param id] 加入 [param rows]。
func _append_owned_item(rows: Array[Dictionary], inventory: AdventureInventoryService, id: String) -> void:
	var count: int = inventory.get_item_count(id) # 持有量实时读取，不保存临时库存。
	if count <= 0:
		return
	rows.append(Data.item_row(id, count))

## 将 [param mode] 的界面槽位转换为现有研究服务的操作输入，滤掉空耗材槽。
func operation_choice(mode: String) -> Dictionary:
	match mode:
		"craft":
			return {"recipe_id": _recipe_id}
		"upgrade":
			var consumed: Array[String] = [] # 只传真实填入的 UID，不向服务传入空槽。
			for uid: String in _materials:
				if not uid.is_empty():
					consumed.append(uid)
			return {"uid": _main_uid, "materials": consumed, "use_pot": _use_pot, "fertilizer": _fertilizer}
		"promotion":
			return {"uid": _main_uid, "book_id": _book_id}
	return {}

## [param slot]、[param index] 的用途名称，用于空槽与替换槽的悬停提示。
static func slot_title(slot: Slot, index: int) -> String:
	match slot:
		Slot.RECIPE: return "制作书"
		Slot.MAIN_CARD: return "主卡"
		Slot.MATERIAL_CARD: return "耗材卡 %d" % (index + 1)
		Slot.POT: return "育苗花盆"
		Slot.FERTILIZER: return "肥料"
		Slot.PROMOTION_BOOK: return "转职书"
	return ""
