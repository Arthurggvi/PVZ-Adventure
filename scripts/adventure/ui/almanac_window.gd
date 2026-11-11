## 冒险图鉴模态窗口；按物种发现解锁全部五阶，所有内容实时读取现有玩法目录。
extends Control

## 由工具栏统一清理模态引用。
signal closed
## 背包已有木框、羊皮纸和按钮素材。
const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")
## 只读目录与详情数据。
const Data = preload("res://scripts/adventure/ui/almanac_data.gd")
## 无战斗行为的角色形象适配器。
const Preview = preload("res://scripts/adventure/ui/almanac_preview.gd")
## 与任务簿相同的设计画布尺寸。
const DESIGN := Vector2(1480, 830)
## 现有中文界面字体。
const FONT = preload("res://assets/fonts/方正少儿_GBK.ttf")
## 左侧三列头像卡的设计尺寸，预留滚动条后仍能放下三列。
const TILE_SIZE := Vector2(121, 140)
## 打开时所属档案，切档时不继续展示旧记录。
var _state: AdventureState
## 当前分类为 plant 或 zombie，不保存到玩家档案。
var _kind := "plant"
## 当前中文名称搜索文本。
var _search := ""
## 当前选中物种；0 表示空目录。
var _selected: int = 0
## 当前查看阶级，首次选中物种默认一阶。
var _tier: int = 1
## 等比缩放的面板根节点。
var _canvas: Control
## 目录网格的滚动容器。
var _directory_scroll: ScrollContainer
## 已发现物种的三列头像卡。
var _directory: GridContainer
## 目录没有内容时居中显示简短状态。
var _empty: Label
## 详情动态内容根节点。
var _details: Control
## 显示当前已收录数量。
var _count: Label
## 分类按钮，通过按下状态强调当前分类。
var _tabs: Dictionary = {}
## 头像卡按钮，用物种编号索引。
var _tiles: Dictionary[int, Button] = {}
## 详情下方的阶级选择器。
var _tier_rail: Control
## 由低到高排列的五个阶级按钮。
var _tier_buttons: Array[Button] = []
## 防止关闭动画期间重复操作。
var _closing := false

## 建立复用素材布局，并绑定档案与发现变化通知。
func _ready() -> void:
	_state = Global.global_game_state.adventure_state
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = Theme.new()
	theme.default_font = FONT
	var shade := ColorRect.new() # 模态暗幕拦截地图点击，工具栏仍由自己的层级管理。
	shade.color = Color(0.035, 0.045, 0.025, 0.72)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	_canvas = Control.new()
	_canvas.name = "AlmanacCanvas"
	_canvas.size = DESIGN
	add_child(_canvas)
	Art.panel(_canvas, "panels/wood_ninepatch.png", Vector2.ZERO, DESIGN, 35)
	Art.panel(_canvas, "panels/outer_frame_ninepatch.png", Vector2.ZERO, DESIGN, 42)
	Art.image(_canvas, "res://assets/adventure/ui/bottom_bar/icons/icon_deck.png", Vector2(38, 27), Vector2(64, 64))
	Art.label(_canvas, "冒险图鉴", Vector2(112, 29), Vector2(310, 60), 40, Color("ffe8b0"))
	Art.button(_canvas, "controls/close", Vector2(1364, 28), Vector2(65, 65), request_close)
	Art.panel(_canvas, "panels/parchment_ninepatch.png", Vector2(35, 112), Vector2(445, 678), 30)
	Art.panel(_canvas, "panels/parchment_ninepatch.png", Vector2(495, 112), Vector2(950, 678), 30)
	for index: int in range(2): # 两类物种共享详情布局。
		var kind: String = "plant" if index == 0 else "zombie" # 绑定值不依赖循环结束后的变量。
		var tab: Button = _selection_button(_canvas, "植物" if index == 0 else "僵尸", "tabs/tab", _choose_kind.bind(kind)) # 复用背包分类的选中纹理。
		tab.position = Vector2(58 + index * 201, 133)
		tab.size = Vector2(191, 51)
		_tabs[kind] = tab
	Art.panel(_canvas, "controls/search_field.png", Vector2(59, 198), Vector2(396, 48), 12)
	Art.image(_canvas, "icons/search_magnifier.png", Vector2(72, 208), Vector2(27, 27))
	var search := LineEdit.new() # 搜索仅在当前分类中过滤已发现条目。
	search.position = Vector2(105, 204)
	search.size = Vector2(337, 36)
	search.placeholder_text = "搜索名称"
	search.flat = true
	search.add_theme_color_override("font_color", Color("382719"))
	search.add_theme_color_override("font_placeholder_color", Color("77654d"))
	search.add_theme_font_size_override("font_size", 22)
	search.text_changed.connect(_search_changed)
	_canvas.add_child(search)
	_directory_scroll = ScrollContainer.new()
	_directory_scroll.position = Vector2(58, 260)
	_directory_scroll.size = Vector2(397, 462)
	_directory_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_canvas.add_child(_directory_scroll)
	_directory = GridContainer.new()
	_directory.columns = 3
	_directory.add_theme_constant_override("h_separation", 9)
	_directory.add_theme_constant_override("v_separation", 9)
	_directory_scroll.add_child(_directory)
	_empty = Art.label(_canvas, "", Vector2(58, 424), Vector2(397, 60), 24, Color("796347"))
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count = Art.label(_canvas, "", Vector2(63, 730), Vector2(385, 38), 20, Color("6a5035"))
	_details = Control.new()
	_details.position = Vector2(515, 128)
	_details.size = Vector2(910, 520)
	_canvas.add_child(_details)
	_build_tier_rail()
	Global.almanac_changed.connect(_refresh)
	Global.user_manager.signal_users_update.connect(_profile_changed)
	resized.connect(_fit)
	_refresh()
	_fit()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.18)
	SoundManager.play_other_SFX(&"buttonclick")

