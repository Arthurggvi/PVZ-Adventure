## 任务窗口只显示服务投影，折叠和选择属于界面状态。
extends Control

## 关闭窗口时通知工具栏释放引用。
signal closed
## 领奖成功并播放反馈后通知教学继续；[param id] 为真实已提交的任务。
signal reward_presented(id: String)
## 原生礼盒星屑和音效。
const RewardBurst = preload("res://scripts/adventure/ui/reward_burst.gd")
## 当前领取按钮，供教学按实际缩放位置定位。
var _claim_button: Button
## 领奖表现期间不重复提交或开始下一段对话。
var reward_playing := false
## 共享木框、羊皮纸、按钮和文字绘制入口。
const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")
## 任务目录使用与图鉴相同的滚动区。
const ContentScroll = preload("res://scripts/ui/content_scroll.gd")
## 任务簿的动态皮肤和初次远征奖励美术由自身声明。
const ResourcePaths = preload("res://scripts/adventure/ui/ui_resource_paths.gd")

## 准备首屏任务详情，不创建其他任务的奖励卡面。
static func get_initial_resource_paths() -> PackedStringArray:
	var paths: PackedStringArray = ResourcePaths.frame() # 列表按钮与当前详情公共素材。
	paths.append_array(ResourcePaths.skin(PackedStringArray(["controls/filter_field.png", "slots/item_slot_normal.png",
		"res://assets/adventure/ui/bottom_bar/icons/icon_quests.png"]), PackedStringArray(["buttons/action_neutral", "buttons/action_confirm"])))
	if Global.global_game_state != null:
		for task: Dictionary in AdventureQuestService.rows(Global.global_game_state.adventure_state):
			if str(task.id) != "first_expedition":
				continue
			var rows: Array[Dictionary] = [] # 只取当前选中任务的奖励。
			for reward: Dictionary in task.get("items", []):
				rows.append(ResourcePaths.ItemArt.entry(str(reward.id)).merged({"id": str(reward.id),
					"plant_type": int(Recipes.definition(str(reward.id)).get("plant_type", 0))}))
			ResourcePaths.inventory_rows(paths, rows)
	return paths
## 共享道具图标解析入口。
const ItemArt = preload("res://scripts/adventure/ui/inventory_item_art.gd")
## 静态目录与当前玩家的任务服务。
const Catalog = preload("res://scripts/adventure/quests/quest_catalog.gd")
## 配方图案使用已有合成定义。
const Recipes = preload("res://scripts/adventure/research/research_recipe_catalog.gd")
## 打开时绑定档案，切档后关闭旧窗口。
var _opened_state: AdventureState
## 当前玩家的任务展示投影。
var _tasks: Array[Dictionary] = []
## 当前详情的周期，跨日后的旧点击不能领取新周期奖励。
var _period := ""
## 设计尺寸，等比缩放后给底部工具栏留出空间。
const DESIGN := Vector2(1480, 830)
## 任务界面的中文字体。
const FONT = preload("res://assets/fonts/方正少儿_GBK.ttf")
## 统一缩放的视觉根节点。
var _canvas: Control
## 目录滚动区域中的纵向列表。
var _directory: VBoxContainer
## 任务内容所在的动态区域。
var _details: Control
## 当前选中的任务 ID。
var _selected := "first_expedition"
## 各分组展开状态；完成分组初始收起。
var _expanded := {"主线任务": true, "支线任务": true, "日常任务": true, "活动任务": true, "已完成": false}
## 各任务行，用于更新选中样式。
var _rows: Dictionary = {}
## 关闭操作防重入。
var _closing := false

