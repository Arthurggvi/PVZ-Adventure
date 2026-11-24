## 编号徽章的舞台、铭牌、格子和悬停提示。只读取装备展示投影。
extends RefCounted

## 首通纪念徽章的稳定内容 ID。
const TEMPLE_ID: StringName = &"valhalla_temple_light"
## 纪念赠礼徽章的稳定内容 ID。
const BELOVED_ID: StringName = &"beloved_badge"
## 复用背包图标比例和标签布局。
const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")
## 延续工具栏悬停提示的内边距和圆角。
const HoverTip = preload("res://scripts/adventure/ui/hover_tip_skin.gd")
## 彩光在整行字形之间连续移动，标题与正文各自保持视觉层级。
const LETTERING_SHADER = preload("res://shaders/adventure/valhalla_badge_lettering.gdshader")
## 舞台、局部高光、字体和铭牌颜色按内容选择，贴图和材质按界面实际使用加载。
const STYLES := {
	TEMPLE_ID: {
		"stage": "res://shaders/adventure/valhalla_shrine.gdshader",
		"finish": "res://shaders/adventure/valhalla_badge_finish.gdshader",
		"font": "res://assets/adventure/ui/player/fonts/temple_badge_serif_sc_semibold.otf",
		"base": Color("0c1428"), "trim": Color("b99660"), "seal": Color("161b30"),
		"tip_base": Color("10192c"), "tip_trim": Color("c29859"), "seal_trim": Color("9c784968"),
		"gold": Color("ffe2a0"), "quiet": Color("d6ae68"), "body": Color("ece0c5"),
		"name": Color("fff0cc"), "dedication": "神殿首通者",
	},
	BELOVED_ID: {
		"stage": "res://shaders/adventure/beloved_badge_stage.gdshader",
		"finish": "res://shaders/adventure/beloved_badge_finish.gdshader",
		"font": "res://assets/adventure/ui/player/fonts/beloved_badge_kai_medium.ttf",
		"base": Color("321623"), "trim": Color("d5a26d"), "seal": Color("48202d"),
		"gold": Color("ffd69f"), "quiet": Color("dfa78b"), "body": Color("f8dfcd"),
		"name": Color("ffeddb"), "dedication": "献给",
	},
}
## 各款字号共用一套字体变体，未收录字形由 Godot 回退。
static var _display_fonts: Dictionary[StringName, FontVariation] = {}

## 判断 [param item] 是否使用专属展示。普通徽章沿用装备格表现。
static func is_definition(item: EquipmentDefinition) -> bool:
	return item != null and STYLES.has(item.id)

## 将 [param badge_id] 对应的 [param icon] 和金边底板画在 [param parent] 的 [param bounds] 内。
## 返回可用于即时更新悬停状态的独立材质。
static func draw_mark(parent: Node, badge_id: StringName, icon: Texture2D, bounds: Rect2) -> ShaderMaterial:
	var finish: Shader = load(STYLES[badge_id].finish) as Shader # 格子底和局部高光各有独立材质。
	var backing := ColorRect.new() # 矢量边缘和暗部填色不另加载贴图。
	backing.position = bounds.position
	backing.size = bounds.size
	backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame_material := ShaderMaterial.new() # 每个格子分别更新选中亮度。
	frame_material.shader = finish
	backing.material = frame_material
	parent.add_child(backing)
	var inset: float = minf(bounds.size.x, bounds.size.y) * 0.095 # 保留切角金边，图案仍填满中央区域。
	var icon_bounds: Rect2 = bounds.grow(-inset) # 图标与底板同心。
	var art: TextureRect = Art.image(parent, "", icon_bounds.position, icon_bounds.size) # 按原比例保留四翼和神殿。
	art.texture = icon
	if badge_id == BELOVED_ID:
		art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS # 细金饰缩进小格时仍保持平滑。
	var icon_material := ShaderMaterial.new() # 只让原图暖色高光受扫光影响。
	icon_material.shader = finish
	icon_material.set_shader_parameter("icon_finish", true)
	art.material = icon_material
	return frame_material

