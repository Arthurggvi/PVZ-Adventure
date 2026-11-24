## 在研究室原工作区打开规则页，负责阅读导航与开合动效。
extends Control

## 退场后通知研究室还原操作区。
signal closed

## 纸面、按钮和标题沿用研究室外框的素材。
const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")
## 与正常工作区、操作栏共用设计坐标。
const Layout = preload("res://scripts/adventure/ui/research_panel_skin.gd")
## 复用原模式名称，确保标题和返回按钮一致。
const Meta = preload("res://scripts/adventure/ui/research_ui_meta.gd")
## 规则文本和数据排版的入口。
const Content = preload("res://scripts/adventure/ui/research_rules_content.gd")
## 页眉、题签和正文共用字族及纸面配色。
const Style = preload("res://scripts/adventure/ui/research_rules_style.gd")
## 开合动效由已有组件负责，可靠处理入场中途退出。
const Motion = preload("res://scripts/ui/transitions/modal_motion.gd")
## 强化说明占三页，概率页始终是初次打开的位置。
const CHAPTERS := ["成功率", "耗材", "道具与保星"]

## 入树前由研究室指定，可为强化或转职。
var mode: String = "upgrade"
## 章节的固定裁剪区，换页位移不会越过纸边。
var _body: Control
## 当前章节序号，尚未绘制时为 -1。
var _chapter: int = -1
## 当前有效的章节淡入动效。
var _chapter_motion: Tween
## 规则纸和返回按钮共用的开合动效。
var _motion: Motion

## 构建纸面、首章和底栏返回按钮，随后从工作区下侧轻微滑入。
func _ready() -> void:
	name = "ResearchRules"
	size = Layout.DESIGN
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Style.prepare()
	var surface := Control.new() # 整页动效的目标，不影响研究室缩放坐标。
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.size = Layout.DESIGN
	add_child(surface)
	var area := Rect2(Layout.SELECTION_REGION.position,
		Layout.INFO_REGION.end - Layout.SELECTION_REGION.position) # 横跨原先三张工作面板。
	var paper: NinePatchRect = Art.panel(surface, "panels/parchment_ninepatch.png", area.position, area.size, 30) # 与日常操作面板同一纸边。
	var cover_color: Color = Style.FOREST if mode == "upgrade" else Style.PLUM # 两种规则封面与正文主色呼应。
	var header: Panel = Style.panel(paper, Rect2(38, 20, area.size.x - 76, 76), cover_color, Style.EDGE) # 深色页眉把章节导航和纸面正文分开。
	var icon: String = "overlays/star_filled.png" if mode == "upgrade" else "icons/category_plants.png" # 和主导航使用相同图案。
	Art.image(header, icon, Vector2(21, 12), Vector2(52, 52))
	Style.label(header, Meta.title(mode) + "规则", Rect2(85, 0, 575, header.size.y), 40, Style.CREAM, Style.bold)
	_body = Control.new()
	_body.position = Vector2(38, 112)
	_body.size = area.size - Vector2(76, 148)
	_body.clip_contents = true
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper.add_child(_body)
	if mode == "upgrade":
		_draw_chapters(header)
	_select_chapter(0, false)
	var return_button: Button = Art.action_button(surface, "返回" + Meta.title(mode), "buttons/action_neutral",
		Layout.ACTION_REGION.position, Layout.ACTION_REGION.size, dismiss) # 处在阅读前操作按钮的位置。
	return_button.name = "ResearchRulesReturn"
	return_button.add_theme_font_size_override("font_size", 30)
	return_button.add_theme_font_override("font", Style.bold)
	_motion = Motion.new()
	_motion.target = surface
	_motion.hidden_scale = 0.988
	_motion.hidden_offset = Vector2(0, 22)
	_motion.close_seconds = 0.17
	_motion.closed.connect(_on_motion_closed)
	add_child(_motion)
	_motion.play_open()

