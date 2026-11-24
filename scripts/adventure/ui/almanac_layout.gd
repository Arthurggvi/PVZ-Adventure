## 图鉴固定画布；负责分类、搜索、故事和阶级栏，业务选择交给窗口宿主。
extends Control

## 请求宿主关闭模态窗口。
signal close_requested
## 请求切换分类；参数为 plant、zombie、boss 或 buff。
signal kind_requested(kind: String)
## 请求按当前文字重新筛选目录。
signal search_changed(value: String)
## 请求查看一至五阶中的指定阶级。
signal tier_requested(tier: int)
## 复用背包已有的木框与羊皮纸。
const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")
## 统一选择按钮的状态样式。
const Style = preload("res://scripts/adventure/ui/almanac_style.gd")
## 轶事沿用统一的内容滚动区。
const ContentScroll = preload("res://scripts/ui/content_scroll.gd")
## 目录拥有自己的滚动区与可见头像状态。
const Directory = preload("res://scripts/adventure/ui/almanac_directory.gd")
## 右侧详情拥有动态内容的构造与清理。
const DetailPanel = preload("res://scripts/adventure/ui/almanac_detail_panel.gd")
## Boss 故事沿用独立资料。
const BossData = preload("res://scripts/adventure/ui/boss_almanac_data.gd")
## Boss 故事的阅读字体与纸面配色。
const BossSkin = preload("res://scripts/adventure/ui/boss_almanac_style.gd")
## 与原图鉴一致的设计画布尺寸。
const DESIGN: Vector2 = Vector2(1480, 830)
## 现有中文界面字体。
const FONT: Font = preload("res://assets/fonts/方正少儿_GBK.ttf")
## 旧版图鉴入口仅显示 Boss；在入树前设置。
var boss_only: bool = false
## 宿主可重建和高亮的目录组件。
var directory: Directory
## 宿主在资源准备完成后才装配的详情组件。
var details: DetailPanel
## 分类按钮按类别索引。
var _tabs: Dictionary[String, Button] = {}
## 搜索输入随分类更新提示，搜索词本身保持不变。
var _search: LineEdit
## 只有植物、僵尸可见的五阶栏。
var _tier_rail: Control
## 从一阶到五阶排列的选择按钮。
var _tier_buttons: Array[Button] = []
## Boss 目录下方的独立故事卡。
var _boss_story: Control
## 选择 Boss 后更新的人物轶事标题。
var _story_title: Label
## 完整保留原文并允许换行的故事正文。
var _story_body: Label
## 切换 Boss 后回到故事起点。
var _story_scroll: ScrollContainer

## 创建固定布局；分类、搜索与阶级按钮只发信号，不改动档案。
func _ready() -> void:
	name = "AlmanacCanvas"
	size = DESIGN
	theme = Theme.new()
	theme.default_font = FONT
	Art.panel(self, "panels/wood_ninepatch.png", Vector2.ZERO, DESIGN, 35)
	Art.panel(self, "panels/outer_frame_ninepatch.png", Vector2.ZERO, DESIGN, 42)
	Art.image(self, "res://assets/adventure/ui/bottom_bar/icons/icon_deck.png", Vector2(38, 27), Vector2(64, 64))
	Art.label(self, "Boss 图鉴" if boss_only else "冒险图鉴", Vector2(112, 29), Vector2(310, 60), 40, Color("ffe8b0"))
	Art.button(self, "controls/close", Vector2(1364, 28), Vector2(65, 65), close_requested.emit)
	Art.panel(self, "panels/parchment_ninepatch.png", Vector2(35, 112), Vector2(445, 678), 30)
	Art.panel(self, "panels/parchment_ninepatch.png", Vector2(495, 112), Vector2(950, 678), 30)
	_build_tabs_and_search()
	directory = Directory.new()
	directory.position = Vector2(58, 260)
	add_child(directory)
	_build_boss_story()
	details = DetailPanel.new()
	details.position = Vector2(515, 128)
	details.size = Vector2(910, 640)
	add_child(details)
	_build_tier_rail()

## 根据 [param available] 等比居中，并为底部工具栏保留交互空间。
func fit_to(available: Vector2) -> void:
	var factor: float = maxf(0.1, minf((available.x - 36.0) / DESIGN.x, (available.y - 140.0) / DESIGN.y)) # 避免面板与角色拉伸。
	scale = Vector2.ONE * factor
	position = Vector2((available.x - DESIGN.x * factor) * 0.5, maxf(0.0, (available.y - 120.0 - DESIGN.y * factor) * 0.5))

