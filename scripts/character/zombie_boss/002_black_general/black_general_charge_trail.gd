## 固定在世界坐标的黑色冲锋残影，保留采样时的各部件姿势并自动淡出。
extends Node2D
class_name BlackGeneralChargeTrail

## 两帧残影之间的冲锋时间，单位秒。
const INTERVAL: float = 0.09
## 单帧残影淡出的战斗时间，单位秒。
const LIFETIME: float = 0.38

## 一张残影中按原绘制顺序保存的纹理、矩形和世界变换。
var _parts: Array[Part] = []

## 残影部件的绘制数据，源角色继续播放动画时不受影响。
class Part:
	## 此部件当前帧使用的纹理。
	var texture: Texture2D
	## 部件相对于原精灵的绘制范围。
	var rect: Rect2
	## 采样瞬间的世界变换。
	var pose: Transform2D

## 从 [param source] 采样一帧，挂到 [param host] 以便随 Boss 清理。
## [param depth] 为绝对绘制层级，[param opacity] 为淡出前的透明度。
static func spawn(source: Node2D, host: Node2D, depth: int, opacity: float) -> void:
	var trail := BlackGeneralChargeTrail.new() # 此次采样独立于后续移动。
	for sprite: Sprite2D in source.find_children("*", "Sprite2D", true, false): # 黑将军可见的角色部件。
		if not sprite.is_visible_in_tree() or sprite.texture == null:
			continue
		var part := Part.new() # 仅保存绘制数据，避免复制角色和动画树。
		part.texture = sprite.texture
		part.rect = sprite.get_rect()
		part.pose = sprite.global_transform
		trail._parts.append(part)
	trail.top_level = true
	trail.z_as_relative = false
	trail.z_index = depth
	trail.modulate = Color(0.075, 0.06, 0.085, opacity)
	host.add_child(trail)
	trail.global_transform = Transform2D.IDENTITY
	var fade := trail.create_tween() # 绑定到残影节点，卸载时随之销毁。
	fade.tween_property(trail, "modulate:a", 0.0, LIFETIME)
	fade.tween_callback(trail.queue_free)

## 绘制冻结的角色姿势；整体透明度由节点补间驱动。
func _draw() -> void:
	for part: Part in _parts: # 逐部件恢复当时的位置和旋转。
		draw_set_transform_matrix(part.pose)
		draw_texture_rect(part.texture, part.rect, false)
