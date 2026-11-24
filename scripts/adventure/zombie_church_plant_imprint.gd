## 定格的一层植物 Alpha。只在棋盘世界画布绘制，随格子移动。
extends Node2D

## 原精灵的帧区、镜像和局部矩形。
const Part = preload("res://scripts/battle/environment/battle_silhouette_part.gd")
## 照满后瓦解的实时时长，单位秒。
const DISPERSE_SECONDS := 0.46

## 冻结的部件，绘制阶段只保留纹理和变换。
var _parts: Array[Part] = []
## 植物没有可绘制帧时仍留在原脚点的焦痕半径。
var _fallback_radius: float

## 在 [param cell] 的本地空间定格 [param plant] 死前的表现帧。
## [param soot_material] 是所有残影共用的材质，每个残影单独设置瓦解进度。
func capture(plant: Plant000Base, cell: PlantCell, soot_material: ShaderMaterial) -> void:
	var to_cell: Transform2D = cell.get_global_transform().affine_inverse() # 挂在格上，脱离植物及原有碰撞器。
	position = to_cell * plant.shadow.global_position
	z_index = -1
	material = soot_material
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_fallback_radius = minf(cell.size.x, cell.size.y) * 0.17
	var body: Node2D = plant.body # 只沿角色真实表现树取帧，不复制动画脚本和效果节点。
	var sprites: Array[Node] = body.find_children("*", "Sprite2D", true, false) # 包含相接的动画部件。
	sprites.append_array(body.find_children("*", "AnimatedSprite2D", true, false))
	for sprite: Node2D in sprites: # 死前已经隐藏的层不进入剪影。
		if sprite.is_visible_in_tree():
			_capture_part(sprite, body, to_cell)
	if _parts.is_empty():
		for sprite: Node2D in sprites: # 若死亡动作提前隐藏身体，仍保留其内部可见的原帧。
			_capture_part(sprite, body, to_cell)

## 读取 [param sprite] 和 [param body] 间仍可见的层，借 [param to_cell] 冻结坐标。
func _capture_part(sprite: Node2D, body: Node2D, to_cell: Transform2D) -> void:
	var layer: Node = sprite # 身体整体的退场透明度不擦掉这次定格。
	var alpha: float = sprite.self_modulate.a # 自身透明度只影响本精灵。
	while layer != null and layer != body:
		if layer is CanvasItem:
			if not layer.visible:
				return
			alpha *= layer.modulate.a
		layer = layer.get_parent()
	if alpha <= 0.025:
		return
	var part := Part.new(sprite) # 独立持有当前纹理的 Alpha 帧。
	if part.read_frame():
		part.pose = to_cell * sprite.global_transform
		part.pose.origin -= position
		part.opacity = alpha
		part.sprite = null
		_parts.append(part)

## 入树后把当前脚点提交给跨精灵连续的石砖纹理。
func _ready() -> void:
	set_instance_shader_parameter(&"ash_origin", global_position)
	self_modulate.a = 0.64
	create_tween().set_ignore_time_scale(true).tween_property(self, ^"self_modulate:a", 1.0, 0.15)

## [param fraction] 为连续照明进度。裂痕只在即将清除时显露。
func set_light_wear(fraction: float) -> void:
	set_instance_shader_parameter(&"light_wear", fraction)

## 禁种结束后的短促破散，只更新共享材质的实例参数。
func disperse() -> void:
	var tween: Tween = create_tween().set_ignore_time_scale(true) # 暂停时保留当前碎裂姿态。
	tween.tween_method(_set_disperse, 0.0, 1.0, DISPERSE_SECONDS)
	tween.tween_callback(queue_free)

## [param progress] 控制当前瓦解比例，从原位剪影收尽碎片。
func _set_disperse(progress: float) -> void:
	set_instance_shader_parameter(&"disperse", progress)

## 一个纯绘制节点使用冻结矩阵合成各个 Alpha 部件。
func _draw() -> void:
	if _parts.is_empty():
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.42))
		draw_circle(Vector2.ZERO, _fallback_radius, Color.WHITE, true, -1.0, true)
		return
	for part: Part in _parts: # 所有部件沿用其死前的位置与形状。
		draw_set_transform_matrix(part.pose)
		draw_texture_rect_region(part.texture, part.rect, part.source, Color(1.0, 1.0, 1.0, part.opacity))
