## 角色面板纯表现：持有独立展示快照，只发出选择和装配意图，不读取玩家全局状态。
extends Control
class_name PlayerPanelView

## 用户请求关闭面板。
signal close_requested
## 用户请求切换 [param uid] 的装配状态。
signal toggle_requested(uid: String)
## 复用已有木框、羊皮纸和按钮，保持冒险界面统一。
const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")
## 装备库存通过原生滚动区接收滚轮和滑动。
const ContentScroll = preload("res://scripts/ui/content_scroll.gd")
## 背包原生格子，装备只提供独立图标投影。
const Tile = preload("res://scripts/adventure/ui/inventory_tile.gd")
## 按装备槽位组合唯一通用底图，不向装备服务注入表现字段。
const EquipmentArt = preload("res://scripts/adventure/ui/player_equipment_art.gd")
## 编号徽章的铭牌、格子和展台按其定义配置。
const CollectibleVisual = preload("res://scripts/adventure/ui/collectible_badge_visual.gd")
## 装备网格与普通背包使用同一原生格子尺寸。
const GRID_COLUMNS: int = 8
## 保留四排空槽，装备增多后完整行继续滚动。
const MIN_GRID_ROWS: int = 4
## 与档案共用已装配时装的选择，左栏读取完整立绘。
const PortraitArt = preload("res://scripts/adventure/ui/player_portrait_art.gd")
## 设计坐标，外层窗口负责按视口等比缩放。
const DESIGN := Vector2(1520, 860)
## 装备背包下方、操作按钮上方的共用详情区域。
const DETAIL_BOUNDS := Rect2(704, 624, 752, 108)
## 编号徽章铭牌在背包与操作按钮之间，给纪念人名留出独立行。
const COLLECTIBLE_DETAIL_BOUNDS := Rect2(704, 617, 752, 121)
## 选中编号徽章时，角色立绘区临时切换成收藏展台。
const COLLECTIBLE_STAGE_BOUNDS := Rect2(55, 203, 404, 502)
## 玩家名称文字。
var _name_label: Label
## 等级角标组件。
var _badge: PlayerLevelBadge
## 左栏全身立绘，展示当前装配或背包里选中的时装。
var _portrait: TextureRect
## 展台容器；不占用装备格或经验条的空间。
var _stage_root: Control
## 已挂载的展台；直到完整退场才释放，以便快速重选时衔接。
var _stage_view: ColorRect
## 尚未退场的舞台对应的款式 ID，同款不同编号共用展台。
var _stage_id: StringName = &""
## 退场后要展示的最新徽章定义；空表示切回角色立绘。
var _requested_stage: EquipmentDefinition
## 当前铭牌的藏品实例 UID。
var _collectible_uid: String = ""
## 左栏过渡进度，0 为角色立绘，1 为完整展台。
var _stage_progress: float = 0.0
## 在途动画目标，防止切换目的徽章时重播同一段退场。
var _stage_goal: float = 0.0
## 由角色面板持有唯一过渡动画，反向切换时旧动画不会执行收尾。
var _stage_tween: Tween
## 仅预览未装配的时装时显示，区分预览与当前装配。
var _preview_label: Label
## 当前等级内经验进度条。
var _experience_bar: TextureProgressBar
## 当前等级内经验文字。
var _experience_label: Label
## 装配摘要仅在立绘上静止悬停时出现。
var _effects_hint: StationaryHoverHint
## 六个槽位的表现容器。
var _slots: Control
## 装备库存网格，滚动支持更多装备。
var _grid: GridContainer
## 普通装备使用的详情布局。
var _details: VBoxContainer
## 编号徽章的镌刻铭牌，与普通详情占用同一块区域。
var _collectible_details: Control
## 铭牌的装配标记；刷新同一枚徽章时只更新此处，避免打断揭幕。
var _collectible_status: Label
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
	# 按立绘原图的 3:4 比例完整展示，在经验条上方留出预览标签的位置。
	_portrait = Art.image(self, "", Vector2(75, 201), Vector2(360, 480))
	_portrait.mouse_filter = Control.MOUSE_FILTER_STOP
	_stage_root = Control.new()
	_stage_root.name = "CollectibleStage"
	_stage_root.position = COLLECTIBLE_STAGE_BOUNDS.position
	_stage_root.size = COLLECTIBLE_STAGE_BOUNDS.size
	_stage_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_root.hide()
	add_child(_stage_root)
	_preview_label = Art.label(self, "时装预览", Vector2(75, 683), Vector2(360, 24), 20)
	_preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_label.hide()
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
	var scroll := ContentScroll.new() # 装备数量增加时纵向滚动，避免把窗口做得更宽。
	scroll.position = Vector2(700, 194)
	scroll.size = Vector2(756, 420)
	add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = GRID_COLUMNS
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_grid)
	_details = VBoxContainer.new() # 名称、期限和说明各自换行，期限独立着色。
	_details.position = DETAIL_BOUNDS.position
	_details.size = DETAIL_BOUNDS.size
	_details.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_details)
	_details_title = Art.label(_details, "", Vector2.ZERO, Vector2.ZERO, 21)
	_details_expiry = Art.label(_details, "", Vector2.ZERO, Vector2.ZERO, 21, Color("a12920"))
	_details_description = Art.label(_details, "", Vector2.ZERO, Vector2.ZERO, 21)
	_details_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details_description.custom_minimum_size.y = 52.0 # 容器为两行说明保留高度，避免自动换行时首帧被裁掉。
	_details_description.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_collectible_details = Control.new()
	_collectible_details.name = "CollectibleBadgeDetails"
	_collectible_details.position = COLLECTIBLE_DETAIL_BOUNDS.position
	_collectible_details.size = COLLECTIBLE_DETAIL_BOUNDS.size
	_collectible_details.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_collectible_details)
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
	var summary: String = "角色加成\n经验 ×[color=#8ecaff]%s[/color]\n掉落数量 ×[color=#8ecaff]%d[/color]\n掉落概率 ×[color=#8ecaff]%s[/color]\n战场金币面额 ×[color=#8ecaff]%s[/color]" % [str(effects.experience_multiplier),
		effects.loot_multiplier, str(effects.drop_chance_multiplier), str(effects.coin_multiplier)] # 单独显示概率类加成。
	if effects.coin_drop_chance_multiplier > 1.0:
		summary += "\n金币掉落率 ×[color=#8ecaff]%s[/color]" % str(effects.coin_drop_chance_multiplier)
	if effects.material_drop_chance_multiplier > 1.0:
		summary += "\n材料掉落率 ×[color=#8ecaff]%s[/color]" % str(effects.material_drop_chance_multiplier)
	_effects_hint.set_text(summary)
	_render_items()

