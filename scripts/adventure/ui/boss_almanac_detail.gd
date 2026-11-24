## 图鉴的独立 Boss 详情页；阶段、属性、技能预览和人物介绍共用同一份只读资料。
extends Control

## 复用图鉴木框、按钮与文字素材。
const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")
## 长篇机制与效果说明共用原生滚动区。
const ContentScroll = preload("res://scripts/ui/content_scroll.gd")
## Boss 属性和分阶段技能目录。
const Data = preload("res://scripts/adventure/ui/boss_almanac_data.gd")
## Boss 页面共用的阅读字体、纸面卡片和强调色。
const PageStyle = preload("res://scripts/adventure/ui/boss_almanac_style.gd")
## 与战斗完全分离的动画舞台。
const Preview = preload("res://scripts/adventure/ui/boss_almanac_preview.gd")
## 创建详情前由图鉴指定的 Boss 编号。
var type_id: int = Data.GENERAL
## 当前阶段，不保存到玩家档案。
var _phase: int = 1
## 当前注册场景的只读属性快照。
var _info: Dictionary = {}
## 当前阶段的技能条目，按钮索引与此数组一致。
var _skills: Array[Dictionary] = []
## 当前选中技能的稳定 ID，切阶段时尽量保持选择。
var _selected_skill: String = ""
## 当前 Boss 的强调色，贯穿数值、阶段标签与选中技能。
var _accent: Color
## 与当前预览阶段同步的角色称谓。
var _title: Label
## 随阶段更新的行动间隔数值。
var _interval: Label
## 凯莱赫图鉴中随阶段更新的常驻减伤百分比。
var _cailleach_reduction: Label
## 当前阶段的特性标题。
var _trait_title: Label
## 当前阶段的特性说明。
var _trait: Label
## 当前演示的技能名称，与效果正文分开排版。
var _effect_title: Label
## 演示状态提示。
var _effect_hint: Label
## 技能下方的效果说明。
var _effect: Label
## 切换技能后回到说明开头。
var _effect_scroll: ScrollContainer
## 两个固定阶段按钮。
var _phase_buttons: Array[Button] = []
## 技能按钮的固定区域，按两行四列排列。
var _skill_grid: GridContainer
## 当前技能按钮，用于更新选中状态。
var _skill_buttons: Array[Button] = []
## 动画预览节点，切阶段时只重建其视觉内容。
var _preview: Preview

