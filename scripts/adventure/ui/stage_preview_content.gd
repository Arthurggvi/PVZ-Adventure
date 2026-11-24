## 预览正文：先展示醒目的植物配方，再列出原有阶段、敌人与完整掉落。
## 所有分类、名称与来源由视图模型提供，此层只负责排版。
extends VBoxContainer

## 复用图标、头像、等阶徽章和文字的绘制原语。
const Art = preload("res://scripts/adventure/ui/stage_preview_art.gd")
## 配方框沿用地图底框，单独强调金色边缘。
const UI = preload("res://scripts/adventure/island_ui.gd")
## 为原生滚动条预留宽度后的正文设计宽度。
const WIDTH := 560.0
## 普通掉落仍沿用原尺寸。
const DROP_TILE := 56.0
## 普通掉落之间的设计像素间距。
const DROP_GAP := 8.0

## 纯展示内容不截获事件，输入统一到父滚动容器。
func _ready() -> void:
	custom_minimum_size.x = WIDTH
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 0)

## 按 [param data] 重建正文；移除旧内容再添加，避免关卡切换时叠行。
func rebuild(data: Dictionary) -> void:
	for child: Node in get_children(): # 原内容立即离树，释放可推迟到帧末。
		remove_child(child)
		child.queue_free()
	var recipes: Array = data.get("recipe_drops", []) # 跨阶段去重的配方及其全部掉落来源。
	if not recipes.is_empty():
		add_child(_recipe_feature(recipes))
		add_child(_spacer(18.0))
	for block: Dictionary in data.get("blocks", []): # 普通、噩梦、终末按原挑战顺序展示。
		_build_block(block)
	reset_size()

## 用 [param recipes] 构建首屏配方专区；数量可能来自不同来源，因此摘要不显示数量。
func _recipe_feature(recipes: Array) -> Control:
	var panel := PanelContainer.new() # 金边暖色底将配方与普通材料区分。
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = UI.panel_style(Color("392d19")) # 局部样式不改变地图主题。
	style.border_color = Color("e3bc62")
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 14.0
	panel.add_theme_stylebox_override("panel", style)
	var body := VBoxContainer.new() # 长名称与多来源自动增高，全部交给同一个滚动区。
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("separation", 10)
	panel.add_child(body)
	body.add_child(_label("本关可掉落植物配方", 28, Color("ffdd88")))
	for recipe: Dictionary in recipes: # 每个配方只画一次，同时列出其阶段或Boss来源。
		var row := HBoxContainer.new() # 放大图标旁直接显示完整名称。
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 14)
		body.add_child(row)
		row.add_child(Art.drop_tile(recipe, 84.0, false))
		var words := VBoxContainer.new() # 名称与掉落条件共享剩余宽度。
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(words)
		words.add_child(_label(str(recipe.get("title", "植物配方")), 26, Color("fff1bd")))
		words.add_child(_label(str(recipe.get("sources", "")), 18, Color("d8c7a2")))
	return panel

## 绘制 [param block] 的阶段与敌人；完整奖励继续按波次、通关和Boss来源分别列出。
func _build_block(block: Dictionary) -> void:
	add_child(_label("%s · %s" % [str(block.get("label", "")), str(block.get("wave_text", ""))], 28, Color("ffe8b0")))
	add_child(_caption("敌人"))
	var enemies: Array = block.get("enemies", []) # 普通敌人的出现波次与等阶。
	var bosses: Array = block.get("bosses", []) # Boss头像与登场时机。
	if enemies.is_empty() and bosses.is_empty():
		add_child(_label("本阶段没有配置敌人。", 20, Color("9fb3a6")))
	for enemy: Dictionary in enemies: # 每个物种一行，等阶不与出现波次挤在一起。
		add_child(_enemy_row(enemy, false))
	for boss: Dictionary in bosses: # Boss沿用专有头像，无普通等阶徽章。
		add_child(_enemy_row(boss, true))
	_add_drops("波次掉落", block.get("drops", []))
	_add_drops("通关掉落", block.get("clear_drops", []))
	for boss: Dictionary in bosses: # 保留每个Boss独立的击败奖励来源。
		_add_drops("击败%s掉落" % str(boss.get("title", "")), boss.get("drops", []))
	add_child(_spacer(20.0))

## 返回 [param entry] 的头像行；[param boss] 决定使用登场时机还是波次、等阶。
func _enemy_row(entry: Dictionary, boss: bool) -> Control:
	var row := Control.new() # 定高头像与三行信息，给最高五阶徽章保留整行宽度。
	row.custom_minimum_size = Vector2(0, 84 if boss else 100)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Art.portrait(row, Vector2(0, 4), entry)
	Art.text(row, str(entry.get("title", "")), Rect2(88, 2, WIDTH - 88, 34), 26,
		Color("ffd0c0") if boss else Color("f2f6ee"), HORIZONTAL_ALIGNMENT_LEFT, true)
	Art.text(row, str(entry.get("timing" if boss else "waves", "")), Rect2(88, 36, WIDTH - 88, 26), 18, Color("a9bcae"))
	if not boss:
		var chips := HBoxContainer.new() # 独立等阶行避免五个徽章覆盖波次说明。
		chips.position = Vector2(88, 66)
		chips.add_theme_constant_override("separation", 6)
		chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(chips)
		for badge: Dictionary in entry.get("tiers", []): # 按数据层给出的等阶顺序显示。
			chips.add_child(Art.chip(badge))
	return row

## 将 [param drops] 置于 [param title] 下；空来源不生成标题或空白网格。
func _add_drops(title: String, drops: Array) -> void:
	if drops.is_empty():
		return
	add_child(_caption(title))
	var grid := GridContainer.new() # 网格保留所有材料、配方和原数量角标。
	grid.columns = maxi(1, int(floor((WIDTH + DROP_GAP) / (DROP_TILE + DROP_GAP))))
	grid.add_theme_constant_override("h_separation", int(DROP_GAP))
	grid.add_theme_constant_override("v_separation", int(DROP_GAP))
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(grid)
	for drop: Dictionary in drops: # 普通材料仍使用原尺寸，配方在顶部另有放大摘要。
		grid.add_child(Art.drop_tile(drop))

## 用 [param value] 创建带上留白的小标题。
func _caption(value: String) -> Control:
	var row := Control.new() # 标题与前一组内容保留十像素间隔。
	row.custom_minimum_size.y = 36.0
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Art.text(row, value, Rect2(0, 10, WIDTH, 26), 21, Color("c6ae70"))
	return row

## 返回可自动换行的 [param value]；[param font_size] 和 [param color] 控制当前层级。
func _label(value: String, font_size: int, color: Color) -> Label:
	var node := Label.new() # 容器按真实文字高度排版，不截断配方名称或来源。
	node.text = value
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	node.add_theme_color_override("font_outline_color", Color("0d1712"))
	node.add_theme_constant_override("outline_size", 3)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

## 返回高 [param height] 设计像素的透明间隔。
func _spacer(height: float) -> Control:
	var row := Control.new() # 容器拥有间距，不使用绝对内容位移。
	row.custom_minimum_size.y = height
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return row
