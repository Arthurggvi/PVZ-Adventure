## 僵尸岛地图的关卡悬停预览：三态面板、自动滚动与既有美术拼装。
## 只消费 StagePreviewData 的展示字典；不查询进度，也不重新解释关卡规则。
extends Control

## 地图与按钮共用的界面构造工具。
const UI = preload("res://scripts/adventure/island_ui.gd")
## 复用背包的槽位与图标绘制原语。
const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")
## 配方掉落需要与背包一致的植物头像和蜡封。
const ItemArt = preload("res://scripts/adventure/ui/inventory_item_art.gd")

## 与地图按钮共用 1920×1080 设计坐标。
const DESIGN_SIZE := Vector2(1920, 1080)
## 固定面板尺寸，内容超出时由内部视口滚动。
const PANEL_SIZE := Vector2(640, 700)
## 面板内边距与标题区高度。
const PADDING := 24.0
const HEADER_HEIGHT := 118.0
## 面板与节点之间的间距。
const GAP := 24.0
## 纵向夹紧范围：避开顶部返回按钮和底部提示条。
const SAFE_TOP := 110.0
const SAFE_BOTTOM := 972.0
## 自动滚动速度、两端停顿时长与悬停确认延迟。
const SCROLL_SPEED := 72.0
const EDGE_PAUSE := 1.2
const SHOW_DELAY := 0.15
## 敌人头像沿用图鉴窗口与静态缩略图，掉落图标沿用背包格。
const ENEMY_TILE := 76.0
const DROP_TILE := 56.0
const DROP_GAP := 8.0
const ENEMY_ROW := 84.0
const BLOCK_GAP := 20.0
const ALMANAC_WINDOW := "res://assets/image/Almanac/Almanac_ZombieWindow.png"
## 黑将军还没有卡牌静态模板，直接复用他的纯视觉场景做悬停头像。
const BLACK_GENERAL_VISUAL := "res://scenes/character/zombie_boss/black_general_visual.tscn"
## 面板底色与滚动边界渐隐高度。
const PANEL_COLOR := Color("12211cee")
const EDGE_FADE := 24.0

## 标题与状态行，只在展示新关卡时改写文字。
var _title_label: Label
var _state_label: Label
## 裁剪滚动的内容视口，内容高度超过视口时才启动自动滚动。
var _viewport: Control
var _content: VBoxContainer
## 延迟确认，快速划过多个节点时不会连续弹面板。
var _delay: Timer
var _pending_data: Dictionary = {}
var _pending_anchor := Rect2()
## 当前滚动位置、方向与两端停顿剩余时长。
var _scroll := 0.0
var _direction := 1.0
var _pause := 0.0
## 淡入补间，切换关卡时先终止上一段。
var _tween: Tween

## 建立固定骨架；内容在每次展示时按数据重建。
func _ready() -> void:
	size = PANEL_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build_chrome()
	_delay = Timer.new()
	_delay.one_shot = true
	_delay.wait_time = SHOW_DELAY
	_delay.timeout.connect(_apply_pending)
	add_child(_delay)

## 记录 [param data] 与锚点并延迟展示；重复请求以最后一次为准。
func request(data: Dictionary, anchor: Rect2) -> void:
	_pending_data = data
	_pending_anchor = anchor
	_delay.start()

## 鼠标离开节点时立即收起，避免面板继续覆盖相邻节点。
func cancel() -> void:
	_pending_data = {}
	_delay.stop()
	visible = false

## 悬停确认后组装内容并按锚点定位。
func _apply_pending() -> void:
	if _pending_data.is_empty():
		return
	var data := _pending_data
	_pending_data = {}
	_title_label.text = str(data.get("title", ""))
	_state_label.text = _state_text(data)
	_rebuild(data)
	_place(_pending_anchor)
	visible = true
	modulate.a = 0.0
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, 0.12)
	_scroll = 0.0
	_direction = 1.0
	_pause = EDGE_PAUSE # 先在顶部停留，让标题与首个阶段有时间被读到。
	_content.position = Vector2.ZERO

## 内容超高时往返滚动；两端各停顿 [constant EDGE_PAUSE] 秒。
func _process(delta: float) -> void:
	if not visible:
		return
	var span: float = _content.size.y - _viewport.size.y
	if span <= 0.0:
		return
	if _pause > 0.0:
		_pause -= delta
		return
	_scroll += SCROLL_SPEED * delta * _direction
	if _scroll >= span:
		_scroll = span
		_direction = -1.0
		_pause = EDGE_PAUSE
	elif _scroll <= 0.0:
		_scroll = 0.0
		_direction = 1.0
		_pause = EDGE_PAUSE
	_content.position.y = -_scroll

