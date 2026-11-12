## 图鉴预览复用静态卡面与角色待机动画，展示实例不进入出战模式。
extends RefCounted

## 共用物种到场景、卡牌身份和阶级 ID 的解析。
const Data = preload("res://scripts/adventure/ui/almanac_data.gd")

## 在 [param parent] 的 [param bounds] 中绘制 [param kind]、[param type_id] 的一阶目录缩略图。
## 返回是否绘制成功；只在目录中缩短超出本体的旗杆和撑杆。
static func draw_thumbnail(parent: Control, kind: String, type_id: int, bounds: Rect2) -> bool:
	return _draw_static(parent, kind, type_id, 1, bounds, true)

## 为 [param kind]、[param type_id]、[param tier] 创建独立形象，放入 [param parent] 的 [param bounds]。
## [param thumbnail] 为 true 时使用目录道具比例。返回是否具有可见精灵；缺少卡牌模板时从注册场景提取静态精灵。
static func _draw_static(parent: Control, kind: String, type_id: int, tier: int, bounds: Rect2, thumbnail: bool = false) -> bool:
	var card_reference: ResourceCardReference = Data.card_reference(kind, type_id) # 共享静态预览入口能够自动接收未来植物转职美术。
	var has_template: bool = AllCards.get_template(card_reference) != null # 目录道具的握点使用卡牌模板的坐标。
	var preview: Node2D # 独立副本，切换阶级后随父容器销毁。
	if has_template:
		preview = AllCards.create_static_preview(card_reference, tier - 1 if kind == "plant" else 0)
	else:
		preview = _from_scene(kind, type_id)
	if preview == null:
		return false
	preview.transform = Transform2D.IDENTITY
	if kind == "zombie":
		AdventureZombieTierArt.apply_to_preview(preview, type_id, Data.tier_id(tier))
		if thumbnail and has_template:
			match type_id:
				CharacterRegistry.ZombieType.Z002Flag:
					_compact_prop(preview, ["Zombie_flagpole", "Zombie_flag"], Vector2(0, 54), Vector2(0.7, 0.4))
				CharacterRegistry.ZombieType.Z004PoleVaulter:
					_compact_prop(preview, ["Zombie_polevaulter_pole", "Zombie_polevaulter_pole2"], Vector2(19, 13), Vector2(0.6, 1.0))
	if not _fit_visual(preview, bounds):
		preview.free()
		return false
	parent.add_child(preview)
	return true

## 在 [param preview] 中把同一件道具的 [param part_names] 围绕握点 [param grip] 按 [param compression] 缩短。
## 握点使用卡牌模板 BodyCorrect 的局部坐标，部件共用一次变换以保持接缝和握姿。
static func _compact_prop(preview: Node2D, part_names: Array[String], grip: Vector2, compression: Vector2) -> void:
	var pose: Transform2D = Transform2D.IDENTITY.scaled(compression) # 以握点为中心缩放，不改变持握手的位置。
	pose.origin = grip - pose * grip
	for part_name: String in part_names: # 旗面与旗杆、撑杆的两段需要一起变换。
		var part := preview.find_child(part_name, true, false) as Sprite2D # 修改独立卡面副本中的道具精灵。
		if part != null:
			part.transform = pose * part.transform

## 在 [param parent] 的 [param bounds] 中展示 [param kind]、[param type_id]、[param tier] 的角色待机。
## 复用原版展示初始化和冒险阶级美术；场景缺失或没有可用图像时回退为卡面。
static func draw_idle(parent: Control, kind: String, type_id: int, tier: int, bounds: Rect2) -> bool:
	var packed: PackedScene = Data.scene_for(kind, type_id) # 实战和图鉴共用注册场景。
	if packed == null:
		return _draw_static(parent, kind, type_id, tier, bounds)
	var source: Node = packed.instantiate() # 每次切换创建独立实例。
	var character := source as Character000Base # 仅角色场景支持 IsShow 生命周期。
	if character == null:
		source.free()
		return _draw_static(parent, kind, type_id, tier, bounds)
	character.character_init_type = Character000Base.E_CharacterInitType.IsShow
	character.is_show = true
	character.is_idle = true
	if character is Plant000Base:
		character.plant_type = type_id as CharacterRegistry.PlantType
		if type_id == AdventureSunflowerPromotionArt.SUNFLOWER_TYPE and tier > 1:
			AdventureSunflowerPromotionArt.apply_to_body(character.get_node_or_null("Body/BodyCorrect") as Node2D, tier - 1)
	elif character is Zombie000Base:
		var id: StringName = Data.tier_id(tier) # 只应用美术和对应色调。
		character.zombie_type = type_id as CharacterRegistry.ZombieType
		if not AdventureZombieTierArt.apply(character, id):
			character.modulate = AdventureZombieTierCatalog.get_tier(id).get("tint", Color.WHITE)
	parent.add_child(character)
	# 应用待机首帧的姿态，再按实际可见精灵计算边界。
	if character.anim_component is AnimComponentNorm:
		character.anim_component.animation_tree.advance(0.0)
	elif character.anim_component is AnimComponentPlayer:
		character.anim_component.animation_player.advance(0.0)
	if not _fit_visual(character, bounds):
		parent.remove_child(character)
		character.queue_free()
		return _draw_static(parent, kind, type_id, tier, bounds)
	return true

