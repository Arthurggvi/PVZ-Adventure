## 柱光的施法者遮挡。统一把原画帧、翻转与继承透明度换算到当前视口。
extends RefCounted

## 读取施法者的当前原画，用于遮住位于身后的柱芯。
const SilhouettePart = preload("res://scripts/battle/environment/battle_silhouette_part.gd")

## 将 [param pose] 的当前原画映射到 [param shader_material]。由 [param view] 提供实际视口，失效或隐藏时返回 false。
static func bind_pose(pose: SilhouettePart, shader_material: ShaderMaterial, view: Rect2) -> bool:
	if pose == null or not is_instance_valid(pose.sprite):
		return false
	var sprite := pose.sprite as AnimatedSprite2D # 裁切与镜像使用当前动画帧。
	if not sprite.is_visible_in_tree() or not pose.read_frame():
		return false
	var texture: Texture2D = pose.texture # 可能是动画图集中的分区。
	var source: Rect2 = pose.source # 原图集中的帧内采样矩形。
	if texture is AtlasTexture:
		source = texture.region
		texture = texture.atlas
	var to_pose: Transform2D = sprite.get_global_transform_with_canvas().affine_inverse() # 使用同一实际相机。
	var flips := Vector2(float(sprite.flip_h), float(sprite.flip_v)) # 恢复精灵的镜像纹理方向。
	var axes: Vector2 = (Vector2.ONE - flips * 2.0) / pose.rect.size.abs() # 映射为帧内归一化坐标。
	var column_x: Vector2 = to_pose.x * view.size.x * axes # 屏幕 X 单位在精灵内的跨度。
	var column_y: Vector2 = to_pose.y * view.size.y * axes # 屏幕 Y 单位在精灵内的跨度。
	var offset: Vector2 = ((to_pose * view.position) - pose.rect.position) * axes + flips # 屏幕左上角的源帧坐标。
	var low: Vector2 = (source.position + Vector2(0.5, 0.5)) / texture.get_size() # 绑定首个纹素中心。
	var span: Vector2 = (source.size - Vector2.ONE) / texture.get_size() # 确保线性采样不串到相邻帧。
	var opacity: float = sprite.self_modulate.a # 源原画褪色时也减弱其遮挡。
	var layer: CanvasItem = sprite # 沿场景树计算实际继承的透明度。
	while layer != null:
		opacity *= layer.modulate.a
		layer = layer.get_parent() as CanvasItem
	shader_material.set_shader_parameter(&"owner_sheet", texture)
	shader_material.set_shader_parameter(&"owner_source", Vector4(low.x, low.y, span.x, span.y))
	shader_material.set_shader_parameter(&"owner_axes", Vector4(column_x.x, column_x.y, column_y.x, column_y.y))
	shader_material.set_shader_parameter(&"owner_offset", offset)
	shader_material.set_shader_parameter(&"owner_opacity", opacity)
	return true