## 面板底色、标题、状态行与裁剪视口。
func _build_chrome() -> void:
	var background := Panel.new()
	background.size = PANEL_SIZE
	background.add_theme_stylebox_override("panel", UI.panel_style(PANEL_COLOR))
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	_title_label = _text(self, "", Rect2(Vector2(PADDING, 16), Vector2(PANEL_SIZE.x - PADDING * 2.0, 50)),
		40, Color("ffe8b0"))
	_state_label = _text(self, "", Rect2(Vector2(PADDING, 68), Vector2(PANEL_SIZE.x - PADDING * 2.0, 30)),
		22, Color("b9c9bf"))
	var divider := ColorRect.new()
	divider.color = Color(0.78, 0.68, 0.44, 0.45)
	divider.position = Vector2(PADDING, HEADER_HEIGHT - 12.0)
	divider.size = Vector2(PANEL_SIZE.x - PADDING * 2.0, 1.0)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(divider)
	_viewport = Control.new()
	_viewport.position = Vector2(PADDING, HEADER_HEIGHT)
	_viewport.size = Vector2(PANEL_SIZE.x - PADDING * 2.0, PANEL_SIZE.y - HEADER_HEIGHT - PADDING)
	_viewport.clip_contents = true
	_viewport.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_viewport)
	_content = VBoxContainer.new()
	_content.custom_minimum_size = Vector2(_viewport.size.x, 0.0)
	_content.add_theme_constant_override("separation", 0)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport.add_child(_content)
	_edge_fade(true)
	_edge_fade(false)