## 等比居中，并为底部工具栏保留交互空间。
func _fit() -> void:
	var factor: float = maxf(0.1, minf((size.x - 36.0) / DESIGN.x, (size.y - 140.0) / DESIGN.y)) # 统一比例避免面板与角色拉伸。
	_canvas.scale = Vector2.ONE * factor
	_canvas.position = Vector2((size.x - DESIGN.x * factor) * 0.5, maxf(0.0, (size.y - 120.0 - DESIGN.y * factor) * 0.5))

## 切换到 [param kind] 分类；新类别从一阶开始，保留搜索词。
func _choose_kind(kind: String) -> void:
	if _closing:
		return
	_kind = kind
	_selected = 0
	_tier = 1
	_directory_scroll.scroll_vertical = 0
	_refresh()
	SoundManager.play_other_SFX(&"tap")

## 根据 [param value] 更新搜索，过滤后选择首个可见物种。
func _search_changed(value: String) -> void:
	_search = value
	_directory_scroll.scroll_vertical = 0
	_refresh()

## 按真实发现记录重建目录；没有记录或搜索无结果时给出明确提示。
func _refresh() -> void:
	if _closing or _state != Global.global_game_state.adventure_state:
		return
	_clear(_directory)
	_tiles.clear()
	for kind: String in _tabs: # 保持分类按钮状态与当前目录一致。
		_tabs[kind].set_pressed_no_signal(kind == _kind)
	var entries: Array[Dictionary] = Data.rows(_state, _kind, _search) # 过滤后的目录快照。
	_count.text = ("已收录 %d 种" if _search.strip_edges().is_empty() else "%d 项结果") % entries.size()
	for entry: Dictionary in entries: # 目录中的预览只使用一阶形象，不产生遇敌记录。
		var type_id: int = int(entry.type_id) # 稳定物种编号用于选择与高亮。
		var title: String = str(entry.title) # 悬停时可看见被省略的长名称。
		var button: Button = _selection_button(_directory, "", "slots/plant_slot", _select.bind(type_id)) # 卡面和名称共用一个点击目标。
		button.custom_minimum_size = TILE_SIZE
		button.tooltip_text = title
		button.accessibility_name = title
		Preview.draw(button, _kind, type_id, 1, Rect2(15, 13, 91, 86))
		var caption: Label = Art.label(button, title, Vector2(10, 102), Vector2(101, 26), 18) # 卡片下部统一保留名称区。
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_tiles[type_id] = button
	if not _tiles.has(_selected):
		_selected = int(entries[0].type_id) if not entries.is_empty() else 0
		_tier = 1
	_empty.visible = entries.is_empty()
	_empty.text = "暂无条目" if _search.strip_edges().is_empty() else "无匹配结果"
	_render_detail()

## 选择 [param type_id] 并回到一阶；非法物种不改变详情。
func _select(type_id: int) -> void:
	if _closing or not _tiles.has(type_id):
		return
	if _selected == type_id:
		_tiles[type_id].set_pressed_no_signal(true)
		return
	_selected = type_id
	_tier = 1
	_render_detail()
	SoundManager.play_other_SFX(&"tap")

## 查看 [param tier]；物种发现即允许切换全部五阶，不受库存卡等级限制。
func _choose_tier(tier: int) -> void:
	if _closing or _selected == 0:
		return
	if tier == _tier:
		_tier_buttons[tier - 1].set_pressed_no_signal(true)
		return
	_tier = clampi(tier, 1, 5)
	_render_detail()
	SoundManager.play_other_SFX(&"tap")

