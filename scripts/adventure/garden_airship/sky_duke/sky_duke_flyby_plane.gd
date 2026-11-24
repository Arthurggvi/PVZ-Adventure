## 一架纯视觉战斗机的可重用航迹、机身锚点和脱离尾流。
extends RefCounted

## Zombie034Fighter 的独立飞行原画，未生成实际敌机时也只驻留一帧。
const BODY_PATH := "res://assets/adventure/zombies/fighter/idle.png"
## 与战斗机场景中 Rotor 使用同一原图。
const ROTOR_PATH := "res://assets/reanim/Zombie_balloon_propeller.png"
## 与 SpriteFrames 第一格 A_00 相同的画幅，去掉左侧 224 个透明像素。
const BODY_UV := Rect2(224.0, 0.0, 295.0, 312.0)
## 与 SourceSprite 的原始偏移一致，再将 Y 轴移至机身中心。
const BODY_RECT := Rect2(-151.5, -156.0, 295.0, 312.0)
## 原 Rotor 的中心，已移到与 BODY_RECT 一致的局部坐标。
const ROTOR_CENTER := Vector2(-155.0, 88.0)
## 旋翼原始像素矩形，以原锚点为中心。
const ROTOR_RECT := Rect2(-14.0, -6.5, 28.0, 13.0)
## 机尾上沿突出的喷口位置，随俯仰和透视缩放。
const EXHAUST := Vector2(136.0, 16.0)
## 各虚拟纵深的平均归一化高度。交错使用视野的两侧边缘和内侧航线。
const LANE_Y: Array[float] = [0.20, 0.88, 0.45, 0.99, 0.08]
## 每架仅记录固定数量的世界烟迹点，兼容档进一步降低采样。
const MAX_TRAIL_POINTS: int = 12

## 当前槽已排期或仍有尾流在衰减时为真。
var active: bool = false
## 从远侧到最近层的归一化虚拟纵深。
var depth: float
## 飞越全程秒数。入视口以前和离开以后还有很短的轨道余量。
var duration: float
## 当前进度，入场前小于零，离场后大于一。
var progress: float
## 飞机在逻辑视口中的当前投影，机体及声音共用。
var pose := Transform2D.IDENTITY
## 每一架仅在经过视野中心时登记一次风压。
var did_pass: bool
## 移动音频的当次唯一租约，释放后也不能重播短音。
var voice_key: int
## 同一飞机的短淡出由共享音频池负责。
var leased: bool
## 当次飞机的不变音调差异。
var voice_pitch: float
## 不同外围飞机的转声素材起点，单位秒。
var voice_offset: float

## 固定航线编号，决定绘制顺序和常用纵向位置。
var _lane: int
## 最早允许进入画面的绝对战斗秒。
var _entry: float
## 相对入场的时间，尾流离开后继续推进。
var _age: float
## 当次名义机体高度占视口短边的比例。
var _height_ratio: float
## 航迹中心的归一化视口高度。
var _track_y: float
## 从右到左整段航迹的归一化升降。
var _slope: float
## 接近镜头时从水平姿态滚转的幅度，单位为弧度。
var _bank: float
## 原画在当前深度和模式下的峰值可见度。
var _opacity: float
## 尾流点从脱离至消失的战斗秒数。
var _life: float
## 兼容模式使用较短的烟迹点前缀。
var _point_limit: int
## 已记录的喷口位置数。下次使用只重置计数。
var _written: int
## 出生点扣除当时的累积风位移，用世界像素保存。
var _wake_world := PackedVector2Array()
## 每架重用的逻辑视口烟迹和逐点色调缓冲。
var _wake_points := PackedVector2Array()
## 对应采样点的凝结透明度，近中段比散开的旧尾迹更亮。
var _wake_colors := PackedColorArray()


## 创建 [param lane] 对应的固定航线，并保留独立的尾流采样空间。
func _init(lane: int) -> void:
	_lane = lane
	depth = float(lane) / float(LANE_Y.size() - 1)
	_wake_world.resize(MAX_TRAIL_POINTS)


