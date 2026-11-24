## 精灵当前帧的信息，供动态投影和冻结剪影共同读取。
extends RefCounted

## 源精灵。冻结姿态读取完毕后可释放这个引用。
var sprite: Node2D
## 带原始 Alpha 的纹理。
var texture: Texture2D
## 当前帧的源纹理区域，单位纹素。
var source: Rect2
## 当前帧的本地绘制范围，负尺寸表示镜像。
var rect: Rect2
## 相对实体脚点或剪影挂载点的部件变换。
var pose: Transform2D
## 动态剪影映射到图集像素后的变换。
var atlas_pose: Transform2D
## 采样时可见的透明度。
var opacity: float

## [param source_sprite] 是当前采样的静态或动画精灵。
func _init(source_sprite: Node2D) -> void:
	sprite = source_sprite

## 读取源精灵当前正在绘制的帧，返回是否存在纹理和源矩形。
func read_frame() -> bool:
	if sprite is Sprite2D:
		var static_sprite := sprite as Sprite2D # 支持分区、帧网格、偏移和镜像。
		if static_sprite.texture == null:
			return false
		texture = static_sprite.texture
		var region: Rect2 = static_sprite.region_rect if static_sprite.region_enabled else Rect2(Vector2.ZERO, texture.get_size()) # 整张纹理或分区。
		var frame_size: Vector2 = region.size / Vector2(static_sprite.hframes, static_sprite.vframes) # 当前帧面积。
		source = Rect2(region.position + Vector2(static_sprite.frame_coords) * frame_size, frame_size)
		rect = static_sprite.get_rect()
	else:
		var animated := sprite as AnimatedSprite2D # 帧动画直接使用帧纹理。
		if animated == null or animated.sprite_frames == null or not animated.sprite_frames.has_animation(animated.animation):
			return false
		if animated.frame >= animated.sprite_frames.get_frame_count(animated.animation):
			return false
		texture = animated.sprite_frames.get_frame_texture(animated.animation, animated.frame)
		if texture == null:
			return false
		var frame_size: Vector2 = texture.get_size() # 从中心或左上角锚定。
		source = Rect2(Vector2.ZERO, frame_size)
		rect = Rect2(animated.offset - frame_size * 0.5 if animated.centered else animated.offset, frame_size)
	rect.size.x *= -1.0 if sprite.flip_h else 1.0
	rect.size.y *= -1.0 if sprite.flip_v else 1.0
	return true