## 创建分层档案：左侧舞台，右侧数值和阶段机制，下方为技能与独立效果卡。
func _ready() -> void:
	size = Vector2(910, 640)
	_info = Data.profile(type_id)
	_title = PageStyle.label(self, str(_info.get("title", Data.title_for(type_id))), Rect2(18, 0, 390, 53), 40, PageStyle.INK, false)
	if not Data.has_battle_details(type_id, _info):
		PageStyle.label(self, Data.DETAILS_UNAVAILABLE, Rect2(21, 67, 680, 40), 22, PageStyle.MUTED)
		return
	var role: String # 图鉴名称下的身份，配色与技能选择一致。
	_accent = PageStyle.DUKE_ACCENT
	match type_id:
		Data.GENERAL:
			role = "军旗统领 · 冲锋压阵"
			_accent = PageStyle.GENERAL_ACCENT
		Data.LANTERN:
			role = "古海守护神"
		Data.SAVIOR:
			role = "教堂 · 亡影复生"
			_accent = PageStyle.SAVIOR_ACCENT
		Data.CAILLEACH:
			role = "边境雪山 · 噩梦"
		_:
			role = "亡灵乐师 · 墓碑复生"
	if not role.is_empty():
		PageStyle.label(self, role, Rect2(21, 51, 390, 24), 17, PageStyle.MUTED)
	for phase: int in range(1, 3): # 阶段是顶层筛选，与下方技能入口区别排版。
		var button: Button = _button("一阶段" if phase == 1 else "二阶段", _choose_phase.bind(phase)) # 固定入口保留焦点。
		button.position = Vector2(595 + (phase - 1) * 150, 12)
		button.size = Vector2(140, 42)
		add_child(button)
		_phase_buttons.append(button)
	_preview = Preview.new()
	_preview.position = Vector2(20, 89)
	add_child(_preview)
	Art.panel(self, "panels/outer_frame_ninepatch.png", Vector2(10, 79), Vector2(410, 320), 24)
	PageStyle.card(self, Rect2(438, 80, 446, 107))
	PageStyle.label(self, "最大生命", Rect2(454, 90, 180, 24), 17, PageStyle.MUTED)
	PageStyle.number(self, String.num_int64(int(_info.health)), Rect2(451, 114, 230, 49), 40, _accent)
	PageStyle.label(self, "阶段转换", Rect2(697, 101, 166, 24), 16, PageStyle.MUTED)
	PageStyle.label(self, "生命 %s %s%%" % ["≤" if _info.inclusive else "<", String.num(float(_info.threshold) * 100.0, 1).trim_suffix(".0")], Rect2(697, 130, 175, 28), 21, _accent)
	PageStyle.card(self, Rect2(438, 197, 218, 76))
	PageStyle.label(self, "随机行动间隔" if type_id == Data.CAILLEACH else "行动间隔", Rect2(454, 206, 180, 22), 16, PageStyle.MUTED)
	_interval = PageStyle.number(self, "", Rect2(454, 231, 100, 34), 27)
	PageStyle.label(self, "秒", Rect2(558, 242, 80, 22), 17, PageStyle.MUTED)
	PageStyle.card(self, Rect2(666, 197, 218, 76))
	if type_id == Data.LANTERN:
		PageStyle.label(self, "对僵尸伤害", Rect2(682, 206, 186, 22), 16, PageStyle.MUTED)
		PageStyle.number(self, "50%", Rect2(682, 231, 115, 34), 27)
	elif type_id == Data.SAVIOR:
		PageStyle.label(self, "本体站位", Rect2(682, 206, 186, 22), 16, PageStyle.MUTED)
		PageStyle.label(self, "第 3 行", Rect2(682, 231, 186, 34), 25)
	elif type_id == Data.CAILLEACH:
		PageStyle.label(self, "常驻减伤", Rect2(682, 206, 90, 22), 16, PageStyle.MUTED)
		_cailleach_reduction = PageStyle.number(self, "", Rect2(682, 231, 90, 34), 27)
		PageStyle.label(self, "灰烬额外减伤", Rect2(776, 206, 106, 22), 16, PageStyle.MUTED)
		PageStyle.number(self, "50%", Rect2(776, 231, 96, 34), 27)
	else:
		PageStyle.label(self, "换行速度", Rect2(682, 206, 186, 22), 16, PageStyle.MUTED)
		PageStyle.number(self, String.num(float(_info.config.lane_change_speed), 1).trim_suffix(".0"), Rect2(682, 231, 100, 34), 27)
		PageStyle.label(self, "像素/秒", Rect2(786, 242, 85, 22), 17, PageStyle.MUTED)
	PageStyle.card(self, Rect2(438, 283, 446, 116), Color(1, 0.96, 0.85, 0.35))
	_trait_title = PageStyle.label(self, "", Rect2(454, 292, 410, 30), 22, _accent, false)
	var trait_scroll: ScrollContainer = _scroll(Vector2(454, 326), Vector2(414, 65)) # 墓碑被动等长机制独立滚动。
	_trait = _text(trait_scroll, "", 19)
	var is_cailleach: bool = type_id == Data.CAILLEACH # 妇人的阶段条目可查阅，其中杖击保留原画预览。
	PageStyle.label(self, "技能与机制" if is_cailleach else "技能演示", Rect2(18, 410, 220, 28), 24, PageStyle.INK, false)
	if not is_cailleach:
		PageStyle.label(self, "点击播放 · 再次点击重播", Rect2(623, 414, 264, 23), 16, PageStyle.MUTED)
	_skill_grid = GridContainer.new()
	_skill_grid.position = Vector2(18, 446)
	_skill_grid.columns = 4
	_skill_grid.add_theme_constant_override("h_separation", 10)
	_skill_grid.add_theme_constant_override("v_separation", 7)
	add_child(_skill_grid)
	PageStyle.card(self, Rect2(18, 543, 874, 95))
	_effect_title = PageStyle.label(self, "", Rect2(33, 551, 420, 29), 23, _accent, false)
	_effect_hint = PageStyle.label(self, "", Rect2(635, 556, 242, 22), 15, PageStyle.MUTED)
	_effect_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_effect_scroll = _scroll(Vector2(34, 584), Vector2(840, 47))
	_effect = _text(_effect_scroll, "", 20)
	_rebuild_phase()

