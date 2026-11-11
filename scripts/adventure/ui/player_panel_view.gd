## 角色面板纯表现：持有独立展示快照，只发出选择和装配意图，不读取玩家全局状态。
extends Control
class_name PlayerPanelView

## 用户请求关闭面板。
signal close_requested
## 用户请求切换 [param uid] 的装配状态。
signal toggle_requested(uid: String)
## 复用已有木框、羊皮纸和按钮，保持冒险界面统一。
const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")
## 背包原生格子，装备只提供独立图标投影。
const Tile = preload("res://scripts/adventure/ui/inventory_tile.gd")
## 按装备槽位组合唯一通用底图，不向装备服务注入表现字段。
const EquipmentArt = preload("res://scripts/adventure/ui/player_equipment_art.gd")
## 装备网格与普通背包使用同一原生格子尺寸。
const GRID_COLUMNS: int = 8
## 保留四排空槽，装备增多后完整行继续滚动。
const MIN_GRID_ROWS: int = 4
## 与战外头像共享时装立绘选择。
const PortraitArt = preload("res://scripts/adventure/ui/player_portrait_art.gd")
## 设计坐标，外层窗口负责按视口等比缩放。
const DESIGN := Vector2(1520, 860)
## 玩家名称文字。
var _name_label: Label
## 等级角标组件。
var _badge: PlayerLevelBadge
## 纯贴图立绘，不实例化具有业务逻辑的角色场景。
var _portrait: TextureRect
## 当前等级内经验进度条。
var _experience_bar: TextureProgressBar
## 当前等级内经验文字。
var _experience_label: Label
## 装配摘要仅在立绘静止悬停时出现。
var _effects_hint: StationaryHoverHint
## 六个槽位的表现容器。
var _slots: Control
## 装备库存网格，滚动支持更多装备。
var _grid: GridContainer
## 当前选择的装备名称与状态。
var _details_title: Label
## 限时装备的红色剩余天数。
var _details_expiry: Label
## 当前选择的装备说明。
var _details_description: Label
## 当前选择的到期 Unix 秒，0 表示没有倒计时。
var _selected_deadline: int = 0
## 装备或卸下按钮。
var _action: Button
## 过期装备的唯一操作，复用普通背包的丢弃按钮。
var _discard: Button
## 服务提供的独立投影列表，不含可写玩家状态。
var _rows: Array[Dictionary] = []
## 当前选中装备 UID，仅属于界面。
var _selected: String = ""
## 分类过滤，-1 表示全部。
var _filter_slot: int = -1

