## 冥弹处决的纯姿势副本：渐白、分片、飘散；不复制任何角色或战斗组件。
extends Node2D
class_name RepeaterExecutionVisual

## 轮廓只存在九百毫秒，真实死亡由调用方立即结算。
const DURATION: float = 0.90
## 连续世界噪声让身体分件的破碎切面保持一致。
const SILHOUETTE_SHADER: Shader = preload("res://shaders/repeater/repeater_silhouette.gdshader")

## 一片原版身体纹理的静态绘制快照。
class Part:
	## 源部件当前纹理与选中帧区域。
	var texture: Texture2D
	## 相对于部件原点的显示矩形。
	var rect: Rect2
	## 当前帧的纹理采样范围。
	var region: Rect2
	## 世界姿态相对于采样原点的变换。
	var pose: Transform2D
	## 采样时累积颜色，原身体后续变化不再影响副本。
	var color: Color
	## 原画实际层级与同层顺序。
	var depth: int
	## 同层稳定顺序，避免排序破坏肢体遮挡。
	var order: int

## 已采集的纯图像部件。
var _parts: Array[Part] = []
## 白化材质只由本次演出使用。
var _ink: ShaderMaterial
## 表现经过的秒数。
var _age: float = 0.0
## 世界采样原点。
var _anchor: Vector2
## 原身体的近似局部边界，用于从轮廓周围散出星尘。
var _bounds: Rect2
## 独立星尘层不受身体破碎遮罩裁掉。
var _dust: Node2D

## 在 [param parent] 中复制 [param body] 此刻的可见姿势；必须在真实死亡前调用。
## 返回短命的纯图像节点，不隐藏原身体，调用者确认处决成功后负责隐藏原身。
static func capture(parent: Node, body: Node2D) -> Node2D:
	if not is_instance_valid(parent) or not is_instance_valid(body):
		return null
	var result := RepeaterExecutionVisual.new() # 释放后不留下角色引用或死亡监听。
	result._anchor = body.global_position
	result._capture_parts(body)
	if result._parts.is_empty():
		result.free()
		return null
	result.top_level = true
	result.z_as_relative = false
	result.z_index = mini(result._depth_of(body) + 2, RenderingServer.CANVAS_ITEM_Z_MAX)
	result._ink = ShaderMaterial.new()
	result._ink.shader = SILHOUETTE_SHADER
	result._ink.set_shader_parameter(&"phase", fposmod(body.global_position.x * 0.13, 71.0))
	result._copy_clipping(body)
	result.material = result._ink
	parent.add_child(result)
	result.global_position = result._anchor
	result._dust = Node2D.new()
	result._dust.material = RepeaterVisualPalette.glow_material()
	result._dust.draw.connect(result._draw_dust)
	result.add_child(result._dust)
	return result

## [param body] 当前若正使用原生出土或入水遮罩，副本保留同一裁切边界。
func _copy_clipping(body: Node2D) -> void:
	var original := body.material as ShaderMaterial # 不替换原角色材质，仅读取已知的遮罩协议。
	if original == null or original.shader == null or not original.shader.resource_path.ends_with("/body_mask.gdshader"):
		return
	_ink.set_shader_parameter(&"mask_enabled", true)
	_ink.set_shader_parameter(&"mask_cutoff", original.get_shader_parameter(&"cutoff_y"))
	_ink.set_shader_parameter(&"mask_world", original.get_shader_parameter(&"use_world_coordinates"))
	_ink.set_shader_parameter(&"mask_above", original.get_shader_parameter(&"clip_above"))
	_ink.set_shader_parameter(&"mask_fade", original.get_shader_parameter(&"fade_width"))

