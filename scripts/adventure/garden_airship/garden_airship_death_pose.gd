## 死亡代理的无脚本绘制快照，沿用原贴图、图集、染色与可视动画轨。
extends Node2D

## 原动画允许在代理上写入的纯绘制属性。方法、音频和其他属性维持原角色的责任。
const VISUAL_PROPERTIES: Array[StringName] = [
	&"position", &"rotation", &"rotation_degrees", &"scale", &"skew", &"visible",
	&"frame", &"modulate", &"self_modulate", &"texture", &"offset", &"flip_h", &"flip_v",
]

## [param source] 是受击实体实际可见的身体，[param host] 是新旧绘制分支共有的战场根。返回仅含绘制节点的快照，或在身体不可见时返回 null。
static func capture(source: Node2D, host: CanvasItem) -> Node2D:
	if not is_instance_valid(source) or not source.is_visible_in_tree():
		return null
	var branch: Node2D = _copy_sprites(source) # 保留原路径以及父子图层关系。
	if branch == null:
		return null
	var pose := Node2D.new() # 由外层位移节点携带完整的世界变换。
	pose.modulate = inherited_tint(source, host)
	branch.transform = Transform2D.IDENTITY
	branch.z_index = 0
	branch.z_as_relative = true
	if source.use_parent_material:
		branch.material = snapshot_material(inherited_material(source.get_parent() as CanvasItem))
		branch.use_parent_material = false
	pose.add_child(branch)
	return pose


## [param source] 是纯绘制节点或通往精灵的 Node2D；返回删去脚本、碰撞及事件连接的分支。
static func _copy_sprites(source: Node2D) -> Node2D:
	if source is CollisionObject2D or source is CollisionShape2D or source is Marker2D:
		return null
	var result: Node2D # 只创建原生绘制节点和维持其变换的普通容器。
	if source is Sprite2D:
		var sprite := source as Sprite2D # 保留裁边、锚点和命中时实际显示的精灵帧。
		var copy := Sprite2D.new() # 纹理与材质共用原资源。
		copy.texture = sprite.texture
		copy.centered = sprite.centered
		copy.offset = sprite.offset
		copy.flip_h = sprite.flip_h
		copy.flip_v = sprite.flip_v
		copy.hframes = sprite.hframes
		copy.vframes = sprite.vframes
		copy.frame = sprite.frame
		copy.region_enabled = sprite.region_enabled
		copy.region_rect = sprite.region_rect
		copy.region_filter_clip_enabled = sprite.region_filter_clip_enabled
		result = copy
	elif source is AnimatedSprite2D:
		var sprite := source as AnimatedSprite2D # 只接续无玩法回调的死亡图集。
		var copy := AnimatedSprite2D.new() # 保留动画、帧号、亚帧进度及镜像。
		copy.sprite_frames = sprite.sprite_frames
		if sprite.sprite_frames != null:
			copy.animation = sprite.animation
			if sprite.is_playing() and is_death_clip(sprite.animation):
				copy.play(sprite.animation, sprite.get_playing_speed())
			copy.set_frame_and_progress(sprite.frame, sprite.frame_progress)
		copy.centered = sprite.centered
		copy.offset = sprite.offset
		copy.flip_h = sprite.flip_h
		copy.flip_v = sprite.flip_v
		result = copy
	else:
		result = Node2D.new()
	for child: Node in source.get_children(): # 装饰和素材中隐藏的候选帧也参与原死亡动画。
		if child is Node2D and not child is ZombieDropBase and child.name != &"NodeDrop":
			var branch: Node2D = _copy_sprites(child) # 不是通往有效绘制节点的容器会被忽略。
			if branch != null:
				result.add_child(branch)
	if not (result is Sprite2D or result is AnimatedSprite2D) and result.get_child_count() == 0:
		result.free()
		return null
	result.name = source.name
	result.transform = source.transform
	result.visible = source.visible
	result.modulate = source.modulate
	result.self_modulate = source.self_modulate
	result.material = snapshot_material(source.material)
	result.use_parent_material = source.use_parent_material
	result.light_mask = source.light_mask
	result.visibility_layer = source.visibility_layer
	result.texture_filter = source.texture_filter
	result.texture_repeat = source.texture_repeat
	result.z_as_relative = source.z_as_relative
	result.z_index = source.z_index
	return result


