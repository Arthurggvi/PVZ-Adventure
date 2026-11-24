## 坠落精灵只推进外观，同一个动作时钟同步全帧轨迹和重采样画面。
extends AnimatedSprite2D

## 击落后前 0.1 秒在原姿态与坠落帧之间过渡，单位为动作秒。
const ENTRY_BLEND_SECONDS: float = 0.10
## 轨迹和 SpriteFrames 的时长权重均以原素材的 60Hz 帧为单位。
const SOURCE_FPS: float = 60.0
## 把 768 像素母版坐标换算到 256 像素精灵局部空间。
const SOURCE_TO_SPRITE: float = 256.0 / 768.0
## 原始第 0–89 帧相对出事点的绝对偏移，单位为母版像素。
const ROOT_MOTION: Array[Vector2] = [
	Vector2(0.0, 0.0), Vector2(-1.008, -0.819), Vector2(-1.603, -1.769),
	Vector2(-1.895, -2.836), Vector2(-1.991, -4.004), Vector2(-1.972, -5.262),
	Vector2(-1.07, -6.737), Vector2(0.818, -8.417), Vector2(3.305, -10.202),
	Vector2(6.01, -11.99), Vector2(8.547, -13.682), Vector2(10.805, -15.385),
	Vector2(13.154, -17.329), Vector2(15.578, -19.24), Vector2(18.045, -20.833),
	Vector2(20.522, -21.819), Vector2(22.989, -21.982), Vector2(25.509, -21.795),
	Vector2(28.059, -21.429), Vector2(30.588, -20.913), Vector2(33.047, -20.279),
	Vector2(35.431, -19.35), Vector2(37.856, -17.404), Vector2(40.251, -14.636),
	Vector2(42.521, -11.338), Vector2(44.575, -7.803), Vector2(46.326, -4.31),
	Vector2(47.916, -0.658), Vector2(49.403, 3.353), Vector2(50.748, 7.758),
	Vector2(51.908, 12.59), Vector2(52.844, 17.883), Vector2(53.604, 23.746),
	Vector2(54.345, 30.322), Vector2(55.045, 37.566), Vector2(55.677, 45.425),
	Vector2(56.216, 53.849), Vector2(56.634, 62.787), Vector2(56.904, 72.187),
	Vector2(57.0, 82.0), Vector2(56.928, 92.445), Vector2(56.723, 103.74),
	Vector2(56.403, 115.831), Vector2(55.984, 128.662), Vector2(55.483, 142.178),
	Vector2(54.917, 156.326), Vector2(54.304, 171.048), Vector2(53.659, 186.291),
	Vector2(53.0, 202.0), Vector2(52.247, 218.346), Vector2(51.32, 235.515),
	Vector2(50.234, 253.473), Vector2(49.007, 272.186), Vector2(47.653, 291.62),
	Vector2(46.189, 311.741), Vector2(44.631, 332.515), Vector2(42.996, 353.909),
	Vector2(41.299, 375.888), Vector2(39.557, 398.419), Vector2(37.785, 421.468),
	Vector2(36.0, 445.0), Vector2(34.149, 469.298), Vector2(32.173, 494.625),
	Vector2(30.078, 520.913), Vector2(27.872, 548.098), Vector2(25.56, 576.115),
	Vector2(23.151, 604.897), Vector2(20.649, 634.379), Vector2(18.062, 664.496),
	Vector2(15.398, 695.182), Vector2(12.661, 726.372), Vector2(9.86, 758.0),
	Vector2(7.0, 790.0), Vector2(4.037, 822.519), Vector2(0.928, 855.748),
	Vector2(-2.317, 889.692), Vector2(-5.688, 924.354), Vector2(-9.175, 959.739),
	Vector2(-12.769, 995.851), Vector2(-16.459, 1032.693), Vector2(-20.234, 1070.269),
	Vector2(-24.086, 1108.584), Vector2(-28.005, 1147.642), Vector2(-31.979, 1187.446),
	Vector2(-36.0, 1228.0), Vector2(-40.139, 1269.867), Vector2(-44.456, 1313.445),
	Vector2(-48.926, 1358.49), Vector2(-53.524, 1404.759), Vector2(-58.224, 1452.01),
]

## 首帧姿态在战斗行坐标系中的变换，包含继承的缩放和镜像。
var _start_pose: Transform2D
## 已经过的原始帧数，含小数；暂停时由战斗行保持进度。
var _ticks: float = 0.0
## 当前显示帧结束于哪个原始帧边界。
var _frame_end: float

## 击落瞬间的单张图集帧，与坠落精灵共用世界姿态。
var _entry_pose: Sprite2D
## 坠落精灵原有的不透明度，入场混合结束后恢复。
var _entry_alpha: float


## 从 [param live] 取出击落前最后一帧，沿相同锚点和方向短暂保留其外观。
## 在入树前执行，坠落节点第一次绘制时就已经完成交接。
func capture_entry_pose(live: AnimatedSprite2D) -> void:
	var texture: Texture2D = live.sprite_frames.get_frame_texture(live.animation, live.frame) # 直接引用原有图集帧。
	if texture == null:
		return

	_entry_pose = Sprite2D.new()
	_entry_pose.texture = texture
	_entry_pose.centered = live.centered
	_entry_pose.offset = live.offset
	_entry_pose.flip_h = live.flip_h
	_entry_pose.flip_v = live.flip_v
	_entry_pose.self_modulate = self_modulate
	_entry_alpha = self_modulate.a
	self_modulate.a = 0.0
	add_child(_entry_pose)


## 记录起点并以首帧开始。独立节点没有受击组件，也不再受原角色控制影响。
func _ready() -> void:
	_start_pose = transform
	_frame_end = sprite_frames.get_frame_duration(animation, 0)


## [param delta] 为未暂停的场景秒数；结束末帧后与画面一起释放。
func _process(delta: float) -> void:
	_ticks += delta * SOURCE_FPS
	_blend_entry_pose()
	if _ticks >= ROOT_MOTION.size():
		queue_free()
		return

	while _ticks >= _frame_end:
		frame += 1
		_frame_end += sprite_frames.get_frame_duration(animation, frame)

	var index: int = floori(_ticks) # 当前所处的母版时间步。
	var next: int = mini(index + 1, ROOT_MOTION.size() - 1) # 最后一个时间步保持末点。
	var offset: Vector2 = ROOT_MOTION[index].lerp(ROOT_MOTION[next], _ticks - index) # 线性采样绝对偏移。
	# 在末帧保持的一个时间步内沿用最后一个区间的下坠速度。
	if index == next:
		offset += (ROOT_MOTION[index] - ROOT_MOTION[index - 1]) * (_ticks - index)
	position = _start_pose * (offset * SOURCE_TO_SPRITE)


## 与坠落轨迹共用场景时钟，混合结束即释放原姿态。
func _blend_entry_pose() -> void:
	if _entry_pose == null:
		return
	var weight: float = smoothstep(0.0, ENTRY_BLEND_SECONDS, _ticks / SOURCE_FPS) # 坠落帧的显示权重。
	self_modulate.a = _entry_alpha * weight
	_entry_pose.modulate.a = 1.0 - weight
	if weight >= 1.0:
		_entry_pose.queue_free()
		_entry_pose = null