## 关闭规则页；主导航同时发声时，[param play_sound] 可关闭此处的音效。
func dismiss(play_sound: bool = true) -> void:
	if _motion.phase == Motion.Phase.CLOSING:
		return
	if play_sound:
		SoundManager.play_other_SFX(&"tap")
	_motion.play_close()

## 在 [param header] 右侧添加互斥的章节题签，保持阅读页标题位置不动。
func _draw_chapters(header: Control) -> void:
	var group := ButtonGroup.new() # 始终保留一个活动章节。
	var width: float = 198.0 # 含五字章节名和两侧内边距。
	var stride: float = width + 10.0 # 同组按钮等距排列。
	var start: float = header.size.x - 16 - (stride * CHAPTERS.size() - 10) # 最右题签与封面保留边距。
	var idle: StyleBoxFlat = Style.box(Color("fff1d211"), Color("d9b97752"), 8) # 未选题签留出封面底色。
	var hover: StyleBoxFlat = Style.box(Color("fff1d22b"), Style.GOLD, 8) # 鼠标经过时浅金提亮。
	var selected: StyleBoxFlat = Style.box(Style.GOLD, Color("ffe3a4"), 8) # 金色题签突出当前章节。
	var focus: StyleBoxFlat = Style.box(Color.TRANSPARENT, Color("fff1d2"), 8) # 键盘描边保留底下的题签颜色。
	focus.set_border_width_all(2)
	for index: int in range(CHAPTERS.size()): # 标签顺序与规则内容一致。
		var button := Button.new() # 每个题签共享尺寸，保留原生触屏和键盘输入。
		button.name = "ResearchRulesChapter%d" % index
		button.text = CHAPTERS[index]
		button.position = Vector2(start + stride * index, 13)
		button.size = Vector2(width, 50)
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.toggle_mode = true
		button.button_group = group
		button.add_theme_font_override("font", Style.bold)
		button.add_theme_font_size_override("font_size", 26)
		button.add_theme_color_override("font_color", Style.CREAM)
		button.add_theme_color_override("font_focus_color", Style.CREAM)
		button.add_theme_color_override("font_hover_color", Style.GOLD)
		button.add_theme_color_override("font_pressed_color", Style.INK)
		button.add_theme_color_override("font_hover_pressed_color", Style.INK)
		button.add_theme_stylebox_override("normal", idle)
		button.add_theme_stylebox_override("hover", hover)
		button.add_theme_stylebox_override("pressed", selected)
		button.add_theme_stylebox_override("hover_pressed", selected)
		button.add_theme_stylebox_override("focus", focus)
		button.set_pressed_no_signal(index == 0)
		button.pressed.connect(_select_chapter.bind(index, true))
		header.add_child(button)

## 绘制 [param index] 对应的章节；[param animate] 为真时根据翻页方向短距离滑入。
func _select_chapter(index: int, animate: bool) -> void:
	if _chapter == index or (_motion != null and _motion.phase == Motion.Phase.CLOSING):
		return
	var offset: float = 18.0 if index > _chapter else -18.0 # 向下一章翻页从右侧入场。
	_chapter = index
	if _chapter_motion != null and _chapter_motion.is_valid():
		_chapter_motion.kill()
	for previous: Node in _body.get_children(): # 快速切换只保留本次需要显示的一页。
		_body.remove_child(previous)
		previous.queue_free()
	var page := Control.new() # 每一章使用同一裁剪区的尺寸。
	page.size = _body.size
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(page)
	Content.draw(page, mode, index)
	if animate:
		SoundManager.play_other_SFX(&"tap")
		page.position.x = offset
		page.modulate.a = 0.0
		_chapter_motion = create_tween().set_parallel(true).set_ignore_time_scale(true) \
			.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_chapter_motion.tween_property(page, "position:x", 0.0, 0.17)
		_chapter_motion.tween_property(page, "modulate:a", 1.0, 0.17)

## 动效结束后恢复下层交互，释放规则页持有的临时控件。
func _on_motion_closed() -> void:
	hide()
	closed.emit()
	queue_free()