## 创建面板、绑定当前档案和任务变化通知。
func _ready() -> void:
	_opened_state = Global.global_game_state.adventure_state
	Global.refresh_quests()
	Global.quests_changed.connect(_refresh_tasks)
	Global.user_manager.signal_users_update.connect(_profile_changed)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Theme.new()
	theme.default_font = FONT
	# 覆盖整个宿主场景的暗幕。
	var shade := ColorRect.new()
	shade.color = Color(0.035, 0.045, 0.025, 0.72)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	_canvas = Control.new()
	_canvas.name = "QuestCanvas"
	_canvas.size = DESIGN
	add_child(_canvas)
	Art.panel(_canvas, "panels/wood_ninepatch.png", Vector2.ZERO, DESIGN, 35)
	Art.panel(_canvas, "panels/outer_frame_ninepatch.png", Vector2.ZERO, DESIGN, 42)
	Art.image(_canvas, "res://assets/adventure/ui/bottom_bar/icons/icon_quests.png", Vector2(38, 27), Vector2(64, 64))
	Art.label(_canvas, "任务簿", Vector2(112, 29), Vector2(360, 60), 40, Color("ffe8b0"))
	Art.button(_canvas, "controls/close", Vector2(1364, 28), Vector2(65, 65), request_close)
	Art.panel(_canvas, "panels/parchment_ninepatch.png", Vector2(35, 112), Vector2(390, 678), 30)
	Art.label(_canvas, "任务目录", Vector2(67, 131), Vector2(320, 50), 29)
	var scroll := ContentScroll.new() # 目录滚动允许将来增加任意数量任务。
	scroll.position = Vector2(57, 193)
	scroll.size = Vector2(345, 568)
	_canvas.add_child(scroll)
	_directory = VBoxContainer.new()
	_directory.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_directory.add_theme_constant_override("separation", 9)
	scroll.add_child(_directory)
	_details = Control.new()
	_details.position = Vector2(445, 112)
	_details.size = Vector2(1000, 678)
	_canvas.add_child(_details)
	_refresh_tasks()
	resized.connect(_fit)
	_fit()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.18)

## 等比居中窗口，并为展开的底部工具栏保留空间。
func _fit() -> void:
	# 以横向边距及底部预留共同限制面板大小。
	var factor := minf((size.x - 36.0) / DESIGN.x, (size.y - 94.0) / DESIGN.y)
	_canvas.scale = Vector2.ONE * maxf(factor, 0.1)
	_canvas.position = Vector2((size.x - DESIGN.x * factor) * 0.5, (size.y - 70.0 - DESIGN.y * factor) * 0.5)

## 创建可折叠分组和独立的任务选择按钮。
func _build_directory() -> void:
	for group: String in Catalog.GROUPS: # 目录按固定顺序呈现。
		# 分组内任务采用独立容器，收起时不影响右侧阅读状态。
		var entries := VBoxContainer.new()
		entries.add_theme_constant_override("separation", 3)
		entries.visible = _expanded[group]
		# 分类标题保留木质纹理，与任务条目区分。
		var header := Art.action_button(_directory, "", "buttons/action_neutral", Vector2.ZERO, Vector2.ZERO, Callable())
		header.custom_minimum_size = Vector2(0, 51)
		header.mouse_filter = Control.MOUSE_FILTER_PASS # 从分组标题开始也能滑动任务目录。
		header.alignment = HORIZONTAL_ALIGNMENT_LEFT
		header.add_theme_font_size_override("font_size", 24)
		header.text = ("▾  " if _expanded[group] else "▸  ") + group
		header.pressed.connect(_toggle_group.bind(group, header, entries))
		_directory.add_child(entries)
		for task: Dictionary in _tasks: # 选择任务仅替换详情显示。
			if task.group != group:
				continue
			var row := Button.new() # 任务行自带键盘焦点和点击区域。
			row.text = "    " + str(task.title) + ("  · 可领取" if task.status == "complete" else "")
			row.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			row.custom_minimum_size = Vector2(0, 43)
			row.alignment = HORIZONTAL_ALIGNMENT_LEFT
			row.add_theme_font_size_override("font_size", 23)
			row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			row.mouse_filter = Control.MOUSE_FILTER_PASS # 保留点击选择，并让触摸拖动到达目录。
			row.pressed.connect(_select_task.bind(str(task.id)))
			entries.add_child(row)
			_rows[task.id] = row

## 切换 [param group] 的展开状态，并更新 [param header] 和 [param entries]。
func _toggle_group(group: String, header: Button, entries: Control) -> void:
	_expanded[group] = not _expanded[group]
	entries.visible = _expanded[group]
	header.text = ("▾  " if _expanded[group] else "▸  ") + group
	SoundManager.play_other_SFX(&"tap")