## 清理 [param root] 的旧表现节点；先移出容器，避免本帧重复布局。
func _clear(root: Node) -> void:
	for child: Node in root.get_children(): # 不影响外部业务对象。
		root.remove_child(child)
		child.queue_free()

## 从当前快照刷新装备槽、过滤列表、预览和选中状态。
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
	var selected_item: EquipmentDefinition = selected_row.get("definition") # 空选中时由当前装配决定立绘。
	var preview_outfit: bool = selected_item != null and selected_item.slot == EquipmentDefinition.Slot.OUTFIT and not expired # 只有有效时装参与试穿预览。
	var outfit: EquipmentDefinition = selected_item if preview_outfit else PortraitArt.equipped_outfit(_rows) # 预览和当前装配都读取整张立绘。
	_portrait.texture = outfit.portrait if outfit != null else PortraitArt.DEFAULT_PORTRAIT
	_preview_label.visible = preview_outfit and not selected_row.equipped
	_show_equipment_details(selected_row)

## 更新所选 [param row] 的详情；编号徽章显示实例铭文，限时装备显示剩余天数。
func _show_equipment_details(row: Dictionary) -> void:
	var item: EquipmentDefinition = row.get("definition") # 空选中时没有详情。
	var show_badge: bool = CollectibleVisual.is_definition(item) # 只有配置了展台的徽章使用专属视效。
	var badge_uid: String = str(row.uid) if show_badge else "" # 普通装备选中时还原角色立绘。
	var reveal: bool = badge_uid != _collectible_uid # 同一实例装配刷新时保留铭牌。
	if reveal:
		_collectible_uid = badge_uid
		_requested_stage = item if show_badge else null
		_sync_stage()
	_details.visible = not show_badge
	_collectible_details.visible = show_badge
	_selected_deadline = 0
	_details_title.text = ""
	_details_description.text = ""
	_details_expiry.hide()
	if show_badge:
		if reveal:
			_clear(_collectible_details)
			_collectible_status = CollectibleVisual.draw_detail(_collectible_details, row, Rect2(Vector2.ZERO, _collectible_details.size))
		_collectible_status.visible = row.get("equipped", false)
		return
	_clear(_collectible_details)
	_collectible_status = null
	if item == null:
		return
	if row.get("expired", false):
		_details_title.text = "%s · 已过期" % item.display_name
		_details_description.text = "有效期已结束。"
		return
	_details_title.text = item.display_name + (" · 已装备" if row.equipped else "")
	_details_description.text = item.description
	_selected_deadline = row.get("expires_at", 0)
	refresh_remaining_time()