## 创建面板；窗口只需调用 [method present] 提供显示数据。
func _ready() -> void:
	size = DESIGN
	Art.panel(self, "panels/wood_ninepatch.png", Vector2.ZERO, DESIGN, 35)
	Art.panel(self, "panels/outer_frame_ninepatch.png", Vector2.ZERO, DESIGN, 42)
	Art.image(self, "res://assets/adventure/ui/bottom_bar/icons/icon_player.png", Vector2(35, 24), Vector2(65, 65))
	Art.label(self, "角色", Vector2(112, 25), Vector2(300, 65), 40, Color("ffe8b0"))
	Art.button(self, "controls/close", Vector2(1416, 27), Vector2(65, 65), func(): close_requested.emit())
	Art.panel(self, "panels/parchment_ninepatch.png", Vector2(32, 111), Vector2(450, 712), 30)
	Art.panel(self, "panels/parchment_ninepatch.png", Vector2(501, 111), Vector2(986, 712), 30)
	_badge = PlayerLevelBadge.new()
	_badge.position = Vector2(56, 133)
	_badge.size = Vector2(104, 68)
	add_child(_badge)
	_name_label = Art.label(self, "", Vector2(171, 140), Vector2(282, 50), 27)
	var portrait_shading := Gradient.new() # 暖棕色从人物身后向外淡出，保留底下的羊皮纸纹理。
	portrait_shading.offsets = PackedFloat32Array([0.0, 0.45, 0.75, 1.0])
	portrait_shading.colors = PackedColorArray([
		Color(0.34, 0.21, 0.12, 0.58),
		Color(0.34, 0.21, 0.12, 0.52),
		Color(0.34, 0.21, 0.12, 0.30),
		Color(0.34, 0.21, 0.12, 0.0),
	])
	var portrait_texture := GradientTexture2D.new() # 让深色延伸到人物两侧，再向四边渐隐。
	portrait_texture.gradient = portrait_shading
	portrait_texture.fill = GradientTexture2D.FILL_SQUARE
	portrait_texture.fill_from = Vector2(0.5, 0.5)
	portrait_texture.fill_to = Vector2(1.0, 0.5)
	var portrait_backdrop: TextureRect = Art.image(self, "", Vector2(55, 190), Vector2(404, 510)) # 背景边缘留出渐隐空间。
	portrait_backdrop.texture = portrait_texture
	portrait_backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_portrait)
	_portrait.position = Vector2(75, 205)
	_portrait.size = Vector2(360, 480)
	_experience_bar = TextureProgressBar.new()
	_experience_bar.texture_under = preload("res://assets/adventure/ui/player/exp_bar_bg.png")
	_experience_bar.texture_progress = preload("res://assets/adventure/ui/player/exp_bar_fill.png")
	_experience_bar.texture_over = preload("res://assets/adventure/ui/player/exp_bar_frame.png")
	_experience_bar.fill_mode = TextureProgressBar.FILL_LEFT_TO_RIGHT
	_experience_bar.nine_patch_stretch = true # 运行时三层资源均为 370×20，避免原生最小尺寸撑大面板。
	_experience_bar.stretch_margin_left = 12
	_experience_bar.stretch_margin_right = 12
	_experience_bar.stretch_margin_top = 6
	_experience_bar.stretch_margin_bottom = 6
	_experience_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_experience_bar)
	_experience_bar.position = Vector2(72, 711)
	_experience_bar.size = Vector2(370, 20)
	_experience_label = Art.label(self, "", Vector2(72, 739), Vector2(370, 33), 22)
	_experience_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Art.label(self, "已装备", Vector2(526, 132), Vector2(143, 44), 27)
	var divider := ColorRect.new() # 在两栏之间留出清晰分界，颜色沿用面板的暖棕色调。
	divider.color = Color(0.56, 0.36, 0.20, 0.62)
	divider.position = Vector2(668, 132)
	divider.size = Vector2(3, 668)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(divider)
	Art.label(self, "装备背包", Vector2(705, 132), Vector2(240, 44), 29)
	var filter := InventoryFilterButton.new() # 筛选框和弹出菜单统一使用背包现有素材。
	filter.position = Vector2(1221, 134)
	filter.size = Vector2(233, 44)
	add_child(filter)
	var options := PackedStringArray(["全部装备"]) # 首项对应不过滤，后续索引对应装备槽。
	options.append_array(EquipmentCatalog.SLOT_NAMES)
	filter.configure(options)
	filter.option_selected.connect(_filter_changed)
	_slots = Control.new()
	_slots.position = Vector2(553, 190)
	add_child(_slots)
	var scroll := ScrollContainer.new() # 装备数量增加时纵向滚动，避免把窗口做得更宽。
	scroll.position = Vector2(700, 194)
	scroll.size = Vector2(756, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = GRID_COLUMNS
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_grid)
	var details := VBoxContainer.new() # 名称、期限和说明各自换行，期限独立着色。
	details.position = Vector2(704, 624)
	details.size = Vector2(752, 108)
	details.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(details)
	_details_title = Art.label(details, "", Vector2.ZERO, Vector2.ZERO, 21)
	_details_expiry = Art.label(details, "", Vector2.ZERO, Vector2.ZERO, 21, Color("a12920"))
	_details_description = Art.label(details, "", Vector2.ZERO, Vector2.ZERO, 21)
	_details_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details_description.custom_minimum_size.y = 52.0 # 容器为两行说明保留高度，避免自动换行时首帧被裁掉。
	_details_description.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_action = Art.action_button(self, "装备", "buttons/action_confirm", Vector2(1232, 744), Vector2(225, 60), _toggle)
	_discard = Art.action_button(self, "丢弃", "buttons/action_danger", Vector2(1232, 744), Vector2(225, 60), _toggle)
	_effects_hint = StationaryHoverHint.new()
	add_child(_effects_hint)
	_effects_hint.watch(_portrait)

## 显示 [param player_name]、[param progression]、[param rows] 与 [param effects]；所有输入均为独立投影。
func present(player_name: String, progression: Dictionary, rows: Array[Dictionary], effects: PlayerEffects) -> void:
	_rows = rows
	_name_label.text = player_name
	_badge.present(int(progression.level))
	_experience_bar.max_value = maxi(1, int(progression.required))
	_experience_bar.value = int(_experience_bar.max_value) if progression.capped else int(progression.current)
	_experience_label.text = "已达到经验存储上限" if progression.capped else "经验  %d / %d" % [progression.current, progression.required]
	_portrait.texture = PortraitArt.resolve(_rows)
	_effects_hint.set_text("角色加成\n经验 ×[color=#8ecaff]%s[/color]\n掉落数量 ×[color=#8ecaff]%d[/color]\n掉落概率 ×[color=#8ecaff]%s[/color]\n战场金币 ×[color=#8ecaff]%s[/color]" % [str(effects.experience_multiplier),
		effects.loot_multiplier, str(effects.drop_chance_multiplier), str(effects.coin_multiplier)])
	_render_items()

## 清理 [param root] 的旧表现节点；先移出容器，避免本帧重复布局。
func _clear(root: Node) -> void:
	for child: Node in root.get_children(): # 不影响外部业务对象。
		root.remove_child(child)
		child.queue_free()