## 从 [param animation] 复制实际解析到 [param pose] 可见分支的价值轨，返回独立播放资源。
static func visual_clip(animation: Animation, pose: Node2D) -> Animation:
	var clean := Animation.new() # 原动画可以带死亡回调和音效，不能挂到代理。
	clean.length = animation.length
	for track: int in animation.get_track_count(): # 仅温和更新已有的视觉属性。
		if animation.track_get_type(track) != Animation.TYPE_VALUE or not animation.track_is_enabled(track):
			continue
		var path: NodePath = animation.track_get_path(track) # 只解析精灵或其普通容器。
		if path.get_subname_count() != 1 or path.get_subname(0) not in VISUAL_PROPERTIES:
			continue
		if pose.get_node_or_null(NodePath(path.get_concatenated_names())) is Node2D:
			animation.copy_track(track, clean)
	return clean


## [param clip] 为原动画名，返回它是否属于倒地或击毁演出。
static func is_death_clip(clip: StringName) -> bool:
	var name_lower: String = String(clip).to_lower() # 素材的 death 可能是通用名或带物种前缀。
	return name_lower.contains("death") or name_lower.ends_with("_die")


## 返回 [param source] 在现有画布中的有效绘制层级。
static func absolute_z(source: CanvasItem) -> int:
	var item: CanvasItem = source # 累加到画布边界，绝对 Z 当前层即可停止。
	var depth: int = 0 # 相对 Z 在同一画布逐级相加。
	while item != null:
		depth += item.z_index
		if not item.z_as_relative or item.top_level:
			break
		item = item.get_parent() as CanvasItem
	return depth


## 返回 [param source] 到共有画布父级 [param host] 之间的调色，不包括自身颜色。
static func inherited_tint(source: CanvasItem, host: CanvasItem) -> Color:
	var tint: Color = Color.WHITE # 角色根及战斗行的乘色留在快照中。
	var item: CanvasItem = source.get_parent() as CanvasItem # 自身 modulate 已留在快照对应节点。
	while item != null and item != host:
		tint *= item.modulate
		if item.top_level:
			break
		item = item.get_parent() as CanvasItem
	return tint


## 返回从 [param source] 起向上解析的当前材质，供断开原父节点继承时使用。
static func inherited_material(source: CanvasItem) -> Material:
	var item: CanvasItem = source # 按画布现有材质继承规则寻找拥有者。
	while item != null and item.use_parent_material and not item.top_level:
		var parent := item.get_parent() as CanvasItem # 普通 Node 会断开画布材质继承。
		if parent == null:
			break
		item = parent
	return item.material if item != null else null


## [param material] 是实际可见材质；锁定由角色独占的状态参数，静态渲染资源继续共用。
static func snapshot_material(material: Material) -> Material:
	return material.duplicate() as Material if material != null and material.resource_local_to_scene else material


## 返回 [param item] 的可见绘制屏幕范围，空范围表示没有可见像素。
static func canvas_bounds(item: Node2D) -> Rect2:
	if not item.visible:
		return Rect2()
	var local_bounds := Rect2() # 某些容器本身不绘制。
	if item is Sprite2D:
		var sprite := item as Sprite2D # get_rect 包含偏移、帧裁边及锚点。
		if sprite.texture != null:
			local_bounds = sprite.get_rect()
	elif item is AnimatedSprite2D:
		var sprite := item as AnimatedSprite2D # 当前图集帧可能比第一帧的完整画幅大。
		if sprite.sprite_frames != null and sprite.sprite_frames.has_animation(sprite.animation):
			var texture: Texture2D = sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame) # 当前实际画幅。
			if texture != null:
				local_bounds = Rect2(sprite.offset, texture.get_size())
				if sprite.centered:
					local_bounds.position -= local_bounds.size * 0.5
	var screen: Rect2 = item.get_global_transform_with_canvas() * local_bounds if local_bounds.has_area() else Rect2()
	for child: Node in item.get_children(): # 实体出界后只按实际残骸检查一次，不遍历场上角色。
		if child is Node2D:
			var extent: Rect2 = canvas_bounds(child) # 折算同一正在渲染的视口坐标。
			if extent.has_area():
				screen = screen.merge(extent) if screen.has_area() else extent
	return screen