## 在 [param position_value]、[param dimensions] 创建只允许竖向滚动的阅读区。
func _scroll(position_value: Vector2, dimensions: Vector2) -> ScrollContainer:
	var scroll := ContentScroll.new() # 宽度固定，长文本自动换行。
	scroll.position = position_value
	scroll.size = dimensions
	add_child(scroll)
	return scroll

## 在 [param parent] 中显示可换行的 [param caption]，字号为 [param font_size]。
func _text(parent: Container, caption: String, font_size: int) -> Label:
	var label: Label = PageStyle.label(parent, caption, Rect2(), font_size) # 内容高度由文字决定，滚动容器负责裁剪。
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

## 创建显示 [param caption] 的选择按钮，并连接 [param action]；添加父节点后由调用者定位。
func _button(caption: String, action: Callable) -> Button:
	var button := Button.new() # 每次点击都发出 pressed，已选技能也能重播。
	button.text = caption
	button.toggle_mode = true
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_color_override("font_color", PageStyle.INK)
	button.add_theme_color_override("font_pressed_color", Color("fff3d8"))
	button.add_theme_color_override("font_hover_color", _accent)
	button.add_theme_color_override("font_hover_pressed_color", Color("fff3d8"))
	button.add_theme_stylebox_override("normal", PageStyle.card_style(Color(1, 0.96, 0.84, 0.55), Color("a88b5b")))
	button.add_theme_stylebox_override("hover", PageStyle.card_style(Color("fff0c9"), _accent))
	button.add_theme_stylebox_override("pressed", PageStyle.card_style(_accent, _accent))
	button.add_theme_stylebox_override("hover_pressed", PageStyle.card_style(_accent.lightened(0.08), _accent))
	var focus: StyleBoxFlat = PageStyle.card_style(Color.TRANSPARENT, Color("a87920")) # 键盘焦点独立于选中状态。
	focus.draw_center = false
	focus.set_border_width_all(2)
	button.add_theme_stylebox_override("focus", focus)
	button.pressed.connect(action)
	return button

## 切换到 [param phase]，同步更新角色外观、属性和技能；重复点击当前阶段不重建资源。
func _choose_phase(phase: int) -> void:
	if phase == _phase:
		_phase_buttons[phase - 1].set_pressed_no_signal(true)
		return
	_phase = phase
	_rebuild_phase()
	SoundManager.play_other_SFX(&"tap")