## 根据 [param id] 更新当前任务及行高亮。
func _select_task(id: String) -> void:
	_selected = id
	for row_id: String in _rows: # 选中、悬停和键盘焦点使用可读的暖色底。
		var row: Button = _rows[row_id] # 此行只控制选择，不操作任务状态。
		for state: String in ["normal", "hover", "pressed", "focus"]: # 同一行的四种输入状态。
			var style := StyleBoxFlat.new() # 半透明深绿突出当前任务。
			style.bg_color = Color("546038") if row_id == id else Color(0.32, 0.24, 0.12, 0.12 if state == "normal" else 0.23)
			style.set_corner_radius_all(5)
			row.add_theme_stylebox_override(state, style)
		for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]: # 保持选中行字体对比度。
			row.add_theme_color_override(state, Color("fff1c6") if row_id == id else Color("49361e"))
	for child: Node in _details.get_children(): # 同步移出显示树，待信号处理结束后释放。
		_details.remove_child(child)
		child.queue_free()
	for task: Dictionary in _tasks: # 任务 ID 在目录内唯一。
		if task.id == id:
			_period = task.period
			_render_details(task)
			return

## 绘制 [param task] 的说明与奖励，按钮状态由真实任务进度决定。
func _render_details(task: Dictionary) -> void:
	if task.get("letter", false):
		_render_letter(task)
		_render_claim_button(task)
		return
	Art.panel(_details, "panels/parchment_ninepatch.png", Vector2.ZERO, Vector2(1000, 364), 30)
	Art.label(_details, str(task.group) + "  /  僵尸岛", Vector2(38, 24), Vector2(800, 32), 20, Color("79613d"))
	Art.label(_details, task.title, Vector2(38, 60), Vector2(920, 65), 43)
	# 可滚动的说明区为长文案留出扩展空间。
	var description := RichTextLabel.new()
	description.position = Vector2(40, 141)
	description.size = Vector2(920, 132)
	description.text = task.description
	description.add_theme_font_size_override("normal_font_size", 24)
	description.add_theme_color_override("default_color", Color("55432b"))
	_details.add_child(description)
	Art.panel(_details, "controls/filter_field.png", Vector2(37, 294), Vector2(926, 44), 12)
	Art.label(_details, task.objective, Vector2(54, 297), Vector2(760, 38), 21)
	Art.label(_details, task.progress, Vector2(861, 297), Vector2(90, 38), 21, Color("596b31"))
	Art.panel(_details, "panels/parchment_ninepatch.png", Vector2(0, 382), Vector2(1000, 296), 30)
	Art.label(_details, "任务奖励", Vector2(38, 401), Vector2(240, 43), 28)
	if int(task.exp) > 0:
		Art.label(_details, "EXP: %d" % task.exp, Vector2(40, 449), Vector2(265, 42), 29, Color("596b31"))
	if int(task.coins) > 0:
		Art.label(_details, "%d$" % task.coins, Vector2(334, 449), Vector2(250, 42), 29)
	if "research" in task.unlocks:
		Art.label(_details, "领取后解锁研究室", Vector2(624, 454), Vector2(335, 38), 23, Color("596b31"))
	if "library" in task.unlocks:
		Art.label(_details, "完成任务解锁图书馆", Vector2(624, 454), Vector2(335, 38), 23, Color("596b31"))
	if "shop" in task.unlocks:
		Art.label(_details, "与戴夫谈完后解锁商店", Vector2(624, 454), Vector2(335, 38), 23, Color("596b31"))
	if not task.items.is_empty():
		Art.label(_details, "道具", Vector2(40, 504), Vector2(150, 34), 22)
		for index: int in 5: # 奖励统一展示五个空槽，已有物品填入对应位置。
			var pos := Vector2(40 + index * 96, 548) # 槽位之间保留间距。
			Art.image(_details, "slots/item_slot_normal.png", pos, Vector2(80, 80))
			if index < task.items.size():
				var reward: Dictionary = task.items[index] # 图标通过现有 ID 解析。
				var backing: String = ItemArt.backing_uri(reward.id) # 与背包共用道具分类底图。
				if not backing.is_empty():
					Art.image(_details, backing, pos, Vector2(80, 80))
				var icon := Art.image(_details, ItemArt.icon_uri(reward.id), pos + Vector2(8, 8), Vector2(64, 64)) # 奖励物品原始素材。
				icon.mouse_filter = Control.MOUSE_FILTER_PASS
				icon.tooltip_text = str(ItemRegistry.get_item_definition(reward.id).get("name", reward.id))
				if str(ItemRegistry.get_item_definition(reward.id).get("category", "")) == "recipe":
					ItemArt.add_recipe_portrait(_details, int(Recipes.definition(reward.id).get("plant_type", 0)), pos + Vector2(40, 43), 0.32)
				if not backing.is_empty():
					Art.slot_frame(_details, pos, Vector2(80, 80))
				Art.count_badge(_details, "×%d" % reward.count, pos + Vector2(77, 77))
	if task.has("equipment_reward"):
		_render_equipment_reward(task, Vector2(40, 548))
	_render_claim_button(task)

