## 将真实战斗画布投影到虚拟听者坐标，并集中设定原生播放器的空间标尺。
extends RefCounted

## 有效视口两侧的横向半宽，单位为虚拟距离。
const HALF_WIDTH: float = 10.0
## 有效视口的垂向半高，与声源额外远近深度分开。
const HALF_HEIGHT: float = 2.4
## 听者位于战场前方的距离；Godot 听者面向 −Z。
const FRONT_DISTANCE: float = 3.2
## 原生距离衰减归零的距离，也用于跳过完全不可听的声源。
const HEARING_RANGE: float = 28.0
## 本工程全局 3D 声像系数为 0.5；用局内播放器校准双声道的边缘宽度。
const PANNING_STRENGTH: float = 1.55
## 较远处的高频最多由原生距离滤波衰减此值，单位 dB。
const FAR_HIGH_SHELF_DB: float = -14.0

## 有效画布原点和尺寸变化时递增，用于重置移动声源的速度估计。
var layout_version: int = 0
## 上次采样对应的过程帧；同帧多次发声共享一份投影。
var _sample_frame: int = -1
## 当前有效视口的逻辑矩形，不包含窗口边框或黑边。
var _visible_rect := Rect2()
## 真实战斗世界到有效视口的变换，采用 Godot 2D 声源同一顺序。
var _to_screen := Transform2D.IDENTITY
## 有效视口内的听者中心，纵向略偏下方。
var _screen_center := Vector2.ZERO
## 从有效视口的逻辑单位到虚拟距离的比例，翻转画布 Y 轴。
var _screen_scale := Vector2.ZERO


## 在实际发声帧采样 [param viewport] 的有效尺寸和战斗 Camera2D 变换。
func sample(viewport: Viewport) -> void:
	var frame := Engine.get_process_frames() # 同帧命中与移动更新复用一次数据读取。
	if frame == _sample_frame:
		return
	_sample_frame = frame
	var visible := viewport.get_visible_rect() # 拉伸后的有效逻辑区域，不使用操作系统窗口尺寸。
	var transform := viewport.get_global_canvas_transform() * viewport.get_canvas_transform() # 真实战斗画布。
	if visible != _visible_rect or not transform.x.is_equal_approx(_to_screen.x) \
			or not transform.y.is_equal_approx(_to_screen.y):
		layout_version += 1
		_visible_rect = visible
		_screen_center = visible.position + visible.size * Vector2(0.5, 0.52)
		_screen_scale = Vector2(2.0 * HALF_WIDTH, -2.0 * HALF_HEIGHT) / visible.size.max(Vector2.ONE)
	_to_screen = transform


## 将 [param world_position] 的可见画布锚点换为虚拟坐标；[param depth] 是增加的虚拟纵深。
func project(world_position: Vector2, depth: float) -> Vector3:
	var offset := (_to_screen * world_position - _screen_center) * _screen_scale # 以视口为准的横纵偏移。
	return Vector3(offset.x, offset.y, -FRONT_DISTANCE - maxf(depth, 0.0))


## 创建池中一个位置声源。只路由到现有 SFX，总线音量和静音由游戏设置控制。
static func make_player() -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new() # 每个槽最多播放一个声部，闲置时没有音频流。
	player.bus = &"SFX"
	player.area_mask = 0
	player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	# 原生有限距离做柔和衰减，近端和战场边缘响度接近。
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	player.max_distance = HEARING_RANGE
	player.panning_strength = PANNING_STRENGTH
	player.attenuation_filter_db = FAR_HIGH_SHELF_DB
	return player


## 返回 [param distance] 对应的原生高频衰减起点，单位 Hz。
static func filter_frequency(distance: float) -> float:
	return lerpf(11500.0, 2250.0, smoothstep(8.0, 24.0, distance))
