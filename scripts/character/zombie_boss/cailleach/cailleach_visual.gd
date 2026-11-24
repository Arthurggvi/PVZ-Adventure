## 妇人的共享原画播放器。逐帧杖击前后以部位形变衔接待机，触地仍使用原画时序。
extends AnimatedSprite2D
class_name CailleachVisual

## 从零计数第 18 帧为杖尖接触地面；此信号每次动作只发出一次。
signal staff_impact
## 一次杖击完整回收到站姿后发出。
signal staff_finished

## 杖尖触地所对应的原画帧序号，和时间资源共用。
const IMPACT_FRAME: int = 18
## 由当前待机帧过渡到杖击起始姿态的动画秒数。
const WINDUP_BLEND_SECONDS: float = 0.24
## 杖击回到站姿所用的动画秒数。
const RECOVERY_BLEND_SECONDS: float = 0.30
## 披风接近收拢的待机帧，从这里恢复循环以接住收杖。
const IDLE_RECOVERY_FRAME: int = 35
## 对齐骨架和轮廓的局部混合材质，只在衔接可见时绘制。
const POSE_SHADER: Shader = preload("res://shaders/adventure/wonderland/cailleach_pose_blend.gdshader")
## 在原画四周为散开的光晕留边，单位为原画像素。
const POSE_BLOOM_MARGIN := Vector2(30.0, 30.0)
## 待机和杖击的同一部位像素。依次为杖顶、挂饰、握杖手、杖端、头巾、脸、肩、垂手、袍带、前靴。
const BODY_POINTS: Array[Vector4] = [
	Vector4(96, 26, 89, 40), Vector4(121, 76, 113, 86), Vector4(114, 149, 110, 157),
	Vector4(126, 360, 126, 360), Vector4(179, 40, 177, 47), Vector4(148, 85, 149, 92),
	Vector4(229, 83, 228, 89), Vector4(211, 226, 214, 234), Vector4(174, 267, 178, 274),
	Vector4(154, 355, 154, 355),
]
## 每个待机帧中上披风、中披风和袍脚的右缘 X 像素，匹配飞扬及收拢的轮廓。
const IDLE_CLOAK_EDGE: Array[Vector3] = [
	Vector3(314,327,338), Vector3(319,333,339), Vector3(323,338,339), Vector3(327,344,339),
	Vector3(329,349,337), Vector3(341,356,332), Vector3(345,359,329), Vector3(348,360,327),
	Vector3(351,361,322), Vector3(342,362,320), Vector3(336,362,322), Vector3(333,363,324),
	Vector3(332,363,323), Vector3(333,363,323), Vector3(334,334,325), Vector3(340,333,303),
	Vector3(334,331,328), Vector3(333,330,329), Vector3(335,331,330), Vector3(339,360,330),
	Vector3(335,362,334), Vector3(332,361,333), Vector3(330,358,332), Vector3(330,352,335),
	Vector3(328,347,333), Vector3(326,342,334), Vector3(323,336,337), Vector3(320,330,338),
	Vector3(319,330,338), Vector3(317,329,338), Vector3(315,329,338), Vector3(315,328,338),
	Vector3(315,327,338), Vector3(314,326,338), Vector3(314,327,338), Vector3(315,327,338),
]
## 普通播放、混入杖击、混回待机。
enum PoseBlend { NONE, WINDUP, RECOVERY }

## 当前是否处于不可重入的杖击动作。
var _staff_active: bool = false
## 当前动作是否已经投递触地信号。
var _impact_sent: bool = false
## 此刻正在推进的衔接方向。
var _pose_blend: PoseBlend = PoseBlend.NONE
## 衔接经过的动画秒数。
var _blend_age: float = 0.0
## 过渡期间替代原精灵的单一合成平面。
var _blend_plane: ColorRect
## 独立持有当前姿态的材质。
var _blend_material: ShaderMaterial
## 原精灵被合成平面替代时的自身着色。
var _sprite_tint: Color = Color.WHITE
## 十个固定身体锚点与三个活动披风锚点。
var _pose_points := PackedVector4Array(BODY_POINTS)

## 装配共用过渡材质，平时由 AnimatedSprite2D 原样播放逐帧原画。
func _ready() -> void:
	_blend_material = ShaderMaterial.new()
	_blend_material.shader = POSE_SHADER
	_blend_material.set_shader_parameter(&"bloom_margin", POSE_BLOOM_MARGIN)
	_blend_plane = ColorRect.new()
	_blend_plane.position = offset - POSE_BLOOM_MARGIN
	_blend_plane.size = sprite_frames.get_frame_texture(&"idle", 0).get_size() + 2.0 * POSE_BLOOM_MARGIN
	_blend_plane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blend_plane.material = _blend_material
	_blend_plane.hide()
	add_child(_blend_plane)
	_pose_points.resize(13)
	set_process(false)
	frame_changed.connect(_on_frame_changed)
	animation_finished.connect(_on_animation_finished)
	if not is_playing():
		play(&"idle")