## 在视口上下各铺一条同色渐隐，避免滚动边界把整行文字切在半截。
## [param top] 为真时从标题分隔线向下淡出，否则从面板底边向上淡出。
func _edge_fade(top: bool) -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, PANEL_COLOR)
	gradient.set_color(1, Color(PANEL_COLOR, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 1
	texture.height = 32
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(0, 1)
	var node := TextureRect.new()
	node.texture = texture
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_SCALE
	node.flip_v = not top
	node.position = Vector2(PADDING, HEADER_HEIGHT if top else PANEL_SIZE.y - PADDING - EDGE_FADE)
	node.size = Vector2(PANEL_SIZE.x - PADDING * 2.0, EDGE_FADE)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(node)

## 状态行只描述进度，具体提示放在占位内容里。
func _state_text(data: Dictionary) -> String:
	if str(data.get("state", "")) == "sealed":
		return "情报未解锁"
	return "普通阶段已通关"

## 按展示字典重建内容；旧行立即离树，避免重建时出现双份内容。
func _rebuild(data: Dictionary) -> void:
	for child: Node in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	if str(data.get("state", "")) == "ready":
		for block: Dictionary in data.get("blocks", []):
			_build_block(block)
	else:
		_build_placeholder(str(data.get("hint", "")))
	_content.reset_size()

## 未通关时只显示问号与条件说明，整块在视口内垂直居中。
func _build_placeholder(hint: String) -> void:
	var frame := Control.new()
	frame.custom_minimum_size = Vector2(0.0, _viewport.size.y)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(frame)
	_text(frame, "？", Rect2(Vector2.ZERO, Vector2(_content.size.x, 250.0)), 180, Color("ffe8b0"),
		HORIZONTAL_ALIGNMENT_CENTER)
	_text(frame, hint, Rect2(Vector2(20, 300), Vector2(_content.size.x - 40.0, 110.0)), 26,
		Color("b9c9bf"), HORIZONTAL_ALIGNMENT_CENTER)

## 绘制 [param block] 的波次摘要、敌人与奖励，击败奖励按 Boss 分开显示。
func _build_block(block: Dictionary) -> void:
	_content.add_child(_block_header(block))
	var enemies: Array = block.get("enemies", [])
	var bosses: Array = block.get("bosses", [])
	if enemies.is_empty() and bosses.is_empty():
		_content.add_child(_caption("敌人"))
		_content.add_child(_line("本阶段没有配置敌人。", 20, Color("9fb3a6")))
	else:
		_content.add_child(_caption("敌人"))
		for enemy: Dictionary in enemies:
			_content.add_child(_enemy_row(enemy))
		for boss: Dictionary in bosses:
			_content.add_child(_boss_row(boss))
	var drops: Array = block.get("drops", [])
	_content.add_child(_caption("波次掉落"))
	if drops.is_empty():
		_content.add_child(_line("本阶段没有配置掉落。", 20, Color("9fb3a6")))
	else:
		_content.add_child(_drop_grid(drops))
	for boss: Dictionary in bosses: # 标明每组击败奖励对应的 Boss。
		var boss_drops: Array = boss.get("drops", []) # 击败该 Boss 后追加的掉落条目。
		if not boss_drops.is_empty():
			_content.add_child(_caption("击败%s掉落" % str(boss.get("title", ""))))
			_content.add_child(_drop_grid(boss_drops))
	_content.add_child(_spacer(BLOCK_GAP))

## 阶段标题行：普通/噩梦与波次摘要。
func _block_header(block: Dictionary) -> Control:
	var row := Control.new()
	row.custom_minimum_size = Vector2(0.0, 46.0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text(row, "%s · %s" % [str(block.get("label", "")), str(block.get("wave_text", ""))],
		Rect2(Vector2(0, 4), Vector2(_content.size.x, 38.0)), 28, Color("ffe8b0"))
	return row

## 普通敌人行：图鉴头像、名称、出现波次与等阶徽章。
func _enemy_row(enemy: Dictionary) -> Control:
	var row := Control.new()
	row.custom_minimum_size = Vector2(0.0, ENEMY_ROW)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait(row, Vector2(0, 2), enemy)
	_text(row, str(enemy.get("title", "")), Rect2(Vector2(88, 6), Vector2(238, 34)), 26,
		Color("f2f6ee"), HORIZONTAL_ALIGNMENT_LEFT, true)
	_text(row, str(enemy.get("waves", "")), Rect2(Vector2(88, 42), Vector2(238, 24)), 18,
		Color("a9bcae"))
	var chips := HBoxContainer.new()
	chips.position = Vector2(336, 48)
	chips.size = Vector2(_content.size.x - 336.0, 30.0)
	chips.alignment = BoxContainer.ALIGNMENT_END
	chips.add_theme_constant_override("separation", 6)
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(chips)
	for badge: Dictionary in enemy.get("tiers", []):
		chips.add_child(_chip(badge))
	return row

## Boss 行：头像、名称与登场时机，不显示普通波次。
func _boss_row(boss: Dictionary) -> Control:
	var row := Control.new()
	row.custom_minimum_size = Vector2(0.0, ENEMY_ROW)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait(row, Vector2(0, 2), boss)
	_text(row, str(boss.get("title", "")), Rect2(Vector2(88, 16), Vector2(320, 34)), 26,
		Color("ffd0c0"), HORIZONTAL_ALIGNMENT_LEFT, true)
	_text(row, str(boss.get("timing", "")), Rect2(Vector2(88, 50), Vector2(320, 24)), 18,
		Color("a9bcae"))
	return row

## 掉落网格：按内容宽度自动分列，每格只有图标，数量用角标表示。
func _drop_grid(drops: Array) -> Control:
	var grid := GridContainer.new()
	grid.columns = maxi(1, int(floor((_content.size.x + DROP_GAP) / (DROP_TILE + DROP_GAP))))
	grid.add_theme_constant_override("h_separation", int(DROP_GAP))
	grid.add_theme_constant_override("v_separation", int(DROP_GAP))
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for drop: Dictionary in drops:
		grid.add_child(_drop_tile(drop))
	return grid

## 绘制 [param drop] 的图标与数量角标，硬上限优先于基础数量。
func _drop_tile(drop: Dictionary) -> Control:
	var cell := Control.new()
	cell.custom_minimum_size = Vector2(DROP_TILE, DROP_TILE)
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Art.image(cell, "slots/item_slot_normal.png", Vector2.ZERO, cell.custom_minimum_size)
	var backing := str(drop.get("backing", ""))
	if not backing.is_empty():
		Art.image(cell, backing, Vector2(4, 4), Vector2(DROP_TILE - 8.0, DROP_TILE - 8.0))
	var icon := str(drop.get("icon", ""))
	if not icon.is_empty():
		Art.image(cell, icon, Vector2(8, 8), Vector2(DROP_TILE - 16.0, DROP_TILE - 16.0))
	var icon_scale: float = (DROP_TILE - 16.0) / 58.0 # 与背包格相同的缩放基准。
	var plant_type := int(drop.get("plant_type", 0))
	if plant_type > 0:
		ItemArt.add_recipe_portrait(cell, plant_type, cell.custom_minimum_size * 0.5, 0.42 * icon_scale)
	var wax := ItemArt.recipe_overlay_uri(str(drop.get("id", "")))
	if not wax.is_empty():
		Art.image(cell, wax, Vector2(8, 8) + Vector2(35, 39) * icon_scale, Vector2(20, 20) * icon_scale)
	var count := int(drop.get("count", 1)) # 固定数量或随机区间的下限。
	var cap := int(drop.get("cap", 0)) # 0 表示条目没有装备加成后的硬上限。
	if cap > 0:
		Art.count_badge(cell, "≤%d" % cap, cell.custom_minimum_size, Color("fff4d6"), 14)
	elif count >= 2:
		Art.count_badge(cell, "×%d" % count, cell.custom_minimum_size, Color("fff4d6"), 14)
	return cell

## 图鉴窗口 + 静态缩略图；未注册美术时保留空窗口，不中断整块内容。
func _portrait(parent: Control, pos: Vector2, entry: Dictionary) -> void:
	var holder := Control.new()
	holder.position = pos
	holder.size = Vector2(ENEMY_TILE, ENEMY_TILE)
	holder.clip_contents = true
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(holder)
	Art.image(holder, ALMANAC_WINDOW, Vector2.ZERO, holder.size)
	var boss: bool = int(entry.get("card_type", 0)) == ResourceCardReference.CardType.ZombieBoss
	var role: int = int(entry.get("type", 0))
	if role <= 0:
		return
	if boss and role == CharacterRegistry.ZombieBossType.ZB002BlackGeneral:
		_black_general_portrait(holder)
		return
	var reference := ResourceCardReference.create(
		ResourceCardReference.CardType.ZombieBoss if boss else ResourceCardReference.CardType.Zombie, role)
	if AllCards.get_template(reference) == null: # 未注册卡牌模板的物种不打印错误，只留空窗口。
		return
	var preview: Node2D = AllCards.create_static_preview(reference)
	if preview == null:
		return
	holder.add_child(preview)
	preview.position = Vector2(35, 41) if boss else Vector2(40, 46)
	preview.scale = Vector2.ONE * (1.0 if boss else 1.6)

## 黑将军的纯视觉场景按缩略图尺寸摆好，并停在 idle 第一帧。
func _black_general_portrait(holder: Control) -> void:
	var packed := load(BLACK_GENERAL_VISUAL) as PackedScene
	if packed == null:
		return
	var preview := packed.instantiate() as BlackGeneralVisual
	if preview == null:
		return
	preview.position = Vector2(38, 69)
	preview.scale = Vector2.ONE * 0.48
	preview.ready.connect(_pose_black_general.bind(preview), CONNECT_ONE_SHOT)
	holder.add_child(preview)

func _pose_black_general(preview: BlackGeneralVisual) -> void:
	if not is_instance_valid(preview):
		return
	preview.play_action(&"idle")
	var player: AnimationPlayer = preview.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if player != null:
		player.seek(0.0, true)
		player.pause()

## 等阶徽章：底色与文字都取等阶目录的配色，1 阶为白色。
func _chip(badge: Dictionary) -> Label:
	var tint: Color = badge.get("color", Color.WHITE)
	var node := Label.new()
	node.text = str(badge.get("label", ""))
	node.add_theme_font_size_override("font_size", 17)
	node.add_theme_color_override("font_color", Color("fff8ec"))
	node.add_theme_color_override("font_outline_color", Color("14201a"))
	node.add_theme_constant_override("outline_size", 3)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(tint.r, tint.g, tint.b, 0.28)
	style.border_color = Color(tint.r, tint.g, tint.b, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 7.0
	style.content_margin_right = 7.0
	style.content_margin_top = 1.0
	style.content_margin_bottom = 1.0
	node.add_theme_stylebox_override("normal", style)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

## 分区小标题，用金色区分敌我两块。
func _caption(value: String) -> Control:
	var row := Control.new()
	row.custom_minimum_size = Vector2(0.0, 36.0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text(row, value, Rect2(Vector2(0, 10), Vector2(_content.size.x, 26.0)), 21, Color("c6ae70"))
	return row

## 单行说明文字，行高随字号增加。
func _line(value: String, font_size: int, color: Color) -> Control:
	var row := Control.new()
	row.custom_minimum_size = Vector2(0.0, font_size + 8.0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text(row, value, Rect2(Vector2(0, 0), Vector2(_content.size.x, font_size + 8.0)), font_size, color)
	return row

## 行间距占位。
func _spacer(height: float) -> Control:
	var row := Control.new()
	row.custom_minimum_size = Vector2(0.0, height)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return row

## 创建不拦截鼠标的文字层；[param clip] 为真时超长名称截断而不是撑破行。
func _text(parent: Control, value: String, rect: Rect2, font_size: int, color: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, clip: bool = false) -> Label:
	var node := Label.new()
	node.text = value
	node.position = rect.position
	node.size = rect.size
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	node.add_theme_color_override("font_outline_color", Color("0d1712"))
	node.add_theme_constant_override("outline_size", 4)
	node.horizontal_alignment = align
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	node.clip_text = clip
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

## 优先放在节点右侧，空间不足翻到左侧；纵向夹在安全区内。
func _place(anchor: Rect2) -> void:
	var x: float = anchor.end.x + GAP
	if x + PANEL_SIZE.x > DESIGN_SIZE.x - 32.0:
		x = anchor.position.x - GAP - PANEL_SIZE.x
	x = clampf(x, 32.0, DESIGN_SIZE.x - 32.0 - PANEL_SIZE.x)
	var y: float = anchor.get_center().y - PANEL_SIZE.y * 0.5
	y = clampf(y, SAFE_TOP, SAFE_BOTTOM - PANEL_SIZE.y)
	position = Vector2(x, y)