## 重建分阶段数值与机制，保留有效的技能选择；人物轶事由外层目录展示。
func _rebuild_phase() -> void:
	var title_key: String = "phase_two_title" if _phase == 2 else "title" # 使用战斗场景配置的阶段称谓。
	_title.text = str(_info[title_key])
	for index: int in range(_phase_buttons.size()): # 用角色强调色标记正在查看的阶段。
		_phase_buttons[index].set_pressed_no_signal(index + 1 == _phase)
	_interval.text = String.num(Data.action_interval(type_id, _info, _phase), 1).trim_suffix(".0")
	if type_id == Data.LANTERN:
		_trait_title.text = "一阶段 · 黑暗形态" if _phase == 1 else "二阶段 · 星空形态"
	elif type_id == Data.SAVIOR:
		_trait_title.text = "一阶段 · 在场效果" if _phase == 1 else "二阶段 · 同步祷告"
	elif type_id == Data.CAILLEACH:
		_cailleach_reduction.text = "%d%%" % roundi(100.0 * ZB006Cailleach.damage_reduction_for_phase(_phase))
		_trait_title.text = "冰封"
	else:
		_trait_title.text = ("一阶段 · 军旗压阵" if _phase == 1 else "二阶段 · 黑焰冲锋") if type_id == Data.GENERAL else ("一阶段 · 墓碑复生" if _phase == 1 else "二阶段 · 亡灵狂欢")
	_trait.text = Data.passive(type_id, _info, _phase)
	_preview.show_boss(type_id, _phase, _info)
	for child: Node in _skill_grid.get_children(): # 销毁旧阶段按钮，避免说明和动作错配。
		_skill_grid.remove_child(child)
		child.queue_free()
	_skill_buttons.clear()
	_skills = Data.skills(type_id, _phase, _info)
	var selected_index: int = -1 # 只保留当前阶段仍存在的技能选择。
	for index: int in range(_skills.size()): # 每阶段显示至多两行条目。
		var skill: Dictionary = _skills[index] # 本次按钮捕获稳定索引。
		var button: Button = _button(str(skill.title), _choose_skill.bind(index)) # 选中项可再次点击重播。
		button.custom_minimum_size = Vector2(211, 41)
		button.tooltip_text = ("查看%s说明" if skill.clips.is_empty() else "播放%s动画") % skill.title
		_skill_grid.add_child(button)
		_skill_buttons.append(button)
		if str(skill.id) == _selected_skill:
			selected_index = index
	if type_id != Data.CAILLEACH:
		var idle: Button = _button("回到待机", _show_idle) # 为其他 Boss 保留独立的待机控制。
		idle.toggle_mode = false
		idle.custom_minimum_size = Vector2(211, 41)
		_skill_grid.add_child(idle)
	if selected_index >= 0:
		_choose_skill(selected_index, false)
	elif type_id == Data.CAILLEACH:
		_choose_skill(0, false)
	else:
		_selected_skill = ""
		_set_idle_description()
		_effect_scroll.scroll_vertical = 0

## 显示 [param index] 对应技能，有可预览的动作时同时播放；[param play_sound] 控制点击声。
func _choose_skill(index: int, play_sound: bool = true) -> void:
	var skill: Dictionary = _skills[index] # 本阶段的动作和效果来自同一条目。
	_selected_skill = str(skill.id)
	for button_index: int in range(_skill_buttons.size()): # 更新选中态，重复点击也保持选中。
		_skill_buttons[button_index].set_pressed_no_signal(button_index == index)
	_effect_title.text = str(skill.title)
	_effect.text = str(skill.description)
	_effect_scroll.scroll_vertical = 0
	if skill.clips.is_empty():
		_effect_hint.text = ""
		_preview.stop()
	else:
		_effect_hint.text = "动作结束后可重播" if type_id == Data.CAILLEACH else "%s · 再次点击可重播" % ("二阶段" if _phase == 2 else "一阶段")
		_preview.play_skill(skill.clips, skill.id)
	if play_sound:
		SoundManager.play_other_SFX(&"tap")

## 清空当前技能选择，恢复当前阶段的待机展示。
func _show_idle() -> void:
	_selected_skill = ""
	for button: Button in _skill_buttons: # 待机不保留其他技能的选中边框。
		button.set_pressed_no_signal(false)
	_preview.play_skill([])
	_set_idle_description()
	_effect_scroll.scroll_vertical = 0

## 待机状态使用独立标题与轻提示，避免重复显示角色名称和阶段。
func _set_idle_description() -> void:
	_effect_title.text = "待机展示"
	_effect_hint.text = "二阶段" if _phase == 2 else "一阶段"
	_effect.text = "选择上方技能，查看动作演示与对应效果。"