## 从正在播放的待机开始混入杖击，整个起手、杖击及回收期间拒绝重入。成功返回 true。
func play_staff_tap() -> bool:
	if _staff_active or not is_node_ready() or not is_inside_tree() or is_queued_for_deletion():
		return false
	if animation != &"idle" or not is_playing():
		cancel_staff_tap()
	_staff_active = true
	_impact_sent = false
	_begin_pose_blend(PoseBlend.WINDUP, frame, 0)
	return true

## [param return_to_idle] 为 true 时重置回待机。死亡或换阶段时可停住当前画面。
func cancel_staff_tap(return_to_idle: bool = true) -> void:
	_staff_active = false
	_impact_sent = false
	_pose_blend = PoseBlend.NONE
	set_process(false)
	if return_to_idle:
		_show_native_sprite()
		play(&"idle")
	else:
		pause()

## [param rate] 同时作用于原画和两端衔接。非法值不改变现状。
func set_action_rate(rate: float) -> void:
	if is_finite(rate) and rate > 0.0:
		speed_scale = rate

## [param direction] 指定进入或回收方向，[param idle_frame] 和 [param staff_frame] 给出两端姿态。
func _begin_pose_blend(direction: PoseBlend, idle_frame: int, staff_frame: int) -> void:
	_pose_blend = direction
	_blend_age = 0.0
	_set_blend_frame(&"staff_tap", staff_frame)
	_set_idle_pose(idle_frame)
	_blend_material.set_shader_parameter(&"amount", 0.0 if direction == PoseBlend.WINDUP else 1.0)
	_sprite_tint = self_modulate
	_blend_plane.color = _sprite_tint
	_blend_plane.show()
	self_modulate.a = 0.0
	set_process(true)

## [param delta] 为游戏秒。插值保持两端缓入缓出，结束帧交还给原生播放。
func _process(delta: float) -> void:
	var winding_up: bool = _pose_blend == PoseBlend.WINDUP # 起手与收杖按相反方向混合。
	var duration: float = WINDUP_BLEND_SECONDS if winding_up else RECOVERY_BLEND_SECONDS # 对应段的动画秒数。
	_blend_age += delta * speed_scale
	var blend: float = smoothstep(0.0, duration, _blend_age) # 两端的速度归零。
	_blend_material.set_shader_parameter(&"amount", blend if winding_up else 1.0 - blend)
	if _blend_age < duration:
		return
	_pose_blend = PoseBlend.NONE
	set_process(false)
	_show_native_sprite()
	if winding_up:
		play(&"staff_tap")
		set_frame_and_progress(0, 0.0)
	else:
		_staff_active = false
		staff_finished.emit()

## 关闭合成层，恢复原画精灵的本地着色。
func _show_native_sprite() -> void:
	if is_instance_valid(_blend_plane) and _blend_plane.visible:
		self_modulate = _sprite_tint
		_blend_plane.hide()

## 将 [param clip] 的 [param frame_index] 绑定到对应图集，保留相邻帧之间的采样边界。
func _set_blend_frame(clip: StringName, frame_index: int) -> void:
	var texture: AtlasTexture = sprite_frames.get_frame_texture(clip, frame_index) as AtlasTexture # 原画裁图。
	var step: Vector2 = Vector2.ONE / texture.atlas.get_size() # 图集每像素的 UV 步长。
	var origin: Vector2 = texture.region.position * step # 当前帧的图集 UV 原点。
	var idle: bool = clip == &"idle" # shader 的两张图集插槽。
	_blend_material.set_shader_parameter(&"idle_sheet" if idle else &"staff_sheet", texture.atlas)
	_blend_material.set_shader_parameter(&"idle_region" if idle else &"staff_region", Vector4(origin.x, origin.y, step.x, step.y))

## [param frame_index] 是当前活跃的待机帧，将飞动的披风与杖击衣缘对齐。
func _set_idle_pose(frame_index: int) -> void:
	_set_blend_frame(&"idle", frame_index)
	var edge: Vector3 = IDLE_CLOAK_EDGE[frame_index] # 对应在上披风、中披风、袍脚的动态位置。
	_pose_points[10] = Vector4(edge.x, 205, 301, 205)
	_pose_points[11] = Vector4(edge.y, 267, 313, 267)
	_pose_points[12] = Vector4(edge.z, 349, 344, 351)
	_blend_material.set_shader_parameter(&"pose_points", _pose_points)

## 混合时待机持续呼吸，触地事件只随原画杖击帧触发一次。
func _on_frame_changed() -> void:
	if _pose_blend != PoseBlend.NONE and animation == &"idle":
		_set_idle_pose(frame)
		return
	if not _staff_active or _impact_sent or animation != &"staff_tap" or frame < IMPACT_FRAME:
		return
	_impact_sent = true
	staff_impact.emit()

## 收杖末帧混回继续播放的待机，完成衔接后才解除重入锁。
func _on_animation_finished() -> void:
	if not _staff_active or animation != &"staff_tap":
		return
	_begin_pose_blend(PoseBlend.RECOVERY, IDLE_RECOVERY_FRAME, frame)
	play(&"idle")
	set_frame_and_progress(IDLE_RECOVERY_FRAME, 0.0)