## 在 [param parent] 的肖像区域建立 [param item] 的专属舞台并返回展台节点。
static func draw_stage(parent: Control, item: EquipmentDefinition) -> ColorRect:
	var badge_style: Dictionary = STYLES[item.id] # 背景和原画高光同属一款设计。
	var alcove := ColorRect.new() # 大幅背景独立于图标，不接收输入。
	alcove.mouse_filter = Control.MOUSE_FILTER_IGNORE
	alcove.size = parent.size
	var vault := ShaderMaterial.new() # 只在显式选中时加载大幅光效。
	vault.shader = load(badge_style.stage) as Shader
	vault.set_shader_parameter("stage_aspect", alcove.size.x / alcove.size.y)
	alcove.material = vault
	parent.add_child(alcove)
	var center: Vector2 = alcove.size * Vector2(0.5, 0.47) # 与神龛的光冕中心对齐。
	var edge: float = alcove.size.x * 0.64 # 余下空间留给光冕和拱顶。
	var art: TextureRect = Art.image(alcove, "", center - Vector2.ONE * edge * 0.5, Vector2.ONE * edge) # 单独悬浮，保留原画透明边缘。
	art.texture = item.icon
	if item.id == BELOVED_ID:
		art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS # 避免悬浮和缩放使细线跳闪。
	art.pivot_offset = art.size * 0.5
	var finish := ShaderMaterial.new() # 原画的圣焰或红宝石由各自的材质驱动。
	finish.shader = load(badge_style.finish) as Shader
	finish.set_shader_parameter("icon_finish", true)
	art.material = finish
	var base_y: float = art.position.y # 徽章在光冕中心上下漂浮，单位为设计像素。
	var drift: Tween = art.create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT) # 节点离树后自动停止。
	drift.tween_property(art, "position:y", base_y - 7.0, 2.65)
	drift.tween_property(art, "position:y", base_y + 5.0, 3.1)
	drift.tween_property(art, "position:y", base_y, 2.0)
	return alcove

## 用 [param progress] 同步 [param stage] 的展台背景与徽章；0 为收束，1 为展开。
static func set_stage_progress(stage: ColorRect, progress: float) -> void:
	var vault: ShaderMaterial = stage.material # 同一进度驱动揭幕和退场。
	var art: TextureRect = stage.get_child(0) # 展台内唯一的前景是浮动的徽章原画。
	vault.set_shader_parameter("arrival", progress)
	art.modulate.a = smoothstep(0.05, 0.81, progress)
	art.scale = Vector2.ONE * lerpf(0.81, 1.0, smoothstep(0.0, 0.92, progress))

## 在 [param parent] 的 [param bounds] 内揭开 [param row] 的完整铭牌，返回供角色面板同步的装配标记。
static func draw_detail(parent: Control, row: Dictionary, bounds: Rect2) -> Label:
	var item: EquipmentDefinition = row.definition # 内容仍来自装备定义。
	var badge_style: Dictionary = STYLES[item.id] # 铭文与编号印记沿用展台的配色。
	var plaque := Panel.new() # 暗底衬托刻字和右侧数值栏。
	var style := StyleBoxFlat.new() # 金边与展台相呼应。
	style.bg_color = badge_style.base
	style.border_color = badge_style.trim
	style.set_border_width_all(2)
	style.set_corner_radius_all(5)
	style.shadow_color = Color("241a19a0")
	style.shadow_size = 4
	style.shadow_offset = Vector2(0, 2)
	plaque.add_theme_stylebox_override("panel", style)
	plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plaque.position = bounds.position
	plaque.size = bounds.size
	parent.add_child(plaque)
	var seal_offset: float = 251.0 if item.id == BELOVED_ID else 166.0 # 挚爱之章还需要显示两项掉落加成。
	var text_width: float = bounds.size.x - seal_offset - 28.0 # 正文在番号牌左侧。
	var edition: String = _edition_caption(int(row.get("edition_uid", 0))) # 没有实例编号时不会显示占位 UID。
	var inscription: String = str(row.get("inscription", "")) # 只显示服务提供的镌刻，不随当前档案名称变化。
	_title(plaque, item.id, item.display_name, Rect2(20, 5, text_width, 37), 32)
	if not inscription.is_empty():
		_engraved_name(plaque, item.id, inscription, Vector2(20, 43), text_width)
	var story_top: float = 59.0 if inscription.is_empty() else 90.0 # 正文始终排在姓名之后。
	_gilt_rule(plaque, Vector2(20, story_top - 2.0), text_width, badge_style.quiet)
	_text(plaque, item.id, item.description, Rect2(20, story_top, text_width, 26), 19, badge_style.body)
	var status: Label = _serial_seal(plaque, item, edition, Vector2(bounds.size.x - seal_offset, 11)) # 外层只更新装配状态。
	plaque.modulate.a = 0.0
	var entry: Tween = plaque.create_tween().set_parallel(true) # 铭牌在光冕点亮后稍迟出现。
	entry.tween_property(plaque, "modulate:a", 1.0, 0.55).set_delay(0.13).set_trans(Tween.TRANS_SINE)
	entry.tween_property(plaque, "position:y", bounds.position.y, 0.58).from(bounds.position.y + 7.0) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return status

