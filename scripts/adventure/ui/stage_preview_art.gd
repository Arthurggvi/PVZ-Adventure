## 关卡预览共用的纯展示构造函数；只消费展示字典，不维护面板状态。
extends RefCounted

## 背包已有的图框、图片与数量角标绘制工具。
const InventorySkin = preload("res://scripts/adventure/ui/inventory_skin.gd")
## 背包已有的植物配方头像与蜡封绘制工具。
const InventoryItemArt = preload("res://scripts/adventure/ui/inventory_item_art.gd")
## 敌人头像窗口的设计边长。
const ENEMY_TILE := 76.0
## 掉落图标布局的基准边长，所有内部尺寸均随实际边长缩放。
const DROP_TILE := 56.0
## 敌人头像沿用的图鉴窗口。
const ALMANAC_WINDOW := "res://assets/image/Almanac/Almanac_ZombieWindow.png"
## 黑将军尚无静态卡牌模板，直接复用纯视觉场景。
const BLACK_GENERAL_VISUAL := "res://scenes/character/zombie_boss/black_general_visual.tscn"

## 在 [param parent] 的 [param pos] 绘制 [param entry] 的头像。
## 优先使用黑将军专用预览，其次使用展示字典的头像，最后回退到卡牌模板。
static func portrait(parent: Control, pos: Vector2, entry: Dictionary) -> void:
	var holder := Control.new() # 裁剪超出图鉴窗口的美术。
	holder.position = pos
	holder.size = Vector2(ENEMY_TILE, ENEMY_TILE)
	holder.clip_contents = true
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(holder)
	InventorySkin.image(holder, ALMANAC_WINDOW, Vector2.ZERO, holder.size)
	var boss: bool = int(entry.get("card_type", 0)) == ResourceCardReference.CardType.ZombieBoss # 决定卡牌类别与缩放。
	var role: int = int(entry.get("type", 0)) # 物种在当前类别中的稳定编号。
	if role <= 0:
		return
	if boss and role == CharacterRegistry.ZombieBossType.ZB002BlackGeneral:
		_black_general_portrait(holder)
		return
	var texture := entry.get("portrait") as Texture2D # Boss 图鉴提供的实战头像，可独立于卡牌存在。
	if texture != null:
		var image := TextureRect.new() # 在边框内等比居中显示头像。
		image.texture = texture
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(image)
		image.position = Vector2(4, 4)
		image.size = holder.size - Vector2(8, 8)
		return
	var reference := ResourceCardReference.create( # 兼容仅提供静态卡牌的角色。
		ResourceCardReference.CardType.ZombieBoss if boss else ResourceCardReference.CardType.Zombie, role)
	if AllCards.get_template_path(reference).is_empty(): # 未注册模板的物种只保留空窗口。
		return
	var preview: Node2D = AllCards.create_static_preview(reference) # 卡牌的独立静态副本。
	if preview == null:
		return
	holder.add_child(preview)
	preview.position = Vector2(35, 41) if boss else Vector2(40, 46)
	preview.scale = Vector2.ONE * (1.0 if boss else 1.6)

## 在 [param holder] 内放置黑将军缩略图，并在入树后停到待机首帧。
static func _black_general_portrait(holder: Control) -> void:
	var packed := load(BLACK_GENERAL_VISUAL) as PackedScene # 黑将军的纯视觉场景资源。
	if packed == null:
		return
	var preview := packed.instantiate() as BlackGeneralVisual # 不含战斗逻辑的独立视觉实例。
	if preview == null:
		return
	preview.position = Vector2(38, 69)
	preview.scale = Vector2.ONE * 0.48
	preview.ready.connect(_pose_black_general.bind(preview), CONNECT_ONE_SHOT)
	holder.add_child(preview)

## 将 [param preview] 的待机动画定位到首帧并暂停。
static func _pose_black_general(preview: BlackGeneralVisual) -> void:
	if not is_instance_valid(preview):
		return
	preview.play_action(&"idle")
	var player: AnimationPlayer = preview.get_node_or_null("AnimationPlayer") as AnimationPlayer # 待机动画播放器。
	if player != null:
		player.seek(0.0, true)
		player.pause()