## 将 [param preview] 的可见部件等比居中到 [param bounds]；空图像返回 false。
static func _fit_visual(preview: Node2D, bounds: Rect2) -> bool:
	var rectangles: Array[Rect2] = [] # 实际可见精灵的外接矩形，适配巨人、车辆等不同大小。
	_collect_bounds(preview, Transform2D.IDENTITY, rectangles)
	if rectangles.is_empty():
		return false
	var extent: Rect2 = rectangles[0] # 所有静态部件在预览根坐标中的并集。
	for index: int in range(1, rectangles.size()): # 合并身体、头部、防具等部分。
		extent = extent.merge(rectangles[index])
	if extent.size.x <= 0.0 or extent.size.y <= 0.0:
		return false
	var factor: float = minf(bounds.size.x / extent.size.x, bounds.size.y / extent.size.y) # 保持长宽比且不裁掉大型角色。
	preview.scale = Vector2.ONE * factor
	preview.position = bounds.get_center() - extent.get_center() * factor
	return true

## 将 [param node] 的可见图像范围变换到 [param transform] 所在坐标，收集到 [param result]。
## [param skip_branch] 可排除与本体比例无关的道具节点及其子树。
static func _collect_bounds(node: Node, transform: Transform2D, result: Array[Rect2], skip_branch: Callable = Callable()) -> void:
	if skip_branch.is_valid() and skip_branch.call(node):
		return
	if node is CanvasItem and not node.visible:
		return
	if node is Sprite2D and node.texture != null and node.self_modulate.a > 0.0:
		result.append(transform * node.get_rect())
	for child: Node in node.get_children(): # 不依赖角色名称或固定源图片尺寸。
		var child_transform: Transform2D = transform * child.transform if child is Node2D else transform # 从父坐标累积变换。
		_collect_bounds(child, child_transform, result, skip_branch)

## 从 [param kind]、[param type_id] 的注册场景提取精灵，缺少源场景时返回 null。
static func _from_scene(kind: String, type_id: int) -> Node2D:
	var packed: PackedScene = Data.scene_for(kind, type_id) # 仅实例化未入树的源，不运行 _ready。
	if packed == null:
		return null
	var source: Node = packed.instantiate() # 临时源始终在本函数结束前释放。
	var visual := Node2D.new() # 无脚本的可见部件容器。
	_copy_sprites(source, visual, Transform2D.IDENTITY)
	source.free()
	return visual

## 复制 [param source] 的静态精灵到 [param target]；[param transform] 累积原始部件位置，不复制脚本、碰撞或动画。
static func _copy_sprites(source: Node, target: Node2D, transform: Transform2D) -> void:
	if source is CanvasItem and not source.visible:
		return
	if source is Sprite2D and source.texture != null:
		var sprite := Sprite2D.new() # 只复制视觉属性，共享纹理只读。
		sprite.texture = source.texture
		sprite.centered = source.centered
		sprite.offset = source.offset
		sprite.hframes = source.hframes
		sprite.vframes = source.vframes
		sprite.frame = source.frame
		sprite.flip_h = source.flip_h
		sprite.flip_v = source.flip_v
		sprite.region_enabled = source.region_enabled
		sprite.region_rect = source.region_rect
		sprite.transform = transform
		sprite.modulate = source.modulate * source.self_modulate
		target.add_child(sprite)
	for child: Node in source.get_children(): # 不把任何 Character 或组件对象加入展示树。
		var child_transform: Transform2D = transform * child.transform if child is Node2D else transform # 将原始层级展平到纯视觉树。
		_copy_sprites(child, target, child_transform)