## 仅提示未选中 [param record] 的名称和 UID；完整铭牌在选择后展示。
static func tooltip(record: Dictionary) -> PanelContainer:
	var badge_id: StringName = record.collectible_badge_id # 格子投影包含对应款式的内容 ID。
	var badge_style: Dictionary = STYLES[badge_id] # 提示只复用配色与字形，不复制铭牌内容。
	var panel: PanelContainer = HoverTip.panel(8.0) # 小条浮在格子附近，避免挡住背包。
	var style := panel.get_theme_stylebox("panel").duplicate() as StyleBoxFlat # 普通装备仍使用原有主题。
	style.bg_color = badge_style.get("tip_base", badge_style.base)
	style.border_color = badge_style.get("tip_trim", badge_style.trim)
	panel.add_theme_stylebox_override("panel", style)
	var layout := HBoxContainer.new() # 名称和编号随字宽撑开。
	layout.add_theme_constant_override("separation", 14)
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(layout)
	var title: Label = _text(layout, badge_id, str(record.get("title", "")), Rect2(), 19, badge_style.name, true) # 容器管理标签宽度。
	title.clip_text = false
	var edition: String = _edition_caption(int(record.get("edition_uid", 0))) # 未登记编号时不放占位文字。
	if not edition.is_empty():
		var serial: Label = _text(layout, badge_id, edition, Rect2(), 16, badge_style.quiet) # 次要信息不使用流彩。
		serial.clip_text = false
	return panel