## 绘制 [param drop] 的掉落图标；[param edge] 为图框边长，内部美术按同一比例缩放。
## [param show_count] 为假时省略数量角标，供跨来源汇总使用；角标仍以硬上限优先。
static func drop_tile(drop: Dictionary, edge: float = 56.0, show_count: bool = true) -> Control:
	var extent := maxf(edge, 1.0) # 保证图框边长为正。
	var ratio := extent / DROP_TILE # 相对于原有五十六像素图框的统一缩放比例。
	var cell := Control.new() # 独立图标单元，也裁剪异常素材的越界部分。
	cell.custom_minimum_size = Vector2(extent, extent)
	cell.size = cell.custom_minimum_size
	cell.clip_contents = true
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	InventorySkin.image(cell, "slots/item_slot_normal.png", Vector2.ZERO, cell.custom_minimum_size)
	var backing := str(drop.get("backing", "")) # 配方等物品使用的底图。
	if not backing.is_empty():
		InventorySkin.image(cell, backing, Vector2(4, 4) * ratio, Vector2(48, 48) * ratio)
	var icon := str(drop.get("icon", "")) # 掉落条目的主图标。
	if not icon.is_empty():
		InventorySkin.image(cell, icon, Vector2(8, 8) * ratio, Vector2(40, 40) * ratio)
	var icon_scale: float = 40.0 * ratio / 58.0 # 继续沿用背包图标的五十八像素缩放基准。
	var plant_type := int(drop.get("plant_type", 0)) # 配方对应的植物编号，零表示无植物头像。
	if plant_type > 0:
		InventoryItemArt.add_recipe_portrait(cell, plant_type, cell.custom_minimum_size * 0.5, 0.42 * icon_scale)
	var wax := InventoryItemArt.recipe_overlay_uri(str(drop.get("id", ""))) # 配方类型对应的蜡封贴图。
	if not wax.is_empty():
		InventorySkin.image(cell, wax, Vector2(8, 8) * ratio + Vector2(35, 39) * icon_scale, Vector2(20, 20) * icon_scale)
	if not show_count:
		return cell
	var count := int(drop.get("count", 1)) # 固定数量或随机区间的下限。
	var cap := int(drop.get("cap", 0)) # 零表示没有装备加成后的硬上限。
	var count_size := maxi(1, int(round(14.0 * ratio))) # 数量角标随图框同步缩放。
	if cap > 0:
		InventorySkin.count_badge(cell, "≤%d" % cap, cell.custom_minimum_size, Color("fff4d6"), count_size)
	elif count >= 2:
		InventorySkin.count_badge(cell, "×%d" % count, cell.custom_minimum_size, Color("fff4d6"), count_size)
	return cell

## 根据 [param badge] 的文字和目录配色创建等阶徽章。
static func chip(badge: Dictionary) -> Label:
	var tint: Color = badge.get("color", Color.WHITE) # 等阶目录提供的徽章主色。
	var node := Label.new() # 展示徽章名称的文字节点。
	node.text = str(badge.get("label", ""))
	node.add_theme_font_size_override("font_size", 17)
	node.add_theme_color_override("font_color", Color("fff8ec"))
	node.add_theme_color_override("font_outline_color", Color("14201a"))
	node.add_theme_constant_override("outline_size", 3)
	var style := StyleBoxFlat.new() # 半透明底色与细边框共用等阶配色。
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

## 在 [param parent] 的 [param rect] 内创建内容为 [param value] 的文字层。
## [param font_size] 与 [param color] 控制字号和字色，[param align] 控制水平对齐。
## [param clip] 为真时裁剪超长文字；所有文字层均不拦截鼠标。
static func text(parent: Control, value: String, rect: Rect2, font_size: int, color: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, clip: bool = false) -> Label:
	var node := Label.new() # 放置到指定矩形内的文字节点。
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