## 采集 [param body] 的可见纹理分件，保留帧选择、翻转和树内绘制顺序。
func _capture_parts(body: Node2D) -> void:
	for child: Node in body.find_children("*", "", true, false): # 不复制任何节点，只读取当时图像。
		if not child is Sprite2D and not child is AnimatedSprite2D:
			continue
		var sprite := child as Node2D # 两类原生精灵都拥有画布变换。
		if not sprite.is_visible_in_tree():
			continue
		var part := Part.new() # 本片纹理和框选区域。
		if sprite is Sprite2D:
			part.texture = sprite.texture
			if part.texture == null:
				continue
			part.rect = sprite.get_rect()
			var frame_size: Vector2 = part.texture.get_size() / Vector2(sprite.hframes, sprite.vframes) # 当前格帧尺寸。
			part.region = sprite.region_rect if sprite.region_enabled else Rect2(Vector2(sprite.frame_coords) * frame_size, frame_size)
		else:
			if sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(sprite.animation):
				continue
			part.texture = sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
			if part.texture == null:
				continue
			part.rect = Rect2(sprite.offset - (part.texture.get_size() * 0.5 if sprite.centered else Vector2.ZERO), part.texture.get_size())
			part.region = Rect2(Vector2.ZERO, part.texture.get_size())
		part.pose = sprite.global_transform
		part.pose.origin -= _anchor
		var center: Vector2 = part.rect.get_center() # 翻转以显示框中心为轴，不改变动画锚点。
		var mirror: Vector2 = Vector2(-1.0 if sprite.flip_h else 1.0, -1.0 if sprite.flip_v else 1.0) # 原生翻转方向。
		part.pose = part.pose * Transform2D(0.0, center).scaled_local(mirror).translated_local(-center)
		part.color = _color_of(sprite)
		part.depth = _depth_of(sprite)
		part.order = _parts.size()
		_bounds = _bounds.merge(part.pose * part.rect) if not _parts.is_empty() else part.pose * part.rect
		_parts.append(part)
	_parts.sort_custom(func(a: Part, b: Part) -> bool: return a.order < b.order if a.depth == b.depth else a.depth < b.depth)

## 返回 [param sprite] 从父画布继承的实际乘色，保留冻结和受击的当前外观。
func _color_of(sprite: CanvasItem) -> Color:
	var result: Color = sprite.self_modulate # 自身颜色不会传递给子节点。
	var cursor: Node = sprite # 累加可见画布的modulate。
	while cursor is CanvasItem:
		result *= cursor.modulate
		cursor = cursor.get_parent()
	return result

## 返回 [param item] 的合成绘制层级，供姿势内排序和整轮廓定位。
func _depth_of(item: CanvasItem) -> int:
	var depth: int = item.z_index # 相对层级按父链累加。
	var cursor: Node = item # 每层均检查是否使用相对Z。
	while cursor is CanvasItem and cursor.z_as_relative:
		cursor = cursor.get_parent()
		if cursor is CanvasItem:
			depth += cursor.z_index
	return depth

## [param delta] 是受暂停控制的秒数；先白化后瓦解，二者平滑重叠。
func _process(delta: float) -> void:
	_age += delta
	if _age >= DURATION:
		queue_free()
		return
	_ink.set_shader_parameter(&"whitening", RepeaterVisualPalette.smooth(_age / 0.22))
	_ink.set_shader_parameter(&"dissolve", RepeaterVisualPalette.smooth((_age - 0.18) / 0.67))
	global_position = _anchor + Vector2(0.0, -7.0) * RepeaterVisualPalette.smooth((_age - 0.24) / 0.66)
	queue_redraw()
	_dust.queue_redraw()

## 绘制采样时的原画分件；伤害或动画变化不会改写副本。
func _draw() -> void:
	for part: Part in _parts: # 原来的遮挡顺序与材质渐变保持一致。
		draw_set_transform_matrix(part.pose)
		draw_texture_rect_region(part.texture, part.rect, part.region, part.color)
	draw_set_transform(Vector2.ZERO)

## 瓦解中后段散出很细的白星，速度以三次曲线衰减。
func _draw_dust() -> void:
	var t: float = clampf((_age - 0.20) / 0.70, 0.0, 1.0) # 星尘晚于轮廓白化出现。
	var fade: float = sin(t * PI) * (1.0 - t) # 中段亮起后无硬切地退出。
	for index: int in range(22): # 固定数量、解析运动，不创建单粒子节点。
		var phase: float = float(index) * 2.399963 # 黄金角分布避开整齐喷射。
		var point: Vector2 = _bounds.get_center() + Vector2(cos(phase), sin(phase)) * _bounds.size * 0.42 # 从轮廓附近起飞。
		point += Vector2(cos(phase) * 20.0, -24.0 - float(index % 5) * 3.0) * RepeaterVisualPalette.out_cubic(t)
		_dust.draw_texture_rect(RepeaterVisualPalette.STAR_TEXTURE, Rect2(point - Vector2.ONE * 2.0, Vector2.ONE * 4.0), false, Color(0.80, 0.87, 1.0, fade * 0.8))