## 从当前快照刷新装备槽、过滤列表和选中状态。
func _render_items() -> void:
	_clear(_slots)
	_clear(_grid)
	var shown: int = 0 # 当前分类下的装备数量。
	var selected_row: Dictionary = {} # 当前详情必须来自本次权威投影。
	for index: int in range(EquipmentCatalog.SLOT_NAMES.size()): # 六个槽位始终保留，即使没有装备。
		var equipped_row: Dictionary = {} # 每槽最多一件，业务层已经校验。
		for row: Dictionary in _rows: # 快照中查找装配标记，不读取存档。
			if row.equipped and row.definition.slot == index:
				equipped_row = row
		var cell: Control = _cell(equipped_row, true) # 槽位与库存共用视觉单元。
		_slots.add_child(cell)
		cell.position = Vector2(0, index * 102)
		cell.set_slot_hint(EquipmentCatalog.SLOT_NAMES[index])
	for row: Dictionary in _rows: # 库存仍包含已装配装备，用标记显示，不复制持有记录。
		if row.uid == _selected:
			selected_row = row
		if _filter_slot >= 0 and row.definition.slot != _filter_slot:
			continue
		_grid.add_child(_cell(row, false))
		shown += 1
	var capacity: int = maxi(GRID_COLUMNS * MIN_GRID_ROWS, ceili(float(shown) / GRID_COLUMNS) * GRID_COLUMNS) # 填满尾行和基础四排。
	for empty_index: int in range(shown, capacity): # 空槽复用背包材质，不能触发装备操作。
		_grid.add_child(_cell({}, false))
	var expired: bool = selected_row.get("expired", false) # 两种操作不会同时出现。
	_action.visible = not selected_row.is_empty() and not expired
	_discard.visible = expired
	_action.text = "卸下" if selected_row.get("equipped", false) else "装备"
	_show_equipment_details(selected_row)

## 更新所选 [param row] 的详情；有效期限显示剩余天数，过期只显示状态。
func _show_equipment_details(row: Dictionary) -> void:
	_selected_deadline = 0
	_details_title.text = ""
	_details_description.text = ""
	_details_expiry.hide()
	if row.is_empty():
		return
	var item: EquipmentDefinition = row.definition # 只读取展示投影。
	if row.get("expired", false):
		_details_title.text = "%s · 已过期" % item.display_name
		_details_description.text = "有效期已结束。"
		return
	_details_title.text = item.display_name + (" · 已装备" if row.equipped else "")
	_details_description.text = item.description
	_selected_deadline = row.get("expires_at", 0)
	refresh_remaining_time()

## 按整天向上取整刷新当前详情，不重新构建背包网格。
func refresh_remaining_time() -> void:
	var seconds_left: int = _selected_deadline - int(Time.get_unix_time_from_system()) # 以绝对期限计算实际剩余秒数。
	_details_expiry.visible = seconds_left > 0
	if seconds_left > 0:
		var days_left: int = ceili(float(seconds_left) / EquipmentDefinition.SECONDS_PER_DAY) # 不足一天仍显示 1 天。
		_details_expiry.text = "剩余到期：%d天" % days_left

## 把 [param row] 转成背包格的纯图标投影；[param in_slot] 控制是否显示已装备角标。
func _cell(row: Dictionary, in_slot: bool) -> Control:
	var tile: Control = Tile.new() # 复用背包格子的普通、悬停和选中边框，不复制交互实现。
	var projection: Dictionary = {} # 装备服务状态不进入普通道具目录。
	if not row.is_empty():
		var item: EquipmentDefinition = row.definition # 只投影图标与文本，不让格子了解装备规则。
		projection = {"kind": "icon", "uid": str(row.uid), "title": item.display_name, "icon": item.icon,
			"backing": EquipmentArt.backing_texture(item.slot),
			"badge": "已装备" if row.equipped and not in_slot else ""}
		if row.get("expired", false):
			projection["badge"] = "已过期"
	tile.setup(projection, -1, false, false, not row.is_empty() and row.uid == _selected)
	tile.custom_minimum_size = Vector2(86, 96)
	tile.chosen.connect(_choose_tile, CONNECT_DEFERRED)
	return tile

## 接收 [param record] 的格子投影；等当前输入处理完再刷新，避免离树后继续消费同一输入。
func _choose_tile(record: Dictionary) -> void:
	_select(str(record.get("uid", "")))

## 选择 [param uid] 只改变表现，不执行装备事务。
func _select(uid: String) -> void:
	_selected = uid
	_render_items()

## [param index] 为下拉索引，首项表示全部。
func _filter_changed(index: int) -> void:
	_filter_slot = index - 1
	_selected = ""
	_render_items()

## 把当前选择交给窗口控制器再次校验和提交。
func _toggle() -> void:
	if not _selected.is_empty():
		toggle_requested.emit(_selected)
