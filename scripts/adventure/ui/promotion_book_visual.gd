## 组合四阶转职书的底图、书皮和植物头像。物种和阶数由技能目录提供。
extends RefCounted

## 提供背包和图书馆共用的贴图控件。
const InventorySkin = preload("res://scripts/adventure/ui/inventory_skin.gd")
## 解析转职书素材并装配对应阶数的静态卡面。
const ItemArt = preload("res://scripts/adventure/ui/inventory_item_art.gd")

## 一至四阶书皮的圆章中心，以原始 256 × 256 贴图左上角为原点，单位为像素。
const MEDALLION_CENTERS: Array[Vector2] = [
	Vector2(135, 109), Vector2(133, 108), Vector2(135, 110), Vector2(133, 112),
]
## 四张方形书皮贴图的原始边长，单位为像素。
const COVER_ART_SIZE := 256.0
## 每像素书皮显示边长对应的头像倍率，沿用原来的图标比例。
const PORTRAIT_SCALE_PER_PIXEL := 0.00335

## 按物种和阶数缓存头像局部中心，重复展示同一外观时复用结果。
static var _portrait_centers: Dictionary[Vector2i, Vector2] = {}

## 在 [param parent] 的 [param bounds] 内绘制 [param item_id] 对应的书皮和头像。
## 书目或书皮素材无效时返回 false，头像缺失时仍保留书皮。
static func draw(parent: Node, item_id: String, bounds: Rect2) -> bool:
	var definition: Dictionary = AdventurePromotionCatalog.definition(item_id) # 读取书目对应的物种和阶数。
	var tier: int = int(definition.get("tier", 0)) # 一至四阶分别对应独立书皮。
	if tier < 1 or tier > 4:
		return false
	var background: String = ItemArt.backing_uri(item_id) # 四阶书共用的道具底图。
	var cover: String = ItemArt.promotion_tier_uri(tier) # 当前阶数的书皮原图。
	if background.is_empty() or cover.is_empty():
		push_error("Promotion book art missing for tier %d" % tier)
		return false
	InventorySkin.image(parent, background, bounds.position, bounds.size)
	InventorySkin.image(parent, cover, bounds.position, bounds.size)
	var plant_type: int = int(definition.get("plant_type", 0)) # 确定书皮上展示的植物卡面。
	var cover_side: float = minf(bounds.size.x, bounds.size.y) # 书皮在矩形槽内等比居中。
	var cover_origin: Vector2 = bounds.get_center() - Vector2.ONE * cover_side * 0.5 # 方形书皮的显示原点。
	# 将原图上的圆章中心换算到父节点坐标。
	var center: Vector2 = cover_origin + MEDALLION_CENTERS[tier - 1] * (cover_side / COVER_ART_SIZE)
	var portrait_scale: float = cover_side * PORTRAIT_SCALE_PER_PIXEL # 随书皮一起缩放头像。
	# 对应阶数的静态卡面保留了卡牌自身的原点。
	var portrait: Node2D = ItemArt.add_recipe_portrait(parent, plant_type, center, portrait_scale, tier)
	if portrait != null:
		var key := Vector2i(plant_type, tier) # 同物种同阶数的不同技能共用同一外观。
		if not _portrait_centers.has(key):
			_portrait_centers[key] = _visible_bounds(portrait, Transform2D.IDENTITY).get_center()
		portrait.position -= portrait.transform.basis_xform(_portrait_centers[key])
	return true

## 将 [param node] 的可见精灵按 [param pose] 合并到头像根坐标。没有可见部件时返回空矩形。
static func _visible_bounds(node: Node2D, pose: Transform2D) -> Rect2:
	if not node.visible or node.modulate.a <= 0.0:
		return Rect2()
	var extent: Rect2 = _sprite_bounds(node as Sprite2D) # 只计入节点自身绘制的部分。
	if extent.has_area():
		extent = pose * extent
	for child: Node in node.get_children(): # 继续收集分件，含隐藏原精灵自身后显示的转职替换层。
		var part := child as Node2D # 动画等非绘制节点无需计入。
		if part == null:
			continue
		var part_extent: Rect2 = _visible_bounds(part, pose * part.transform) # 累积变换后再取外接矩形。
		if part_extent.has_area():
			extent = extent.merge(part_extent) if extent.has_area() else part_extent
	return extent

## 返回 [param sprite] 当前帧在精灵局部坐标中的非透明范围。无法读取贴图时沿用绘制矩形。
static func _sprite_bounds(sprite: Sprite2D) -> Rect2:
	if sprite == null or sprite.texture == null or sprite.self_modulate.a <= 0.0:
		return Rect2()
	var drawn: Rect2 = sprite.get_rect() # 含精灵的居中设置和偏移。
	var image: Image = sprite.texture.get_image() # 只在缓存头像中心时读取贴图像素。
	if image == null or image.is_empty() or (image.is_compressed() and image.decompress() != OK):
		return drawn
	if sprite.region_enabled or sprite.hframes > 1 or sprite.vframes > 1:
		var frame_origin: Vector2 = Vector2(sprite.frame_coords) * drawn.size # 帧在源区域内的左上角。
		if sprite.region_enabled:
			frame_origin += sprite.region_rect.position
		image = image.get_region(Rect2i(Rect2(frame_origin, drawn.size)))
	var used := Rect2(image.get_used_rect()) # 去掉当前帧周围的透明像素。
	if sprite.flip_h:
		used.position.x = drawn.size.x - used.end.x
	if sprite.flip_v:
		used.position.y = drawn.size.y - used.end.y
	return Rect2(drawn.position + used.position, used.size)