## 以 [param entry] 和单次 [param voice] 租用该槽。[param rng] 只服务当次演出，[param reduced] 降低遮挡和采样量。
func begin(entry: float, voice: int, rng: RandomNumberGenerator, reduced: bool) -> void:
	_entry = entry
	voice_key = voice
	voice_pitch = rng.randf_range(0.968, 1.035)
	voice_offset = rng.randf_range(0.20, 3.60)
	_track_y = LANE_Y[_lane] + rng.randf_range(-0.032, 0.032)
	var side: float = -1.0 if _lane % 2 == 0 else 1.0 # 两侧交错滚转，避免同向平移队列。
	_slope = side * rng.randf_range(0.10, 0.18)
	_bank = -side * rng.randf_range(0.11, 0.23)
	_height_ratio = lerpf(0.49, 0.96, depth) * rng.randf_range(0.93, 1.07) * (0.86 if reduced else 1.0)
	duration = lerpf(0.35, 0.252, depth) * rng.randf_range(0.94, 1.06)
	_opacity = lerpf(0.93, 0.79, depth) * (0.88 if reduced else 1.0)
	_life = lerpf(0.42, 0.62, depth)
	_point_limit = 8 if reduced else MAX_TRAIL_POINTS
	_written = 0
	_age = -1.0
	progress = -1.0
	did_pass = false
	leased = false
	active = true


## 在 [param view] 采样 [param seconds]，登记跨过的尾流出生时刻。
## [param world_from_view] 转回真实战斗世界，[param travel] 是当前累计世界风位移。
func sample_frame(seconds: float, view: Rect2, world_from_view: Transform2D, travel: Vector2) -> void:
	_age = seconds - _entry
	progress = _age / duration
	if _age < 0.0 or finished():
		return
	if crossing():
		pose = screen_pose(progress, view)
	while _written < _point_limit:
		var sample_progress: float = float(_written) / float(_point_limit - 1) # 解析补算已跨过的固定样本。
		if sample_progress > progress:
			break
		_wake_world[_written] = world_from_view * (screen_pose(sample_progress, view) * EXHAUST) - travel
		_written += 1


## 返回 [param t] 对应的逻辑视口姿态。[param view] 的比例同时决定整个轨道的进出场余量。
func screen_pose(t: float, view: Rect2) -> Transform2D:
	var height: float = _height_ratio * minf(view.size.x, view.size.y) # 以画幅短边确定真正机体高度。
	var margin: float = height * 0.75 # 最大滚转和旋翼仍完全在边缘之外起落。
	var distance: float = view.size.x + 2.0 * margin # 包含画面两端余量的总距离。
	var travel: float = t - 0.13 * sin(TAU * t) / TAU # 镜前中心比两端更快。
	var rise: float = _track_y + _slope * (travel - 0.5) + 0.022 * sin(PI * travel) # 各机按各自的俯仰弧轨擦过视野。
	var center: Vector2 = view.position + Vector2(view.size.x + margin - travel * distance, rise * view.size.y) # 右进左出。
	var scale_factor: float = height / BODY_RECT.size.y * (0.82 + 0.20 * sin(PI * t)) # 最近处的轻微透视放大。
	var bank: float = -atan2(_slope * view.size.y, distance) + _bank * sin(PI * t) # 机头朝左，倾斜随航迹和滚转一起变化。
	return Transform2D(bank, Vector2.ONE * scale_factor, 0.0, center)


## 返回机体是否处于整段横越窗口。
func crossing() -> bool:
	return progress >= 0.0 and progress < 1.0


## 返回机体和最后一段尾流是否都已走完各自的时间窗。
func finished() -> bool:
	return _age >= duration + _life


## 返回飞越对现有船体风场的归一化强度。
func pass_strength() -> float:
	return lerpf(0.31, 0.84, depth) * _opacity