## 在 [param parent] 中按 [param badge_id] 绘制 [param caption] 的彩光标题，[param bounds] 和 [param font_size] 控制字形布局。
static func _title(parent: Control, badge_id: StringName, caption: String, bounds: Rect2, font_size: int) -> void:
	var title: Label = _text(parent, badge_id, caption, bounds, font_size, Color.WHITE, true) # 白色字面承接彩光，暗色字影保留外轮廓。
	var lettering := ShaderMaterial.new() # 每个标题按自身文本像素宽度映射彩光。
	lettering.shader = LETTERING_SHADER
	lettering.set_shader_parameter("rose_gold", badge_id == BELOVED_ID)
	lettering.set_shader_parameter("text_width", title.get_theme_font("font").get_string_size(caption,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	title.material = lettering

## 在 [param parent] 的 [param origin] 按 [param badge_id] 排称谓与独占一行的 [param inscription]，宽度为 [param width] 像素。
static func _engraved_name(parent: Control, badge_id: StringName, inscription: String, origin: Vector2, width: float) -> void:
	var badge_style: Dictionary = STYLES[badge_id] # 献礼称谓与首通称谓各自使用对应的文案。
	_text(parent, badge_id, badge_style.dedication, Rect2(origin, Vector2(width, 15)), 13, badge_style.quiet, true)
	var name_bounds := Rect2(origin + Vector2(0, 15), Vector2(width, 29)) # 姓名独占一行。
	_text(parent, badge_id, inscription, name_bounds, 26, badge_style.name, true)

## 在 [param parent] 的 [param origin] 制作 [param item] 的 [param edition] 号印记并返回装配标记。
static func _serial_seal(parent: Control, item: EquipmentDefinition, edition: String, origin: Vector2) -> Label:
	var badge_style: Dictionary = STYLES[item.id] # 独立编号栏沿用铭牌色彩。
	var seal := Panel.new() # 编号和效果不占用姓名所在行。
	seal.position = origin
	seal.size = Vector2(233 if item.id == BELOVED_ID else 148, 98)
	seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var edge := StyleBoxFlat.new() # 细金边下的深色凹底。
	edge.bg_color = badge_style.seal
	edge.border_color = badge_style.get("seal_trim", Color(badge_style.trim, 0.43))
	edge.set_border_width_all(1)
	edge.set_corner_radius_all(4)
	seal.add_theme_stylebox_override("panel", edge)
	parent.add_child(seal)
	if item.id == BELOVED_ID:
		_effect_line(seal, "金币掉落率", item.coin_drop_chance_multiplier, 6.0)
		_effect_line(seal, "材料掉落率", item.material_drop_chance_multiplier, 34.0)
		_gilt_rule(seal, Vector2(12, 66), 209.0, badge_style.quiet)
		_text(seal, item.id, edition, Rect2(12, 72, 148, 20), 15, badge_style.quiet)
		var equipped: Label = _text(seal, item.id, "已装备", Rect2(162, 72, 59, 20), 13, badge_style.body) # 右侧状态随槽位同步。
		equipped.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		return equipped
	_text(seal, item.id, "绝版限定", Rect2(4, 8, 140, 20), 15, badge_style.quiet, true).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gilt_rule(seal, Vector2(17, 34), 114.0, badge_style.quiet)
	if not edition.is_empty():
		var serial_size: int = 24 if edition.length() <= 10 else 13 # 较长的 JSON 安全整数编号也能完整显示。
		_text(seal, item.id, edition, Rect2(5, 38, 138, 32), serial_size, badge_style.gold, true).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var status: Label = _text(seal, item.id, "已装备", Rect2(4, 72, 140, 19), 13, badge_style.body) # 装配状态不影响铭牌的动画。
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return status

## 在 [param seal] 的 [param y] 位置展示 [param caption] 和对应的相对倍率 [param multiplier]。
static func _effect_line(seal: Control, caption: String, multiplier: float, y: float) -> void:
	var badge_style: Dictionary = STYLES[BELOVED_ID] # 加成字色呼应红宝石外沿的暖金。
	_text(seal, BELOVED_ID, caption, Rect2(12, y, 124, 26), 17, badge_style.body)
	var bonus: String = "+%d%%" % roundi((multiplier - 1.0) * 100.0) # 直接读取装备效果而非另写显示数值。
	_text(seal, BELOVED_ID, bonus, Rect2(136, y, 85, 26), 20, badge_style.gold).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

## 在 [param parent] 内从 [param origin] 起绘制长 [param width] 像素、用 [param color] 着色的渐隐刻线。
static func _gilt_rule(parent: Control, origin: Vector2, width: float, color: Color) -> void:
	var rule := Line2D.new() # 细线随容器整体缩放，不截获悬停或点击。
	rule.points = PackedVector2Array([origin, origin + Vector2(width, 0.0)])
	rule.width = 1.0
	rule.gradient = Gradient.new()
	rule.gradient.set_color(0, Color(color, 0.69))
	rule.gradient.set_color(1, Color(color, 0.0))
	parent.add_child(rule)

## 将正整数 [param edition_uid] 格式化为玩家可见的 UID；零或负数代表没有展示编号。
static func _edition_caption(edition_uid: int) -> String:
	return "UID #%d" % edition_uid if edition_uid > 0 else ""

## 在 [param parent] 的 [param bounds] 内用 [param badge_id] 的字体画 [param caption]，[param font_size] 和 [param color] 控制字号与色彩，[param tracked] 开启题字字距。
static func _text(parent: Control, badge_id: StringName, caption: String, bounds: Rect2, font_size: int,
		color: Color, tracked: bool = false) -> Label:
	var label: Label = Art.label(parent, caption, bounds.position, bounds.size, font_size, color) # 复用背包的标签布局。
	var display: FontVariation = _display_fonts.get(badge_id) # 字体子集按款式共享。
	if display == null:
		var lettering := load(STYLES[badge_id].font) as FontFile # 只为实际展示款式加载字体。
		display = FontVariation.new()
		display.base_font = lettering if lettering != null else label.get_theme_font("font")
		display.spacing_glyph = 2
		_display_fonts[badge_id] = display
	label.add_theme_font_override("font", display if tracked else display.base_font)
	label.add_theme_color_override("font_shadow_color", Color("060b1a"))
	return label