## 展示 [param task] 的活动信和装备奖励；正文可滚动，奖励与领取按钮保持可见。
func _render_letter(task: Dictionary) -> void:
	Art.panel(_details, "panels/parchment_ninepatch.png", Vector2.ZERO, Vector2(1000, 491), 30)
	Art.label(_details, task.group, Vector2(48, 22), Vector2(900, 34), 22, Color("24685b"))
	Art.label(_details, task.title, Vector2(46, 56), Vector2(904, 68), 50, Color("8d3725"))
	var letter := RichTextLabel.new() # 大段正文独立滚动，末句用 Godot 内置彩虹动效。
	letter.position = Vector2(50, 129)
	letter.size = Vector2(900, 345)
	letter.bbcode_enabled = true
	letter.add_theme_font_override("normal_font", FONT)
	letter.add_theme_font_size_override("normal_font_size", 25)
	letter.add_theme_constant_override("line_separation", 3)
	letter.add_theme_color_override("default_color", Color("483525"))
	letter.text = task.description
	letter.meta_clicked.connect(_open_author_profile)
	_details.add_child(letter)
	Art.panel(_details, "panels/parchment_ninepatch.png", Vector2(0, 507), Vector2(1000, 171), 30)
	# 补领时标明面板展示的是本次可领的奖励。
	var heading: String = "追加奖励" if task.get("additional_equipment_only", false) else "活动奖励"
	Art.label(_details, heading, Vector2(39, 520), Vector2(270, 38), 26, Color("24685b"))
	_render_letter_equipment_rewards(task)

## 在活动信底部并排展示 [param task] 的奖励，限时装备注明计时起点与装备入口。
func _render_letter_equipment_rewards(task: Dictionary) -> void:
	var original_id: String = task.get("equipment_reward", "") # 补领投影省略原奖励。
	var reward_ids: Array = task.get("additional_equipment_rewards", []).duplicate() # 复制列表以便将原奖励排在前面。
	if not original_id.is_empty():
		reward_ids.push_front(original_id)
	for index: int in reward_ids.size(): # 三列内容区在固定领奖按钮之前结束。
		var id: String = reward_ids[index] # 根据目录 ID 读取图标、名称和期限。
		var equipment: EquipmentDefinition = EquipmentCatalog.definition(id) # 与角色背包使用同一份装备定义。
		if equipment == null:
			continue
		var pos := Vector2(39 + index * 215, 557) # 每列宽 208，图标与两行文字居中排列。
		# 时装保留活动信中的名称，收集器使用角色页的装备名称。
		var title: String = task.get("equipment_label", equipment.display_name) if id == original_id else equipment.display_name
		var subtitle: String = equipment.display_name if title != equipment.display_name else "" # 时装别名与角色页名称对应。
		if equipment.lifetime_days > 0:
			subtitle = "领取起 %d 天 · 角色页装备" % equipment.lifetime_days
		_render_equipment_reward_icon(equipment, pos + Vector2(72, 0), 64)
		var name_label: Label = Art.label(_details, title, pos + Vector2(0, 63), Vector2(208, 28), 22, Color("185f8c")) # 图标下方的装备名。
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var detail_label: Label = Art.label(_details, subtitle, pos + Vector2(0, 91), Vector2(208, 24), 18) # 名称下方的角色页名称或限时说明。
		detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

## 以 [param pos] 绘制 [param task] 的普通任务装备图标、名称和效果说明。
func _render_equipment_reward(task: Dictionary, pos: Vector2) -> void:
	var equipment: EquipmentDefinition = EquipmentCatalog.definition(task.equipment_reward) # 复用角色面板的装备定义。
	if equipment == null:
		return
	var title: String = task.get("equipment_label", equipment.display_name) # 未设别名时沿用定义名称。
	_render_equipment_reward_icon(equipment, pos, 82)
	Art.label(_details, title, pos + Vector2(102, 2), Vector2(510, 42), 33, Color("185f8c"))
	Art.label(_details, equipment.display_name if title != equipment.display_name else equipment.description,
		pos + Vector2(104, 45), Vector2(510, 34), 24)

