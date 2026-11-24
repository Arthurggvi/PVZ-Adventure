## 定格福音命中的植物原画，将每个可见部件拆成一次上传的微片。
extends Node2D

## 复用教堂投影读取动画帧、精灵网格和翻转的方式。
const Part = preload("res://scripts/battle/environment/battle_silhouette_part.gd")
## 每个部件共用相同碎裂材质，实际纹理来自植株。
const FRAGMENT_SHADER = preload("res://shaders/adventure/wonderland/savior_gospel_fragments.gdshader")
## 每次湮灭的微片网格上限。
const PIECE_BUDGET := 600
## 共用微片顶点顺序，纹理纵轴向下。
const CORNERS: Array[Vector2] = [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN]

## 本次从实际可见帧取得的材质实例。之后只推进统一的年龄。
var _surfaces: Array[ShaderMaterial] = []

## 植株 [param plant] 死亡前取最后一帧。用 [param world] 的画布将其对齐到柱底 [param foot]。
## [param span] 为格宽，用于限制碎片尺寸和漂移距离。返回是否采到可绘制的帧。
func capture(plant: Plant000Base, world: Node2D, foot: Vector2, span: float) -> bool:
	var sprites: Array[Node2D] = [] # 深度优先保留原画的树内叠放顺序。
	_collect(plant.body, sprites)
	var to_world: Transform2D = world.get_canvas_transform().affine_inverse() # 扣除相机和镜头震动。
	@warning_ignore("integer_division")
	var budget: int = PIECE_BUDGET / maxi(1, sprites.size()) # 为复杂的多部件植物均分实例数。
	for sprite: Node2D in sprites: # 每个部件只在湮灭帧组装一次。
		var part := Part.new(sprite) # 使用当帧纹理和真实绘制矩形。
		if not part.read_frame() or not _resolve_atlas(part):
			continue
		part.pose = to_world * sprite.get_global_transform_with_canvas()
		_add_surface(part, _tint(sprite), foot, span, maxi(1, budget))
	return not _surfaces.is_empty()

## [param age] 由外层柱体的战斗时钟统一提交。
func present(age: float) -> void:
	for material: ShaderMaterial in _surfaces: # 静态网格保持原样。
		material.set_shader_parameter(&"fracture_age", age)

## 从 [param node] 保留实际仍显示的精灵，按绘制顺序追加到 [param sprites]。
func _collect(node: Node, sprites: Array[Node2D]) -> void:
	if node is Node2D and not node.is_visible_in_tree():
		return
	if node is Sprite2D or node is AnimatedSprite2D:
		sprites.append(node)
	for child: Node in node.get_children(): # 包括精灵的附件层。
		_collect(child, sprites)

## 转换 [param part] 的逻辑帧区，将图集留白映射回实际纹理和原精灵的局部矩形。
func _resolve_atlas(part: Part) -> bool:
	while part.texture is AtlasTexture:
		var atlas := part.texture as AtlasTexture # 处理 AtlasTexture 叠用及已裁过的动画帧。
		if atlas.atlas == null:
			return false
		var region: Rect2 = atlas.region if atlas.region.has_area() else Rect2(Vector2.ZERO, atlas.atlas.get_size()) # 零范围使用全图。
		var crop: Rect2 = part.source.intersection(Rect2(atlas.margin.position, region.size)) # 排除原来只是透明留白的像素。
		if not crop.has_area():
			return false
		var lo: Vector2 = (crop.position - part.source.position) / part.source.size # 相对原帧的裁剪范围。
		var hi: Vector2 = (crop.end - part.source.position) / part.source.size # 在镜像时用于交换边缘。
		var sign_axes: Vector2 = part.rect.size.sign() # 把原有翻转延续给顶点 UV。
		var offset := Vector2(lo.x if sign_axes.x > 0.0 else 1.0 - hi.x, lo.y if sign_axes.y > 0.0 else 1.0 - hi.y) # 裁片在原姿态中的位置。
		part.rect.position += part.rect.size.abs() * offset
		part.rect.size *= hi - lo
		part.source = Rect2(region.position + crop.position - atlas.margin.position, crop.size)
		part.texture = atlas.atlas
	return part.source.has_area() and part.rect.size.abs().x > 0.0 and part.rect.size.abs().y > 0.0

## 求 [param sprite] 当前的颜色和继承透明度，片段仍可辨认植物的原有纹理。
func _tint(sprite: CanvasItem) -> Color:
	var tint: Color = sprite.self_modulate # 自调色只作用于本精灵。
	var layer: CanvasItem = sprite # CanvasItem 之间传递调色。
	while layer != null:
		tint *= layer.modulate
		layer = layer.get_parent() as CanvasItem
	return tint