## 重建形象和说明；保持阶级选择器节点，切换时保留键盘焦点。
func _render_detail() -> void:
	_clear(_details)
	for type_id: int in _tiles: # 更新头像卡选中状态。
		_tiles[type_id].set_pressed_no_signal(type_id == _selected)
	_tier_rail.visible = _selected != 0
	if _selected == 0:
		return
	for index: int in range(_tier_buttons.size()): # 阶级按钮用统一的亮边区分选中态。
		_tier_buttons[index].set_pressed_no_signal(index + 1 == _tier)
	Art.label(_details, Data.character_name(_kind, _selected), Vector2(18, 3), Vector2(880, 60), 40)
	Art.panel(_details, "panels/wood_ninepatch.png", Vector2(19, 72), Vector2(874, 4), 2)
	var holder := Control.new() # 框内裁剪待机动画和地面背景。
	holder.position = Vector2(42, 115)
	holder.size = Vector2(304, 363)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.clip_contents = true
	_details.add_child(holder)
	var background := TextureRect.new() # 复用图鉴原有的环境贴图。
	var grounds: Dictionary = AlmanacCharacterShowPanel.CHARACTER_BG_MAP # 保持昼夜、水陆等角色背景对应关系。
	background.texture = grounds.get(Data.entry(_kind, _selected).get("背景", "Day"), grounds["Day"])
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not Preview.draw_idle(holder, _kind, _selected, _tier, Rect2(35, 39, 234, 284)):
		Art.label(holder, "无", Vector2(140, 151), Vector2(45, 56), 24)
	Art.panel(_details, "panels/outer_frame_ninepatch.png", Vector2(17, 90), Vector2(354, 413), 40)
	_render_sections(Data.detail(_kind, _selected, _tier))

## 用 [param asset] 的普通、悬停和选中素材构造 [param parent] 下的按钮，显示 [param title] 并连接 [param action]。
func _selection_button(parent: Control, title: String, asset: String, action: Callable) -> Button:
	var button := Button.new() # 同一个控件承接键盘与鼠标输入。
	button.text = title
	button.toggle_mode = true
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 24)
	button.add_theme_color_override("font_color", Color("fff0ce"))
	button.add_theme_color_override("font_hover_color", Color("fff6de"))
	button.add_theme_color_override("font_pressed_color", Color("fff6de"))
	button.add_theme_color_override("font_outline_color", Color("3e2518"))
	button.add_theme_constant_override("outline_size", 2)
	button.add_theme_stylebox_override("normal", Art.texture_style(asset + "_normal.png", 14.0))
	button.add_theme_stylebox_override("hover", Art.texture_style(asset + "_hover.png", 14.0))
	button.add_theme_stylebox_override("pressed", Art.texture_style(asset + "_selected.png", 14.0))
	button.add_theme_stylebox_override("hover_pressed", Art.texture_style(asset + "_selected.png", 14.0))
	var focus := StyleBoxFlat.new() # 焦点环只描边，避免盖住选中纹理。
	focus.draw_center = false
	focus.border_color = Color("fff2bd")
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(9)
	button.add_theme_stylebox_override("focus", focus)
	button.pressed.connect(action)
	parent.add_child(button)
	return button

## 将五阶入口放在同一块木质底座上，并保持等宽与统一间距。
func _build_tier_rail() -> void:
	_tier_rail = Control.new()
	_tier_rail.position = Vector2(532, 655)
	_tier_rail.size = Vector2(876, 107)
	_canvas.add_child(_tier_rail)
	Art.panel(_tier_rail, "panels/wood_ninepatch.png", Vector2.ZERO, _tier_rail.size, 28)
	Art.label(_tier_rail, "阶级", Vector2(25, 28), Vector2(75, 50), 25, Color("ffe6b0"))
	for tier: int in range(1, 6): # 从一阶至五阶依次排列。
		var button: Button = _selection_button(_tier_rail, "%d 阶" % tier, "buttons/button", _choose_tier.bind(tier)) # 切阶后选中项保持金边。
		button.position = Vector2(112 + (tier - 1) * 148, 24)
		button.size = Vector2(139, 60)
		_tier_buttons.append(button)

