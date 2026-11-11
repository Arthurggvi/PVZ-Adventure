## 绘制采样时的黑将军姿势，供淡出拖尾和常驻剪影复用。
extends Node2D
class_name BlackGeneralChargeTrail

## 两帧残影之间的冲锋时间，单位秒。
const INTERVAL: float = 0.16
## 单帧残影淡出的战斗时间，单位秒。
const LIFETIME: float = 1.22
## 为定格姿势及四路分身提供黑色内层、紫灰轮廓和破碎遮罩。
const POSE_SHADER: Shader = preload("res://shaders/black_general_shadow_pose.gdshader")

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
	trail.capture(source, source.global_position, false)
	trail.top_level = true
	trail.z_as_relative = false
	trail.z_index = depth
	trail.modulate.a = opacity
	host.add_child(trail)
	trail.global_position = source.global_position
	trail.material = make_ink(lerpf(0.24, 0.80, opacity), source.global_position.x)
	trail._dissolve(lifetime, Vector2(28.0, -14.0))

## 创建独立的轮廓材质；[param intensity] 控制描边亮度，[param origin_x] 用来错开破碎图案。
static func make_ink(intensity: float, origin_x: float) -> ShaderMaterial:
	var ink := ShaderMaterial.new() # 同一次演出的部件共享进度，不与其他影子同步。
	ink.shader = POSE_SHADER
	ink.set_shader_parameter(&"intensity", intensity)
	ink.set_shader_parameter(&"phase", fposmod(origin_x * 0.11, 29.0))
	return ink

## 将 [param progress] 写到 [param ink] 的破碎遮罩，材质尚未完成首帧绘制时也可设置。
static func set_dissolve(progress: float, ink: ShaderMaterial) -> void:
	ink.set_shader_parameter(&"dissolve", progress)

## [param host] 接管死亡姿势，[param depth] 为绝对层级；原设施释放后，碎裂演出仍能播完。
func shed(host: Node2D, depth: int) -> void:
	var remnant := BlackGeneralChargeTrail.new() # 捕获的数据只读，可由短命的退场节点继续绘制。
	remnant._parts = _parts
	remnant.top_level = true
	remnant.z_as_relative = false
	remnant.z_index = depth
	remnant.material = make_ink(1.42, global_position.x)
	host.add_child(remnant)
	remnant.global_transform = global_transform
	remnant._dissolve(0.72, Vector2(25.0, -52.0))

## 在 [param duration] 秒内一边沿 [param drift] 飘动，一边从断裂边缘瓦解。
func _dissolve(duration: float, drift: Vector2) -> void:
	var decay := create_tween().set_parallel(true) # 让轮廓破碎和烟流位移同步。
	decay.tween_method(set_dissolve.bind(material), 0.0, 1.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	decay.tween_property(self, "position", position + drift, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	decay.tween_property(self, "modulate:a", 0.0, duration * 0.78).set_delay(duration * 0.22)
	decay.chain().tween_callback(queue_free)

## 采集 [param source] 的姿势，以世界坐标 [param anchor] 为原点。
## [param include_cloth] 为 false 时省略大面积的旗布和披风，避免多路轨迹遮住战场。
func capture(source: Node2D, anchor: Vector2, include_cloth: bool = true) -> void:
	_parts.clear()
	for sprite: Sprite2D in source.find_children("*", "Sprite2D", true, false): # 黑将军可见的角色部件。
		if not sprite.is_visible_in_tree() or sprite.texture == null:
			continue
		if not include_cloth and (sprite.name == &"Cape" or sprite.name == &"CapeCollar"
				or String(sprite.name).begins_with("HeldFlag")):
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