## 将单帧机体 [param body] 与原旋翼 [param rotor] 按 [param from_view] 提交给前景 [param item]。
func draw_plane(item: CanvasItem, from_view: Transform2D, body: Texture2D, rotor: Texture2D) -> void:
	var cover: float = _opacity * smoothstep(0.0, 0.12, progress) * (1.0 - smoothstep(0.88, 1.0, progress)) # 两端柔和衰减。
	var ink := Color(0.91 - 0.28 * depth, 0.95 - 0.21 * depth, 0.98 - 0.13 * depth, cover) # 最近层保有原机身标记和逆光轮廓。
	var body_to_item: Transform2D = from_view * pose # 机身和两片旋翼使用同一飞行姿态。
	item.draw_set_transform_matrix(body_to_item)
	item.draw_texture_rect_region(body, BODY_RECT, BODY_UV, ink)
	if rotor != null:
		var spin: float = _age * 46.0 + voice_offset # 与原机一样独立自转。
		item.draw_set_transform_matrix(body_to_item * Transform2D(spin, Vector2(1.65, 1.75), 0.0, ROTOR_CENTER))
		item.draw_texture_rect(rotor, ROTOR_RECT, false, Color(ink, cover * 0.80))
		item.draw_set_transform_matrix(body_to_item * Transform2D(-spin * 1.37, Vector2(1.85, 1.95), 0.0, ROTOR_CENTER))
		item.draw_texture_rect(rotor, ROTOR_RECT, false, Color(ink, cover * 0.23))


## 用 [param body] 的原剪影在世界画笔 [param item] 画一道压缩掠影。[param from_view] 和 [param view] 来自正式战斗视口。
func draw_shadow(item: CanvasItem, from_view: Transform2D, body: Texture2D, view: Rect2) -> void:
	var center: Vector2 = Vector2(pose.origin.x + view.size.x * 0.035, view.position.y + view.size.y * lerpf(0.41, 0.63, depth)) # 同步越过较低的战斗区域。
	var size: float = pose.x.length() # 按实际机体透视缩放，纵向压扁并沿速度方向倾斜。
	var silhouette := Transform2D(Vector2(1.28, 0.015) * size, Vector2(0.27, 0.12) * size, center) # 只取形状，不复制明处机身。
	var opacity: float = sin(PI * progress) * _opacity * 0.17 # 只经过一次，保留底下实体和平台细节。
	item.draw_set_transform_matrix(from_view * silhouette)
	item.draw_texture_rect_region(body, BODY_RECT, BODY_UV, Color(0.09, 0.12, 0.17, opacity))


## 将真实世界中漂移的水汽按 [param view_from_world] 投到视口，再用 [param from_view] 写到前景 [param item]。
## [param travel] 是本组自启动以来累计的世界风位移，已经脱离的粒子保持各自的出生位置。
func draw_trail(item: CanvasItem, from_view: Transform2D, view_from_world: Transform2D, travel: Vector2) -> void:
	if _written == 0:
		return
	var step: float = duration / float(_point_limit - 1) # 固定出生间隔。
	var first: int = clampi(ceili((_age - _life) / step), 0, _written) # 已消散的前缀无需绘制。
	var tip: bool = crossing() and _age - (_written - 1) * step > 0.001 # 当前喷口接续最近的已记录点。
	var count: int = _written - first + int(tip) # 末端活跃时可多一个喷口点。
	if count < 2:
		return
	_wake_points.resize(count)
	_wake_colors.resize(count)
	for index: int in range(first, _written): # 旧烟在风中继续脱离、摆动和冷却。
		var age_ratio: float = clampf((_age - index * step) / _life, 0.0, 1.0) # 0 在喷口，1 已消散。
		var scatter: Vector2 = Vector2(33.0, 21.0 * sin(voice_offset + index * 1.4 + 2.0 * age_ratio)) * age_ratio * age_ratio # 少量程序化扩散。
		_wake_points[index - first] = view_from_world * (_wake_world[index] + travel + scatter)
		_wake_colors[index - first] = Color(0.82, 0.92, 1.0, 0.56 * pow(1.0 - age_ratio, 1.7) * _opacity)
	if tip:
		_wake_points[count - 1] = pose * EXHAUST
		_wake_colors[count - 1] = Color(0.90, 0.96, 1.0, 0.46 * _opacity)
	item.draw_set_transform_matrix(from_view)
	item.draw_polyline_colors(_wake_points, _wake_colors, 2.4 + 2.1 * depth, true)