## 将 [param info] 的能力、属性和效果拆成可独立阅读的区块，长说明可滚动。
func _render_sections(info: Dictionary) -> void:
	var scroll := ScrollContainer.new() # 阶级栏固定，只有说明内容滚动。
	scroll.position = Vector2(391, 90)
	scroll.size = Vector2(504, 413)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_details.add_child(scroll)
	var sections := VBoxContainer.new() # 按基础能力、数值、阶级效果和基础特性排列。
	sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sections.add_theme_constant_override("separation", 11)
	scroll.add_child(sections)

	var ability: VBoxContainer = _section(sections, "基础能力") # 一段可换行的基础说明。
	_text(ability, str(info.summary), 20, Color("382719"))

	var stat_section: VBoxContainer = _section(sections, "属性") # 属性名和值在独立数值格中对齐。
	var stats := HBoxContainer.new() # 植物与僵尸使用各自的数值字段。
	stats.add_theme_constant_override("separation", 8)
	stat_section.add_child(stats)
	for stat: String in info.stats: # 数值与标签上下排列。
		var cell: VBoxContainer = _section(stats, "") # 数值格平分当前可用宽度。
		var value: Label = _text(cell, str(info.stats[stat]), 23, Color("382719")) # 保留倍率或秒数单位。
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var caption: Label = _text(cell, stat, 17, Color("76583a")) # 属性名使用次级色。
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var effects: VBoxContainer = _section(sections, "阶级效果") # 当前阶优先，已有的低阶转职分组随后列出。
	if info.effects.is_empty():
		_text(effects, "无", 20, Color("76583a"))
	for group: Dictionary in info.effects: # 僵尸的效果没有额外阶级标题。
		var effect_group: VBoxContainer = effects # 只有多个阶级时才增加分组卡和阶数。
		if info.effects.size() > 1:
			effect_group = _section(effects, str(group.title))
		if group.options.is_empty():
			_text(effect_group, "无", 20, Color("76583a"))
		for option: String in group.options: # 分支名与说明各占一行，支持长效果换行。
			if not option.is_empty():
				_text(effect_group, option, 20, Color("654023"))
			_text(effect_group, str(group.options[option]), 20, Color("382719"))

	if not info.traits.is_empty():
		var traits: VBoxContainer = _section(sections, "基础特性") # 原有条目放在主要能力之后。
		for property_name: String in info.traits: # 每条基础特性单独占一行。
			_text(traits, "%s  %s" % [property_name, str(info.traits[property_name])], 19, Color("654b30"))

## 在 [param parent] 下创建带浅色底和内边距的区块；[param title] 为空时省略标题。
func _section(parent: Container, title: String) -> VBoxContainer:
	var panel := PanelContainer.new() # 区块高度随内容增长。
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new() # 从羊皮纸底色中略微提亮，便于辨认阅读区块。
	style.bg_color = Color(1.0, 0.95, 0.81, 0.56) if not title.is_empty() else Color(0.67, 0.46, 0.25, 0.12)
	style.border_color = Color(0.48, 0.29, 0.14, 0.23)
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	style.content_margin_left = 13
	style.content_margin_right = 13
	style.content_margin_top = 9
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var column := VBoxContainer.new() # 标题和内容之间保留统一行距。
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)
	if not title.is_empty():
		_text(column, title, 22, Color("824820"))
	return column

## 在 [param parent] 中追加可换行的 [param caption]，使用 [param font_size] 和 [param ink]。
func _text(parent: Container, caption: String, font_size: int, ink: Color) -> Label:
	var label := Label.new() # 普通文字保留数据中的原始符号。
	label.text = caption
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", ink)
	label.add_theme_constant_override("line_spacing", 4)
	parent.add_child(label)
	return label

## 清理 [param parent] 的动态内容，当前帧即移除以避免多套角色同时显示。
func _clear(parent: Node) -> void:
	for child: Node in parent.get_children(): # 不保留隐藏的旧预览或旧按钮连接。
		parent.remove_child(child)
		child.queue_free()

## 档案切换后关闭旧图鉴；同一档案重命名不影响收录。
func _profile_changed() -> void:
	if _state != Global.global_game_state.adventure_state:
		request_close()

## [param event] 为当前输入；按 Esc 关闭并拦截事件，防止传到地图或其他窗口。
func _input(event: InputEvent) -> void:
	if not _closing and event.is_action_pressed(&"ui_cancel"):
		request_close()
		get_viewport().set_input_as_handled()

## 遵守工具栏统一模态契约，关闭后发出一次 closed 信号。
func request_close() -> void:
	if _closing:
		return
	_closing = true
	SoundManager.play_other_SFX(&"buttonclick")
	var tween: Tween = create_tween() # 短淡出不改变宿主场景或玩家资产。
	tween.tween_property(self, "modulate:a", 0.0, 0.15)
	tween.tween_callback(func() -> void: closed.emit(); queue_free())