## 为 [param part] 写入 UV 微片。[param tint] 保存原画色，[param foot]、[param span] 决定起爆位置和尺幅。
## [param budget] 是当前图层的微片数量上限。
func _add_surface(part: Part, tint: Color, foot: Vector2, span: float, budget: int) -> void:
	var rect := Rect2(part.rect.position, part.rect.size.abs()) # 正尺寸用于建立实际轮廓，镜像单独交给 UV。
	var size := Vector2(part.pose.x.length(), part.pose.y.length()) * rect.size # 屏幕缩放前的实际身体比例。
	var grid := Vector2i((size / (span * 0.068)).ceil().max(Vector2.ONE)) # 普通格上约四到五个世界像素一片。
	if grid.x * grid.y > budget:
		var ratio: float = sqrt(float(budget) / float(grid.x * grid.y)) # 大型原画也使用有限几何。
		grid = Vector2i((Vector2(grid) * ratio).floor().max(Vector2.ONE))
		@warning_ignore("integer_division")
		grid.y = mini(grid.y, maxi(1, budget / grid.x))
		grid.x = mini(grid.x, budget)
	var bounds: Rect2 = (part.pose * rect).grow(0.01) # 用此范围还原每片的旋转中心。
	var texture_size: Vector2 = part.texture.get_size() # 图集的纹素换算为采样坐标。
	var uv_start: Vector2 = (part.source.position + Vector2(0.35, 0.35)) / texture_size # 只在外缘避开相邻帧。
	var uv_span: Vector2 = (part.source.size - Vector2(0.70, 0.70)).max(Vector2.ZERO) / texture_size # 内部微片共享连续 UV。
	var orientation: Vector2 = part.rect.size.sign() # 翻转对应原画。
	var flipped: Vector2 = (Vector2.ONE - orientation) * 0.5 # UV 原点在被翻转的轴变为一。
	var vertices := PackedVector2Array() # 直接写入世界坐标，Shader 只加位移和转动。
	var uvs := PackedVector2Array() # 当前帧中的真实原画像素。
	var colors := PackedColorArray() # 两通道中心坐标和一个稳定随机值。
	var indices := PackedInt32Array() # 每块微片独立划分、共享四个角。
	var step: Vector2 = Vector2.ONE / Vector2(grid) # 网格单元归一化尺寸。
	for row: int in range(grid.y): # 从上往下覆盖实际图像。
		for column: int in range(grid.x): # 每行的原色纹理不会串到其他图层。
			var start: Vector2 = Vector2(column, row) * step # 位于部件帧内的左上角。
			var center: Vector2 = part.pose * (rect.position + rect.size * (start + step * 0.5)) # 此块微片的原世界中心。
			var anchor: Vector2 = (center - bounds.position) / bounds.size # 沿两轴压入顶点颜色。
			var salt: float = fposmod(sin(center.dot(Vector2(8.721, 2.367))) * 844.83, 1.0) # 每片独立破散速度。
			var index: int = vertices.size() # 此片两个三角形的起始顶点。
			for corner: Vector2 in CORNERS: # 保持相邻纹理边连续。
				var sample: Vector2 = start + step * corner # 实际帧内坐标。
				vertices.append(part.pose * (rect.position + rect.size * sample))
				uvs.append(uv_start + uv_span * (sample * orientation + flipped))
				colors.append(Color(anchor.x, anchor.y, salt, 1.0))
			indices.append_array(PackedInt32Array([index, index + 1, index + 2, index, index + 2, index + 3]))
	var arrays: Array = [] # Canvas ArrayMesh 的顶点数据。
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new() # 每个可见精灵部件只提交一个表面。
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := ShaderMaterial.new() # 复用 Shader、持有本部件几何和调色参数。
	material.shader = FRAGMENT_SHADER
	material.set_shader_parameter(&"frame_position", bounds.position)
	material.set_shader_parameter(&"frame_size", bounds.size)
	material.set_shader_parameter(&"source_origin", foot - Vector2(0.0, span * 0.54))
	material.set_shader_parameter(&"cell_span", span)
	material.set_shader_parameter(&"pose_tint", tint)
	var instance := MeshInstance2D.new() # 画出原画碎片而不保留植物节点或脚本。
	instance.mesh = mesh
	instance.texture = part.texture
	instance.material = material
	instance.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(instance)
	_surfaces.append(material)
