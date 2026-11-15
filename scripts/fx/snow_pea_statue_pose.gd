## 采集僵尸致死前的原画姿势，以轮廓内透明冰壳和自下而上的结晶显示冰雕。
extends Node2D
class_name SnowPeaStatuePose

## 冰壳只采样原画，不复制僵尸的动画、状态材质或游戏逻辑。
const ICE_SHADER: Shader = preload("res://scripts/fx/snow_pea_statue_ice.gdshader")
## 结晶扫描的有效战斗秒数，结束后停止逐帧处理。
const FORM_SECONDS: float = 0.42

## 一片冻结的原画，保留姿势、帧选区和合成绘制层。
class Part:
	## 图集或当前动画帧纹理。
	var texture: Texture2D
	## 图像局部显示范围。
	var rect: Rect2
	## 帧的纹理采样范围。
	var region: Rect2
	## 含原生方向翻转的被冻结变换。
	var pose: Transform2D
	## 树内相对绘制层，打平到单个画布前用于排序。
	var depth: int
	## 同层按原遍历顺序保持遮挡顺序。
	var order: int

## 当前冰雕唯一的绘制数据，不持有原节点。
var _parts: Array[Part] = []
## 原画变换后的局部范围，用于结晶高度和破碎分布。
var _bounds: Rect2 = Rect2(-20.0, -82.0, 40.0, 82.0)
## 每座冰雕私有的形成进度，避免多座同时触发时相互重置。
var _ice_material: ShaderMaterial
## 当前结晶动画年龄，完成后保持静态。
var _age: float = 0.0

## 复制 [param body] 此刻的可见原画；[param feet] 为新设施局部原点。
func capture(body: BodyCharacter, feet: Vector2) -> void:
	_parts.clear()
	for node: Node in body.find_children("*", "", true, false): # 只采集可见静态纹理和正在显示的帧。
		if not (node is Sprite2D or node is AnimatedSprite2D) or not node.is_visible_in_tree():
			continue
		var part := Part.new() # 本分件的独立渲染快照。
		if node is Sprite2D:
			part.texture = node.texture
			if part.texture == null:
				continue
			part.rect = node.get_rect()
			var size: Vector2 = part.texture.get_size() / Vector2(node.hframes, node.vframes) # 当前图格的像素尺寸。
			part.region = node.region_rect if node.region_enabled else Rect2(Vector2(node.frame_coords) * size, size)
		else:
			if node.sprite_frames == null or not node.sprite_frames.has_animation(node.animation):
				continue
			part.texture = node.sprite_frames.get_frame_texture(node.animation, node.frame)
			if part.texture == null:
				continue
			var size: Vector2 = part.texture.get_size() # 动画帧使用其完整纹理范围。
			part.rect = Rect2(node.offset - (size * 0.5 if node.centered else Vector2.ZERO), size)
			part.region = Rect2(Vector2.ZERO, size)
		part.pose = node.global_transform
		part.pose.origin -= feet
		var center: Vector2 = part.rect.get_center() # 围绕分件显示框中心保留原生翻转。
		var mirror := Vector2(-1.0 if node.flip_h else 1.0, -1.0 if node.flip_v else 1.0) # 纹理翻转独立于节点缩放。
		part.pose *= Transform2D(0.0, center).scaled_local(mirror).translated_local(-center)
		part.depth = _depth(node, body)
		part.order = _parts.size()
		var extent: Rect2 = part.pose * part.rect # 包括持盾、弯腰及不同体型的真实可见范围。
		_bounds = extent if _parts.is_empty() else _bounds.merge(extent)
		_parts.append(part)
	_parts.sort_custom(_draws_before)
	queue_redraw()

## 安装时已取得最终世界位置，所有分件共享连续的结晶前沿。
func _ready() -> void:
	_ice_material = ShaderMaterial.new()
	_ice_material.shader = ICE_SHADER
	_ice_material.set_shader_parameter(&"vertical_bounds",
		Vector2(global_position.y + _bounds.position.y, global_position.y + _bounds.end.y))
	material = _ice_material

## [param delta] 只推进形成动画；完成后原画与冰壳不再重绘或更新参数。
func _process(delta: float) -> void:
	_age = minf(FORM_SECONDS, _age + delta)
	_ice_material.set_shader_parameter(&"formation", smoothstep(0.0, FORM_SECONDS, _age))
	if _age >= FORM_SECONDS:
		set_process(false)

## 返回冰雕原画的局部范围，提供给独立的形成与破碎画布。
func get_pose_bounds() -> Rect2:
	return _bounds

## 返回 [param sprite] 相对于 [param body] 的展开绘制层。
func _depth(sprite: CanvasItem, body: CanvasItem) -> int:
	var node: CanvasItem = sprite # 逐层折算相对绘制层级。
	var depth: int = 0 # 当前累计基础层。
	while is_instance_valid(node) and node != body:
		depth += node.z_index
		if not node.z_as_relative:
			break
		node = node.get_parent() as CanvasItem
	return depth

## 确定 [param first] 是否应先于 [param second] 绘制，确保同层稳定。
func _draws_before(first: Part, second: Part) -> bool:
	return first.order < second.order if first.depth == second.depth else first.depth < second.depth

## 按定格姿态绘制；一次画布提交，无需复制各分件节点或逐帧推进动画。
func _draw() -> void:
	for part: Part in _parts: # 原遮挡顺序保留。
		draw_set_transform_matrix(part.pose)
		draw_texture_rect_region(part.texture, part.rect, part.region)
	draw_set_transform(Vector2.ZERO)
