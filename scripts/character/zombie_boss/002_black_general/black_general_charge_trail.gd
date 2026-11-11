## 绘制采样时的黑将军姿势，供淡出拖尾和常驻剪影复用。
extends Node2D
class_name BlackGeneralChargeTrail

## 两帧残影之间的冲锋时间，单位秒。
const INTERVAL: float = 0.11
## 单帧残影淡出的战斗时间，单位秒。
const LIFETIME: float = 1.10

## 按原绘制顺序保存的纹理、矩形和相对于采样原点的变换。
var _parts: Array[Part] = []

## 残影部件的绘制数据，源角色继续播放动画时不受影响。
class Part:
	## 此部件当前帧使用的纹理。
	var texture: Texture2D
	## 部件相对于原精灵的绘制范围。
	var rect: Rect2
	## 采样时相对于原点的变换。
	var pose: Transform2D

## 从 [param source] 采样一帧，挂到 [param host] 以便随 Boss 清理。
## [param depth] 为绝对绘制层级，[param opacity] 为初始透明度，[param lifetime] 为淡出秒数。
static func spawn(source: Node2D, host: Node2D, depth: int, opacity: float, lifetime: float = LIFETIME) -> void:
	var trail := BlackGeneralChargeTrail.new() # 此次采样独立于后续移动。
	trail.capture(source, source.global_position)
	trail.top_level = true
	trail.z_as_relative = false
	trail.z_index = depth
	trail.modulate = Color(0.075, 0.06, 0.085, opacity)
	host.add_child(trail)
	trail.global_position = source.global_position
	var fade := trail.create_tween() # 先保留清楚的形状，再逐渐消散。
	fade.tween_property(trail, "modulate:a", 0.0, lifetime).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	fade.tween_callback(trail.queue_free)

## 采集 [param source] 的姿势并以世界坐标 [param anchor] 为原点，可交给拖尾或常驻剪影绘制。
func capture(source: Node2D, anchor: Vector2) -> void:
	_parts.clear()
	for sprite: Sprite2D in source.find_children("*", "Sprite2D", true, false): # 黑将军可见的角色部件。
		if not sprite.is_visible_in_tree() or sprite.texture == null:
			continue
		var part := Part.new() # 仅保存绘制数据，避免复制角色和动画树。
		part.texture = sprite.texture
		part.rect = sprite.get_rect()
		part.pose = sprite.global_transform
		part.pose.origin -= anchor
		_parts.append(part)
	queue_redraw()

## 按采样姿势绘制，使用当前节点的色调和透明度。
func _draw() -> void:
	for part: Part in _parts: # 逐部件恢复当时的位置和旋转。
		draw_set_transform_matrix(part.pose)
		draw_texture_rect(part.texture, part.rect, false)
