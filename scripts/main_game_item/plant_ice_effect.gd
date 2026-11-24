## 植物冰块仅负责原版前后层的脚点对齐与尺寸适配；沿用 IceEffect 的完整结束流程。
extends IceEffect
class_name PlantIceEffect

## 完整前层原 PNG 的非透明范围；文件名中的尺寸不是实际图片尺寸。
const FRONT_VISIBLE_RECT: Rect2 = Rect2(2.0, 2.0, 202.0, 211.0)
## 完整后层原 PNG 的非透明范围；前后层各自对齐脚点下方的同一包覆底边。
const BACK_VISIBLE_RECT: Rect2 = Rect2(2.0, 2.0, 206.0, 214.0)
## 小型植物的最低冰块宽度和脚点上方高度，单位为所属植物的局部像素。
const MINIMUM_SIZE: Vector2 = Vector2(64.0, 72.0)
## 冰块左右各保留的空隙，避免叶片贴住冰面边缘。
const SIDE_PADDING: float = 8.0
## 冰块顶端高于当前身体与真实受击区的余量。
const TOP_PADDING: float = 8.0
## 冰块底端低于身体与真实受击区的余量，避免脚点以下的纹理裸露。
const BOTTOM_PADDING: float = 2.0

## 入树后只读取所属植物的现有几何；不改变植物身体、碰撞或任何生命状态。
func _ready() -> void:
	var plant: Plant000Base = get_parent() as Plant000Base # 冰效始终直接挂在被冻植物下。
	if plant == null:
		return
	var foot: Vector2 = plant.to_local(plant.shadow.global_position) # 父类随后把本冰效移动到这个脚点。
	var bounds: Rect2 = Rect2(foot, Vector2.ZERO) # 包含脚点，保证偏置身体仍被完整包住。
	bounds = _body_bounds(plant.body, plant, bounds)
	bounds = _collision_bounds(plant, bounds)
	var half_width: float = maxf(absf(bounds.position.x - foot.x), absf(bounds.end.x - foot.x)) # 两侧按离脚点较远的一端取值。
	var bottom_margin: float = maxf(0.0, bounds.end.y - foot.y) + BOTTOM_PADDING # 包住阴影脚点以下的身体，只下移贴图。
	var above_foot_height: float = maxf(MINIMUM_SIZE.y, foot.y - bounds.position.y + TOP_PADDING) # 保持原有冰块顶端不动。
	var size: Vector2 = Vector2(maxf(MINIMUM_SIZE.x, half_width * 2.0 + SIDE_PADDING * 2.0),
		above_foot_height + bottom_margin) # 增加底部范围后仍按实际高度适配，不扩大碰撞。
	_fit_layer(icetrap, FRONT_VISIBLE_RECT, size, bottom_margin)
	_fit_layer(icetrap_2, BACK_VISIBLE_RECT, size, bottom_margin)

## 累积 [param node] 下可见身体贴图的范围，返回所属 [param plant] 局部坐标中的 [param bounds]。
## 仅在冻结开始时读取一次姿态，忽略睡眠图标、血条及其他身体以外的节点。
func _body_bounds(node: Node, plant: Plant000Base, bounds: Rect2) -> Rect2:
	if node is Sprite2D:
		var sprite: Sprite2D = node as Sprite2D # 普通植物的骨架贴图以自身绘图矩形为准。
		if sprite.texture != null and sprite.is_visible_in_tree() and sprite.self_modulate.a > 0.0:
			bounds = _merge_rect(bounds, sprite.get_rect(), sprite, plant)
	elif node is AnimatedSprite2D:
		var animated: AnimatedSprite2D = node as AnimatedSprite2D # 导入帧动画只读取当前可见帧。
		if animated.sprite_frames != null and animated.is_visible_in_tree() and animated.self_modulate.a > 0.0 \
				and animated.sprite_frames.has_animation(animated.animation) \
				and animated.frame < animated.sprite_frames.get_frame_count(animated.animation):
			var texture: Texture2D = animated.sprite_frames.get_frame_texture(animated.animation, animated.frame) # 当前帧可能尚未配置贴图。
			if texture != null:
				var frame_rect: Rect2 = Rect2(animated.offset, texture.get_size()) # 导入精灵保留原有中心与偏移。
				if animated.centered:
					frame_rect.position -= frame_rect.size * 0.5
				bounds = _merge_rect(bounds, frame_rect, animated, plant)
	for child: Node in node.get_children(): # 只遍历身体树，不访问新冰效或碰撞代理。
		bounds = _body_bounds(child, plant, bounds)
	return bounds

## 将 [param plant] 的真实受击形状并入 [param bounds]；无贴图姿态仍能按现有尺寸显示冰块。
func _collision_bounds(plant: Plant000Base, bounds: Rect2) -> Rect2:
	for child: Node in plant.hurt_box_component.hurt_box_real.get_children(): # 只读真实受击区，不使用长距离索敌范围。
		if child is CollisionShape2D:
			var collider: CollisionShape2D = child as CollisionShape2D # 禁用形状不参与当前可受击身体的适配。
			if collider.disabled or collider.shape == null:
				continue
			var dimensions: Vector2 = Vector2.ZERO # 现有角色使用的圆、胶囊及矩形尺寸。
			if collider.shape is RectangleShape2D:
				dimensions = (collider.shape as RectangleShape2D).size
			elif collider.shape is CapsuleShape2D:
				var capsule: CapsuleShape2D = collider.shape as CapsuleShape2D # 胶囊高度已包含上下圆帽。
				dimensions = Vector2(capsule.radius * 2.0, capsule.height)
			elif collider.shape is CircleShape2D:
				dimensions = Vector2.ONE * (collider.shape as CircleShape2D).radius * 2.0
			if dimensions.x > 0.0 and dimensions.y > 0.0:
				bounds = _merge_rect(bounds, Rect2(-dimensions * 0.5, dimensions), collider, plant)
		elif child is CollisionPolygon2D:
			var polygon: CollisionPolygon2D = child as CollisionPolygon2D # 多边形保持自身变换，不修改顶点。
			if not polygon.disabled:
				for point: Vector2 in polygon.polygon: # 把实际顶点逐个换算回植物局部坐标。
					bounds = bounds.expand(plant.to_local(polygon.to_global(point)))
	return bounds

## 将 [param node] 的绘图矩形 [param rect] 转入 [param plant] 局部坐标并合并到 [param bounds]。
func _merge_rect(bounds: Rect2, rect: Rect2, node: Node2D, plant: Plant000Base) -> Rect2:
	var relative: Transform2D = plant.global_transform.affine_inverse() * node.global_transform # 保留骨架旋转、缩放及当前朝向。
	return bounds.merge(relative * rect)

## 按 [param size] 缩放 [param sprite] 的非透明 [param visible_rect]，并以 [param bottom_margin] 下移贴图底边。
## 冰效根仍锚定阴影脚点；高度同步增加，因此冰块顶端不会随底边下移。
func _fit_layer(sprite: Sprite2D, visible_rect: Rect2, size: Vector2, bottom_margin: float) -> void:
	sprite.centered = false
	sprite.offset = -Vector2(visible_rect.get_center().x, visible_rect.end.y)
	sprite.scale = size / visible_rect.size
	sprite.position.y = bottom_margin