## 同款从当前帧继续；不同款先让已显示的舞台退场，再展示最新选择。
func _sync_stage() -> void:
	if _stage_view == null:
		if _requested_stage == null:
			return
		_stage_id = _requested_stage.id
		_stage_view = CollectibleVisual.draw_stage(_stage_root, _requested_stage)
	var show_stage: bool = _requested_stage != null and _requested_stage.id == _stage_id # 同款重选可接续退场进度。
	var target: float = 1.0 if show_stage else 0.0 # 从已显示的款式决定当前动画是否回到立绘。
	if _stage_tween != null:
		if _stage_goal == target:
			return
		_stage_tween.kill()
		_stage_tween = null
	elif show_stage and is_equal_approx(_stage_progress, 1.0):
		return
	_stage_goal = target
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.show()
	_effects_hint.dismiss()
	_apply_stage_progress(_stage_progress)
	_stage_root.show()
	var distance: float = absf(target - _stage_progress) # 半途反向时按剩下的幅度缩短时长。
	if is_zero_approx(distance):
		_finish_stage_transition(show_stage)
		return
	var seconds: float = (1.3 if show_stage else 0.74) * distance # 退场留出背景收束和立绘复现的时间。
	_stage_tween = create_tween().set_ignore_time_scale(true)
	_stage_tween.tween_method(_apply_stage_progress, _stage_progress, target, seconds) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT if show_stage else Tween.EASE_IN_OUT)
	_stage_tween.tween_callback(_finish_stage_transition.bind(show_stage))

## 将 [param progress] 同时应用到展台材质、透明度和立绘，维持同一连续画面。
func _apply_stage_progress(progress: float) -> void:
	_stage_progress = progress
	var cover: float = smoothstep(0.0, 0.70, progress) # 展台收束后再淡进底下的立绘。
	_stage_root.modulate.a = cover
	_portrait.modulate.a = 1.0 - smoothstep(0.32, 0.77, progress)
	_preview_label.modulate.a = 1.0 - cover
	CollectibleVisual.set_stage_progress(_stage_view, progress)

## [param show_stage] 确定稳定画面；退场完成后释放旧展台，并接上最新选择。
func _finish_stage_transition(show_stage: bool) -> void:
	_stage_tween = null
	if show_stage:
		_portrait.hide()
		return
	_stage_root.hide()
	_clear(_stage_root)
	_stage_view = null
	_stage_id = &""
	if _requested_stage == null:
		_portrait.mouse_filter = Control.MOUSE_FILTER_STOP
	else:
		_sync_stage()

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
		var show_badge: bool = CollectibleVisual.is_definition(item) # 编号徽章使用独立底板。
		projection = {"kind": "icon", "uid": str(row.uid), "title": item.display_name, "icon": item.icon,
			"backing": null if show_badge else EquipmentArt.backing_texture(item.slot),
			"inset_icon": item.slot == EquipmentDefinition.Slot.OUTFIT,
			"badge": "已装备" if row.equipped and not in_slot else ""}
		if show_badge:
			projection["collectible_badge_id"] = item.id
			projection["edition_uid"] = row.get("edition_uid", 0)
		if row.get("expired", false):
			projection["badge"] = "已过期"
	tile.setup(projection, -1, false, false, not row.is_empty() and row.uid == _selected)
	tile.custom_minimum_size = Vector2(86, 96)
	if not in_slot:
		tile.enable_scrollable_selection(tile)
	tile.chosen.connect(_choose_tile, CONNECT_DEFERRED)
	return tile

## 接收 [param record] 的格子投影；等当前输入处理完再刷新，避免离树后继续消费同一输入。
func _choose_tile(record: Dictionary) -> void:
	_select(str(record.get("uid", "")))

## 选择 [param uid] 刷新详情和时装预览，不执行装备事务。
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