## 在 [param pos] 绘制边长 [param edge] 的 [param equipment] 奖励图标，悬停可查看效果。
func _render_equipment_reward_icon(equipment: EquipmentDefinition, pos: Vector2, edge: float) -> void:
	Art.image(_details, "slots/item_slot_normal.png", pos, Vector2.ONE * edge)
	var icon: TextureRect = Art.image(_details, "", pos + Vector2(8, 8), Vector2.ONE * (edge - 16)) # 直接使用装备贴图，兼容裁切图集。
	icon.texture = equipment.icon
	icon.mouse_filter = Control.MOUSE_FILTER_PASS
	icon.tooltip_text = equipment.description

## 将活动信中点击的 [param meta] 与作者主页核对后交给系统浏览器。
func _open_author_profile(meta: Variant) -> void:
	if str(meta) == Catalog.AUTHOR_PROFILE_URL:
		OS.shell_open(Catalog.AUTHOR_PROFILE_URL)

## 为 [param task] 绘制共用的领奖入口；实际点击时重新核验档案和周期。
func _render_claim_button(task: Dictionary) -> void:
	var caption: String = "已领取" if task.status == "claimed" else "领取奖励" # 首次领取与已完成任务沿用原提示。
	if task.get("additional_equipment_only", false):
		caption = "领取追加奖励"
	var claim := Art.action_button(_details, caption, "buttons/action_confirm", Vector2(695, 551), Vector2(260, 74), _claim_reward) # 与引导和礼盒演出的坐标对齐。
	_claim_button = claim
	claim.disabled = task.status != "complete"
	claim.tooltip_text = "完成任务后领取奖励" if task.status == "active" else ""

## 将真实领取交给服务；成功进入完成目录，失败展示可重试原因。
func _claim_reward() -> void:
	if reward_playing:
		return
	if Global.global_game_state.adventure_state != _opened_state or not Global.save_service.is_current_profile_loaded():
		request_close()
		return
	# 服务一次提交物品、装备、金币、经验和领取状态。
	var issue := AdventureQuestService.claim(_opened_state, Global.adventure_inventory, Global.global_game_state,
		Global.save_service.save_now, _selected, _period, AdventureQuestService.today())
	if issue.is_empty():
		_expanded["已完成"] = true
		reward_playing = true
		Global.player_changed.emit()
	Global.quests_changed.emit()
	if issue.is_empty():
		RewardBurst.play(_canvas, _details.position + Vector2(825, 586))
		var claimed_id: String = _selected # 防止动画期间用户选择另一任务。
		var feedback := create_tween() # 随窗口销毁取消，不跨场景继续教学。
		feedback.tween_interval(1.0)
		feedback.tween_callback(func():
			reward_playing = false
			reward_presented.emit(claimed_id))
		return
	# 存档失败与周期变化反馈。
	var notice := AcceptDialog.new()
	notice.title = "任务奖励"
	notice.dialog_text = issue
	notice.confirmed.connect(notice.queue_free)
	notice.canceled.connect(notice.queue_free)
	add_child(notice)
	notice.popup_centered(Vector2i(440, 160))

## 换档时销毁旧窗口，重命名且状态相同则继续显示。
func _profile_changed() -> void:
	if Global.global_game_state.adventure_state != _opened_state:
		request_close()

## 服务通知后刷新目录和详情；保留用户当前折叠状态。
func _refresh_tasks() -> void:
	if _directory == null or _closing:
		return

	if Global.global_game_state.adventure_state != _opened_state:
		request_close()
		return
	_tasks = AdventureQuestService.rows(_opened_state)
	_rows.clear()
	for child: Node in _directory.get_children(): # 只替换动态列表。
		child.queue_free()
		_directory.remove_child(child)
	_build_directory()
	_select_task(_selected)

## 教学选择 [param id]，返回实际领取按钮；不触发领取、不改变任务数据。
func guide_reward(id: String) -> Control:
	if _selected != id:
		_select_task(id)
	return _claim_button

## Escape 与关闭按钮使用相同生命周期。
func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		request_close()
		get_viewport().set_input_as_handled()

## 发出关闭通知并销毁本窗口，重复请求不会触发两次。
func request_close() -> void:
	if _closing:
		return
	_closing = true
	closed.emit()
	queue_free()