## 立即同步 [param kind]、[param type_id]、[param tier] 的控件状态；不等待详情加载，避免旧阶级栏或故事残留。
func set_selection(kind: String, type_id: int, tier: int) -> void:
	for tab_kind: String in _tabs: # 分类按钮保持唯一选中。
		_tabs[tab_kind].set_pressed_no_signal(tab_kind == kind)
	directory.set_selected(type_id)
	_search.placeholder_text = "搜索名称 / 效果 / 来源" if kind == "buff" else "搜索名称"
	_tier_rail.visible = type_id != 0 and (kind == "plant" or kind == "zombie")
	for index: int in range(_tier_buttons.size()): # 五阶选择节点固定，保留键盘焦点。
		_tier_buttons[index].set_pressed_no_signal(index + 1 == tier)
	_boss_story.visible = kind == "boss" and type_id != 0
	if _boss_story.visible:
		_story_title.text = "%s · 轶事" % BossData.title_for(type_id)
		_story_body.text = str(BossData.STORIES.get(type_id, ""))
		_story_scroll.scroll_vertical = 0

## 四类按钮总宽 396 像素，完整放入左侧 397 像素区域；旧 Boss 入口保持单一标签。
func _build_tabs_and_search() -> void:
	var kinds: PackedStringArray = PackedStringArray(["boss"] if boss_only else ["plant", "zombie", "boss", "buff"]) # 明确固定分类顺序。
	var titles: Dictionary[String, String] = {"plant": "植物", "zombie": "僵尸", "boss": "Boss", "buff": "Buff"} # 短标题避免挤占标签宽度。
	for index: int in range(kinds.size()): # 每个分类绑定自己的稳定标识。
		var kind: String = kinds[index] # 回调绑定当前值，不依赖循环结束后的变量。
		var tab: Button = Style.selection_button(self, titles[kind], "tabs/tab", kind_requested.emit.bind(kind)) # 沿用原分类纹理。
		tab.position = Vector2(58 + index * 101, 133)
		tab.size = Vector2(126 if boss_only else 93, 51)
		_tabs[kind] = tab
	Art.panel(self, "controls/search_field.png", Vector2(59, 198), Vector2(396, 48), 12)
	Art.image(self, "icons/search_magnifier.png", Vector2(72, 208), Vector2(27, 27))
	_search = LineEdit.new()
	_search.position = Vector2(105, 204)
	_search.size = Vector2(337, 36)
	_search.placeholder_text = "搜索名称"
	_search.flat = true
	_search.add_theme_color_override("font_color", Color("382719"))
	_search.add_theme_color_override("font_placeholder_color", Color("77654d"))
	_search.add_theme_font_size_override("font_size", 22)
	_search.text_changed.connect(search_changed.emit)
	add_child(_search)

## Boss 故事利用目录下方留白；其他分类恢复完整目录高度并隐藏此卡片。
func _build_boss_story() -> void:
	_boss_story = Control.new()
	_boss_story.position = Vector2(61, 429)
	_boss_story.size = Vector2(391, 288)
	add_child(_boss_story)
	BossSkin.card(_boss_story, Rect2(0, 0, 391, 288), Color(1, 0.96, 0.85, 0.4))
	_story_title = BossSkin.label(_boss_story, "", Rect2(17, 14, 355, 32), 24, BossSkin.MUTED, false)
	_story_scroll = ContentScroll.new()
	_story_scroll.position = Vector2(18, 58)
	_story_scroll.size = Vector2(355, 213)
	_boss_story.add_child(_story_scroll)
	_story_body = BossSkin.label(_story_scroll, "", Rect2(), 21)
	_story_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_story_body.add_theme_constant_override("line_spacing", 7)

## 将五阶入口放在同一木质底座，保留原有等宽排列与点击语义。
func _build_tier_rail() -> void:
	_tier_rail = Control.new()
	_tier_rail.position = Vector2(532, 655)
	_tier_rail.size = Vector2(876, 107)
	add_child(_tier_rail)
	Art.panel(_tier_rail, "panels/wood_ninepatch.png", Vector2.ZERO, _tier_rail.size, 28)
	Art.label(_tier_rail, "阶级", Vector2(25, 28), Vector2(75, 50), 25, Color("ffe6b0"))
	for tier: int in range(1, 6): # 一至五阶从左到右排列。
		var button: Button = Style.selection_button(_tier_rail, "%d 阶" % tier, "buttons/button", tier_requested.emit.bind(tier)) # 切阶后选中项保持金边。
		button.position = Vector2(112 + (tier - 1) * 148, 24)
		button.size = Vector2(139, 60)
		_tier_buttons.append(button)
