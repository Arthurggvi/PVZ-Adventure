## 图鉴的独立 Boss 详情页；阶段、属性、技能预览和人物介绍共用同一份只读资料。
extends Control

## 复用图鉴木框、按钮与文字素材。
const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")
## Boss 属性和分阶段技能目录。
const Data = preload("res://scripts/adventure/ui/boss_almanac_data.gd")
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
## 属性和常驻特性文字。
var _stats: Label
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

## 创建固定排版，长文字使用各自的滚动区，不挤占技能入口。
func _ready() -> void:
	size = Vector2(910, 640)
	_info = Data.profile(type_id)
	Art.label(self, str(_info.title), Vector2(18, 3), Vector2(430, 60), 40)
	for phase: int in range(1, 3): # 独立阶段按钮不与普通僵尸五阶混用。
		var button: Button = _button("一阶段" if phase == 1 else "二阶段", _choose_phase.bind(phase)) # 固定按钮保留键盘焦点。
		button.position = Vector2(580 + (phase - 1) * 155, 12)
		button.size = Vector2(145, 44)
		add_child(button)
		_phase_buttons.append(button)
	Art.panel(self, "panels/wood_ninepatch.png", Vector2(19, 66), Vector2(874, 4), 2)
	_preview = Preview.new()
	_preview.position = Vector2(20, 83)
	add_child(_preview)
	Art.panel(self, "panels/outer_frame_ninepatch.png", Vector2(10, 73), Vector2(410, 320), 24)
	Art.label(self, "属性与特性", Vector2(438, 78), Vector2(445, 34), 24, Color("824820"))
	var stats_scroll: ScrollContainer = _scroll(Vector2(438, 119), Vector2(445, 263)) # 属性说明可以滚动，不覆盖预览。
	_stats = _text(stats_scroll, "", 21)
	_skill_grid = GridContainer.new()
	_skill_grid.position = Vector2(18, 404)
	_skill_grid.columns = 4
	_skill_grid.add_theme_constant_override("h_separation", 10)
	_skill_grid.add_theme_constant_override("v_separation", 7)
	add_child(_skill_grid)
	Art.panel(self, "panels/wood_ninepatch.png", Vector2(18, 504), Vector2(874, 3), 1)
	_effect_scroll = _scroll(Vector2(20, 515), Vector2(870, 107))
	_effect = _text(_effect_scroll, "点击上方技能，观看动画并查看对应作用。", 21)
	_rebuild_phase()

## 在 [param position_value]、[param dimensions] 创建只允许竖向滚动的阅读区。
func _scroll(position_value: Vector2, dimensions: Vector2) -> ScrollContainer:
	var scroll := ScrollContainer.new() # 宽度固定，长文本自动换行。
	scroll.position = position_value
	scroll.size = dimensions
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	return scroll

## 在 [param parent] 中显示可换行的 [param caption]，字号为 [param font_size]。
func _text(parent: Container, caption: String, font_size: int) -> Label:
	var label := Label.new() # 内容高度由实际文字决定，滚动容器负责裁剪。
	label.text = caption
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("382719"))
	label.add_theme_constant_override("line_spacing", 5)
	parent.add_child(label)
	return label

## 创建显示 [param caption] 的选择按钮，并连接 [param action]；添加父节点后由调用者定位。
func _button(caption: String, action: Callable) -> Button:
	var button := Button.new() # 每次点击都发出 pressed，已选技能也能重播。
	button.text = caption
	button.toggle_mode = true
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_color_override("font_color", Color("fff0ce"))
	button.add_theme_color_override("font_pressed_color", Color("fff6de"))
	button.add_theme_color_override("font_hover_color", Color("fff6de"))
	button.add_theme_color_override("font_outline_color", Color("3e2518"))
	button.add_theme_constant_override("outline_size", 2)
	button.add_theme_stylebox_override("normal", Art.texture_style("buttons/button_normal.png", 10))
	button.add_theme_stylebox_override("hover", Art.texture_style("buttons/button_hover.png", 10))
	button.add_theme_stylebox_override("pressed", Art.texture_style("buttons/button_selected.png", 10))
	button.add_theme_stylebox_override("hover_pressed", Art.texture_style("buttons/button_selected.png", 10))
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

## 重建分阶段资料；人物描述完整放在右侧滚动区，技能作用始终位于按钮下方。
func _rebuild_phase() -> void:
	for index: int in range(_phase_buttons.size()): # 用亮边标记正在查看的阶段。
		_phase_buttons[index].set_pressed_no_signal(index + 1 == _phase)
	_stats.text = Data.stats(_info, _phase) + "\n\n" + Data.passive(type_id, _info) + "\n\n人物介绍\n" + str(_info.story)
	_preview.show_boss(type_id, _phase, _info)
	for child: Node in _skill_grid.get_children(): # 销毁旧阶段按钮，避免说明和动作错配。
		_skill_grid.remove_child(child)
		child.queue_free()
	_skill_buttons.clear()
	_skills = Data.skills(type_id, _phase, _info)
	var selected_index: int = -1 # 只保留当前阶段仍存在的技能选择。
	for index: int in range(_skills.size()): # 至多七种技能，末格保留给待机按钮。
		var skill: Dictionary = _skills[index] # 本次按钮捕获稳定索引。
		var button: Button = _button(str(skill.title), _choose_skill.bind(index)) # 选中项可再次点击重播。
		button.custom_minimum_size = Vector2(211, 42)
		button.tooltip_text = "播放%s动画" % skill.title
		_skill_grid.add_child(button)
		_skill_buttons.append(button)
		if str(skill.id) == _selected_skill:
			selected_index = index
	var idle: Button = _button("待机", _show_idle) # 用户可主动停止技能演示。
	idle.toggle_mode = false
	idle.custom_minimum_size = Vector2(211, 42)
	_skill_grid.add_child(idle)
	if selected_index >= 0:
		_choose_skill(selected_index, false)
	else:
		_selected_skill = ""
		_effect.text = "点击上方技能，观看动画并查看对应作用。\n当前：%s · %s" % [_info.title, "二阶段" if _phase == 2 else "一阶段"]
		_effect_scroll.scroll_vertical = 0

## 播放 [param index] 对应技能；[param play_sound] 控制切阶段自动刷新时是否重复点击声。
func _choose_skill(index: int, play_sound: bool = true) -> void:
	var skill: Dictionary = _skills[index] # 本阶段的动作和效果来自同一条目。
	_selected_skill = str(skill.id)
	for button_index: int in range(_skill_buttons.size()): # 更新选中态，重复点击也保持选中。
		_skill_buttons[button_index].set_pressed_no_signal(button_index == index)
	_effect.text = "%s · %s\n%s" % [skill.title, "二阶段" if _phase == 2 else "一阶段", skill.description]
	_effect_scroll.scroll_vertical = 0
	_preview.play_skill(skill.clips, skill.id)
	if play_sound:
		SoundManager.play_other_SFX(&"tap")

## 清空当前技能选择，恢复当前阶段的待机展示。
func _show_idle() -> void:
	_selected_skill = ""
	for button: Button in _skill_buttons: # 待机不保留其他技能的选中边框。
		button.set_pressed_no_signal(false)
	_preview.play_skill([])
	_effect.text = "正在展示%s的%s待机。点击技能可重新播放演示。" % [_info.title, "二阶段" if _phase == 2 else "一阶段"]
	_effect_scroll.scroll_vertical = 0
