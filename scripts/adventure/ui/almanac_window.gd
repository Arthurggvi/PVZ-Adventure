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
## 目录行的滚动容器。
var _directory_scroll: ScrollContainer
## 已发现物种的纵向目录。
var _directory: VBoxContainer
## 详情动态内容根节点。
var _details: Control
## 显示当前已收录数量。
var _count: Label
## 分类按钮，通过按下状态强调当前分类。
var _tabs: Dictionary = {}
## 当前目录按钮，用物种编号索引。
var _rows: Dictionary = {}
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
	Art.label(_canvas, "遇见一次，即可查看全部五阶", Vector2(480, 36), Vector2(750, 48), 25, Color("ffe8b0"))
	Art.button(_canvas, "controls/close", Vector2(1364, 28), Vector2(65, 65), request_close)
	Art.panel(_canvas, "panels/parchment_ninepatch.png", Vector2(35, 112), Vector2(445, 678), 30)
	Art.panel(_canvas, "panels/parchment_ninepatch.png", Vector2(495, 112), Vector2(950, 678), 30)
	for index: int in range(2): # 两类物种共享详情布局。
		var kind: String = "plant" if index == 0 else "zombie" # 绑定值不依赖循环结束后的变量。
		var tab: Button = Art.action_button(_canvas, "植物" if index == 0 else "僵尸", "buttons/action_neutral", Vector2(58 + index * 204, 133), Vector2(190, 53), _choose_kind.bind(kind)) # 复用按钮状态素材。
		tab.toggle_mode = true
		_tabs[kind] = tab
	Art.panel(_canvas, "controls/search_field.png", Vector2(59, 198), Vector2(396, 48), 12)
	var search := LineEdit.new() # 搜索仅在当前分类中过滤已发现条目。
	search.position = Vector2(72, 204)
	search.size = Vector2(367, 36)
	search.placeholder_text = "搜索已收录的名称"
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
	_directory = VBoxContainer.new()
	_directory.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_directory.add_theme_constant_override("separation", 7)
	_directory_scroll.add_child(_directory)
	_count = Art.label(_canvas, "", Vector2(63, 730), Vector2(385, 38), 21)
	_details = Control.new()
	_details.position = Vector2(515, 128)
	_details.size = Vector2(910, 640)
	_canvas.add_child(_details)
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
	_rows.clear()
	for kind: String in _tabs: # 保持分类按钮状态与当前目录一致。
		_tabs[kind].set_pressed_no_signal(kind == _kind)
	var entries: Array[Dictionary] = Data.rows(_state, _kind, _search) # 过滤后的目录快照。
	var total: int = Data.rows(_state, _kind).size() # 搜索结果数与已收录总数分别显示。
	_count.text = "已收录 %d 种 · 当前 %d 种" % [total, entries.size()]
	for entry: Dictionary in entries: # 目录中的预览只使用一阶形象，不产生遇敌记录。
		var type_id: int = int(entry.type_id) # 稳定物种编号用于选择与高亮。
		var button: Button = Art.action_button(_directory, str(entry.title), "buttons/action_neutral", Vector2.ZERO, Vector2.ZERO, _select.bind(type_id)) # 每个目录项都是独立焦点与点击目标。
		button.custom_minimum_size = Vector2(0, 77)
		button.toggle_mode = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.add_theme_font_size_override("font_size", 23)
		for style_name: String in ["normal", "hover", "pressed", "disabled", "focus"]: # 给左侧角色缩略图留出位置。
			var style: StyleBox = button.get_theme_stylebox(style_name).duplicate() # 不修改其他按钮共享样式。
			style.content_margin_left = 87.0
			button.add_theme_stylebox_override(style_name, style)
		Preview.draw(button, _kind, type_id, 1, Rect2(14, 9, 61, 59))
		_rows[type_id] = button
	if not _rows.has(_selected):
		_selected = int(entries[0].type_id) if not entries.is_empty() else 0
		_tier = 1
	if entries.is_empty():
		var empty := Label.new() # 空列表也提供明确原因。
		empty.text = "尚未收录\n获得植物或在冒险实战遇到后解锁。" if total == 0 else "没有匹配的名称。"
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_color_override("font_color", Color("654b30"))
		empty.add_theme_font_size_override("font_size", 23)
		_directory.add_child(empty)
	_render_detail()

## 选择 [param type_id] 并回到一阶；非法物种不改变详情。
func _select(type_id: int) -> void:
	if _closing or not _rows.has(type_id):
		return
	_selected = type_id
	_tier = 1
	_render_detail()
	SoundManager.play_other_SFX(&"tap")

## 查看 [param tier]；物种发现即允许切换全部五阶，不受库存卡等级限制。
func _choose_tier(tier: int) -> void:
	if _closing or _selected == 0:
		return
	_tier = clampi(tier, 1, 5)
	_render_detail()
	SoundManager.play_other_SFX(&"tap")

## 重建形象、说明及五阶按钮；旧视觉节点先移出树，避免快速切换重叠。
func _render_detail() -> void:
	_clear(_details)
	for type_id: int in _rows: # 目录高亮不依赖按钮点击后的默认切换状态。
		_rows[type_id].set_pressed_no_signal(type_id == _selected)
	if _selected == 0:
		Art.label(_details, "选择已收录的植物或僵尸", Vector2(90, 220), Vector2(740, 70), 33)
		return
	Art.label(_details, "%s · %d 阶" % [Data.character_name(_kind, _selected), _tier], Vector2(18, 0), Vector2(870, 64), 34)
	Art.image(_details, "res://assets/image/Almanac/Almanac_GroundDay.jpg", Vector2(20, 83), Vector2(300, 300))
	var holder := Control.new() # 预览单独持有视觉副本，切换时整体释放。
	holder.position = Vector2(30, 93)
	holder.size = Vector2(280, 280)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_details.add_child(holder)
	if not Preview.draw(holder, _kind, _selected, _tier, Rect2(10, 10, 260, 260)):
		Art.label(holder, "暂无形象", Vector2(60, 100), Vector2(180, 60), 26)
	Art.label(_details, "已解锁全部 1–5 阶", Vector2(26, 400), Vector2(300, 42), 23)
	var hint: Label = Art.label(_details, "未配置专属形象时\n沿用已有外观", Vector2(26, 446), Vector2(300, 72), 21, Color("796347")) # 不承诺未实现的形态。
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var text := RichTextLabel.new() # 长技能说明在固定区域滚动，不挤压阶级切换按钮。
	text.position = Vector2(350, 81)
	text.size = Vector2(533, 457)
	text.bbcode_enabled = false
	text.text = Data.description(_kind, _selected, _tier)
	text.add_theme_font_size_override("normal_font_size", 23)
	text.add_theme_color_override("default_color", Color("382719"))
	text.add_theme_constant_override("line_separation", 7)
	_details.add_child(text)
	for tier: int in range(1, 6): # 所有阶级永远可点，仅受物种发现状态约束。
		var button: Button = Art.action_button(_details, "%d 阶" % tier, "buttons/action_neutral", Vector2(23 + (tier - 1) * 176, 565), Vector2(160, 58), _choose_tier.bind(tier)) # 同时提供鼠标和键盘焦点操作。
		button.toggle_mode = true
		button.set_pressed_no_signal(tier == _tier)

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
