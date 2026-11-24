## 图鉴右侧详情承载区；保留植物、僵尸原版说明，并装配独立 Boss 与 Buff 页面。
extends Control

## 复用图鉴木框与文字素材。
const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")
## 动态内容切换时立即移除旧预览。
const Style = preload("res://scripts/adventure/ui/almanac_style.gd")
## 说明区支持直接滑动和滚轮。
const ContentScroll = preload("res://scripts/ui/content_scroll.gd")
## 植物与僵尸的只读详情数据。
const Data = preload("res://scripts/adventure/ui/almanac_data.gd")
## 与战斗行为分离的待机预览。
const Preview = preload("res://scripts/adventure/ui/almanac_preview.gd")
## Boss 专用阶段与技能详情。
const BossDetail = preload("res://scripts/adventure/ui/boss_almanac_detail.gd")
## Buff 专用规则说明与可重播演示。
const BuffDetail = preload("res://scripts/adventure/ui/buff_almanac_detail.gd")

## 清除旧详情并给出准备反馈；旧角色在当帧即离开场景树。
func show_loading() -> void:
	Style.clear(self)
	Art.label(self, "正在加载…", Vector2(20, 40), Vector2(700, 60), 24)

## 显示已准备的 [param kind]、[param type_id]、[param tier]；[param loaded] 为 false 时给出重选提示，编号 0 清空内容。
func show_entry(kind: String, type_id: int, tier: int, loaded: bool = true) -> void:
	Style.clear(self)
	if type_id == 0:
		return
	if not loaded:
		Art.label(self, "暂时无法加载，请再次点击当前条目重试。", Vector2(20, 40), Vector2(850, 60), 24)
		return
	if kind == "boss":
		var boss_detail: BossDetail = BossDetail.new() # Boss 独占完整详情高度，不与阶级栏重叠。
		boss_detail.type_id = type_id
		add_child(boss_detail)
	elif kind == "buff":
		var buff_detail: BuffDetail = BuffDetail.new() # 状态资料不依赖发现记录或库存阶级。
		buff_detail.type_id = type_id
		add_child(buff_detail)
	else:
		_draw_character(kind, type_id, tier)

## 为 [param kind]、[param type_id]、[param tier] 保留原版角色形象、地面背景和能力区块。
func _draw_character(kind: String, type_id: int, tier: int) -> void:
	Art.label(self, Data.character_name(kind, type_id), Vector2(18, 3), Vector2(880, 60), 40)
	Art.panel(self, "panels/wood_ninepatch.png", Vector2(19, 72), Vector2(874, 4), 2)
	var holder: Control = Control.new() # 框内裁剪待机动画和地面背景。
	holder.position = Vector2(42, 115)
	holder.size = Vector2(304, 363)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.clip_contents = true
	add_child(holder)
	var background: TextureRect = TextureRect.new() # 沿用原图鉴的环境贴图。
	var grounds: Dictionary = AlmanacCharacterShowPanel.CHARACTER_BG_MAP # 保留昼夜、水陆对应关系。
	background.texture = grounds.get(Data.entry(kind, type_id).get("背景", "Day"), grounds["Day"])
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not Preview.draw_idle(holder, kind, type_id, tier, Rect2(35, 39, 234, 284)):
		Art.label(holder, "无", Vector2(140, 151), Vector2(45, 56), 24)
	Art.panel(self, "panels/outer_frame_ninepatch.png", Vector2(17, 90), Vector2(354, 413), 40)
	_render_sections(Data.detail(kind, type_id, tier))

## 将 [param info] 的能力、属性和效果拆成原有阅读区块；长说明独立滚动。
func _render_sections(info: Dictionary) -> void:
	var scroll := ContentScroll.new() # 阶级栏固定，只有说明内容滚动。
	scroll.position = Vector2(391, 90)
	scroll.size = Vector2(504, 413)
	add_child(scroll)
	var sections: VBoxContainer = VBoxContainer.new() # 按基础能力、数值、阶级效果和基础特性排列。
	sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sections.add_theme_constant_override("separation", 11)
	scroll.add_child(sections)
	var ability: VBoxContainer = _section(sections, "基础能力") # 基础说明允许自动换行。
	_text(ability, str(info.summary), 20, Color("382719"))
	var stat_section: VBoxContainer = _section(sections, "属性") # 属性名和值在独立数值格中对齐。
	var stats: HBoxContainer = HBoxContainer.new() # 植物与僵尸使用各自的数值字段。
	stats.add_theme_constant_override("separation", 8)
	stat_section.add_child(stats)
	for stat: String in info.stats: # 数值与标签上下排列，保留原单位。
		var cell: VBoxContainer = _section(stats, "") # 数值格平分当前可用宽度。
		var value: Label = _text(cell, str(info.stats[stat]), 23, Color("382719")) # 保留倍率或秒数。
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var caption: Label = _text(cell, stat, 17, Color("76583a")) # 属性名使用次级色。
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var effects: VBoxContainer = _section(sections, "阶级效果") # 当前阶优先，已有低阶转职随后列出。
	if info.effects.is_empty():
		_text(effects, "无", 20, Color("76583a"))
	for group: Dictionary in info.effects: # 僵尸的效果没有额外阶级标题。
		var effect_group: VBoxContainer = effects # 只有多个阶级时才增加分组卡。
		if info.effects.size() > 1:
			effect_group = _section(effects, str(group.title))
		if group.options.is_empty():
			_text(effect_group, "无", 20, Color("76583a"))
		for option: String in group.options: # 分支名与说明分行展示，长效果自动换行。
			if not option.is_empty():
				_text(effect_group, option, 20, Color("654023"))
			_text(effect_group, str(group.options[option]), 20, Color("382719"))
	if not info.traits.is_empty():
		var traits: VBoxContainer = _section(sections, "基础特性") # 原条目位于主要能力之后。
		for property_name: String in info.traits: # 每条基础特性单独占一行。
			_text(traits, "%s  %s" % [property_name, str(info.traits[property_name])], 19, Color("654b30"))

## 在 [param parent] 下创建带浅色底和内边距的区块；[param title] 为空时省略标题，返回内容列。
func _section(parent: Container, title: String) -> VBoxContainer:
	var panel: PanelContainer = PanelContainer.new() # 区块高度随内容增长。
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style: StyleBoxFlat = StyleBoxFlat.new() # 从羊皮纸底色中略微提亮阅读区。
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
	var column: VBoxContainer = VBoxContainer.new() # 标题和内容之间保留统一行距。
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)
	if not title.is_empty():
		_text(column, title, 22, Color("824820"))
	return column

## 在 [param parent] 中追加可换行的 [param caption]，使用 [param font_size] 和 [param ink]，返回文字节点。
func _text(parent: Container, caption: String, font_size: int, ink: Color) -> Label:
	var label: Label = Label.new() # 普通文字保留数据中的原始符号。
	label.text = caption
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", ink)
	label.add_theme_constant_override("line_spacing", 4)
	parent.add_child(label)
	return label
