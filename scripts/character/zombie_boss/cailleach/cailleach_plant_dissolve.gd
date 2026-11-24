## 一次「安息吧」把所有受害植株的当前轮廓留在雪里，逻辑死亡与残像无关。
extends Node2D

## 复用棋盘投影读取精灵原帧的接口。
const Part = preload("res://scripts/battle/environment/battle_silhouette_part.gd")
## 一次技能的残像材质，和满层悲寒使用同一色温。
const FROST: Shader = preload("res://shaders/adventure/wonderland/cailleach_grief.gdshader")
## 轮廓随风走散的战斗秒数。
const DURATION: float = 0.51

## 所有原株死亡前复制的纹理片段和当地姿态。
var _parts: Array[Part] = []
## 从消散开始的战斗秒数。
var _elapsed: float = 0.0
## 共享同一阵雪的透明度和风纹。
var _frost_material: ShaderMaterial

## [param plant] 仍占据原格时采样实际绘制帧。残像不持有原株或受击框。
func capture(plant: Plant000Base) -> void:
	var into_scene: Transform2D = global_transform.affine_inverse() # 残像保留死亡当刻的世界位置。
	var sprites: Array[Node] = plant.body.find_children("*", "Sprite2D", true, false) # 原生及骨骼植株的静态部件。
	sprites.append_array(plant.body.find_children("*", "AnimatedSprite2D", true, false))
	for sprite: Node2D in sprites: # 只留当前可见的帧，移除原对象后仍可绘制。
		if not sprite.is_visible_in_tree():
			continue
		var part := Part.new(sprite) # 存帧区、镜像和纹理，不重复生成图块。
		if part.read_frame():
			part.pose = into_scene * sprite.global_transform
			part.opacity = sprite.self_modulate.a * sprite.modulate.a
			part.sprite = null
			_parts.append(part)
	queue_redraw()

## 同一次处决只创建一个表现节点。
func _ready() -> void:
	z_as_relative = false
	z_index = 3999
	_frost_material = ShaderMaterial.new()
	_frost_material.shader = FROST
	_frost_material.set_shader_parameter(&"sorrow", 1.0)
	material = _frost_material

## [param delta] 为战斗秒。未捕获真实精灵时直接释放。
func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= DURATION or _parts.is_empty():
		queue_free()
		return
	_frost_material.set_shader_parameter(&"disperse", _elapsed / DURATION)

## 只画已完成采样的原画，不再查询植物生命周期。
func _draw() -> void:
	for part: Part in _parts: # 各段坐标来自原有的世界姿态。
		draw_set_transform_matrix(part.pose)
		draw_texture_rect_region(part.texture, part.rect, part.source, Color(1.0, 1.0, 1.0, part.opacity))
