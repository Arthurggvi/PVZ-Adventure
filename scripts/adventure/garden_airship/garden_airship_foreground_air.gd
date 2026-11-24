## 战斗后方的中近云、船体外缘的空气以及原有事件擦身云。所有图层跟随既有战斗镜头。
extends Node2D

## 场景局内风场提供近云平移和形变强度。
const Wind := preload("res://scripts/adventure/garden_airship/garden_airship_wind.gd")
## 同一虚拟姿态只改变近云本身的位置和画面倾角。
const Atmosphere := preload("res://scripts/adventure/garden_airship/garden_airship_atmosphere.gd")
## 与战斗残骸共用的视口空间换算和虚拟深度投影。
const FlowSpace := preload("res://scripts/adventure/garden_airship/garden_airship_flow_space.gd")
## 两个雾丝批次分别由后景和前景画布绘制。
const AirRibbons := preload("res://scripts/adventure/garden_airship/garden_airship_air_ribbons.gd")
## 中近云焦距，基准巡航投影覆盖约 620 至 960 参考像素/秒。
const CLOUD_FOCAL: float = 1000.0
## 固定的虚拟深度。前三片是既有船底云，后四片按梁后至下层间隙分布。
const CLOUD_DEPTHS: Array[float] = [841.0, 1030.0, 760.0, 1160.0, 1000.0, 865.0, 752.0]
## 纹理及旋转完全离开当前画幅后再换形；该余量单位为画层局部像素。
const REENTRY_MARGIN: float = 22.0
## 近身云在两次主事件分别越过两处船底，始终低于草皮、弹道和区域提示。
const SWEEP_PORT := Vector2(-347.0, 790.0)
## 云缘事件从船底进入画幅，再从另一侧离开。
const SWEEP_STARBOARD := Vector2(455.0, 1630.0)

## 擦身云在当前真实视口上的声像，-1 为左、1 为右。
var sweep_pan: float = 0.0
## 同一云团在当前画幅内的经过强度，供局内声场使用。
var sweep_proximity: float = 0.0

## 四片后层中近云与既有三片底云共享纹理，独立定轨和回收。
@onready var _clouds: Array[Sprite2D] = [$HullCloud, $BehindHull/WakeCloud, $KeelCloud,
	$BehindHull/MidCloudUpper, $BehindHull/MidCloudPort, $BehindHull/MidCloudStarboard, $BehindHull/MidCloudLower]
## 原始质心，船底及棋盘后面各自保持纵向分布。
var _origins := PackedVector2Array()
## 每片现有纹理投影的当前轨道中心，单位为该画层像素。
var _cloud_tracks := PackedVector2Array()
## 各片云当前一轮的伸缩比例。
var _shapes := PackedVector2Array()
## 原画缩放，风场只做少量拉伸与收紧。
var _scales := PackedVector2Array()
## 各片云在场景里设定的基准不透明度与实际进出场用的包围余量。
var _opacity := PackedFloat32Array()
## 预留缩放和旋转后最大云片横向半幅，单位为画层像素。
var _half_widths := PackedFloat32Array()
## 独立于战斗的可复测形态随机序列，仅对不可见的云使用。
var _rng := RandomNumberGenerator.new()
## 上帧共同的虚拟航迹，积分相位不随风速或分辨率重置。
var _last_travel: float = 0.0
## 平台间隙雾丝由 -11 图层承载，实体和船体自然挡住该批绘制。
@onready var _gap_flow: AirRibbons = $BehindHull/GapFlow
## 船体外缘有独立批次，在战场 0 层之上、擦身云与 HUD 之下。
@onready var _hull_flow: AirRibbons = $HullFlow
## 强事件复用一块局部云，不生成额外粒子或全屏透明面。
@onready var _sweep: Sprite2D = $SweepCloud
## 近身云的原画尺寸比，前缘和云尾一起随轨道移动。
@onready var _sweep_scale: Vector2 = _sweep.scale

## 原画一次性初始化七个固定槽。视口内的云保留造型直至完整离场。
func _ready() -> void:
	_rng.seed = 0xA1756
	for cloud: Sprite2D in _clouds: # 预制中的船底与空域云，不再实例化任何 Sprite2D。
		var size: Vector2 = cloud.get_rect().size * cloud.scale # 原画横幅与纵幅，后者也计入倾斜余量。
		_origins.append(cloud.position)
		_cloud_tracks.append(cloud.position)
		_shapes.append(Vector2.ONE)
		_scales.append(cloud.scale)
		_opacity.append(cloud.self_modulate.a)
		_half_widths.append(0.5 * (1.38 * size.x + 0.053 * size.y))

## [param ship_frame] 是局内真实 Sprite2D，用于前景绕流定位。
func setup_hull(ship_frame: Sprite2D) -> void:
	_hull_flow.bind_hull(ship_frame)

## [param wind] 提供共享的航迹与相对气流。[param atmosphere] 提供现有事件形状与姿态。
## [param reduced] 减少重叠云量，保留间隙和船身的高速参照。
func apply_flight(wind: Wind, atmosphere: Atmosphere, reduced: bool) -> void:
	_apply_sweep(atmosphere, reduced)
	var travel: float = maxf(0.0, wind.travel_distance - _last_travel) # 航速连续变化，层内相位只按实际新增路程前进。
	_last_travel = wind.travel_distance
	var amount: float = atmosphere.motion_amount # 沿用原来的减少动效强度，不用它改变基本气流方向。
	_advance_clouds(wind, atmosphere, travel, reduced)
	_gap_flow.apply_flow(wind, travel, atmosphere.pose.z * 0.26,
		lerpf(0.61, 1.0, amount) * (1.0 - 0.24 * sweep_proximity), reduced)
	_hull_flow.apply_flow(wind, travel, 0.0,
		lerpf(0.54, 1.0, amount) * (1.0 - 0.60 * sweep_proximity), reduced)

## 用 [param wind] 的虚拟 [param travel] 推进各层实际速度。[param atmosphere] 只偏移云体。
## [param reduced] 跳过较厚重叠云。云的完整纹理仅在两个画层各自边界外换轨。
func _advance_clouds(wind: Wind, atmosphere: Atmosphere, travel: float, reduced: bool) -> void:
	var screen: Rect2 = get_viewport_rect() # CanvasLayer 跟随同一镜头，仍分别使用各自真实画布。
	var rear: Transform2D = _gap_flow.get_global_transform_with_canvas() # 战场后的局部到视口变换。
	var front: Transform2D = _hull_flow.get_global_transform_with_canvas() # HUD 下前景的局部到视口变换。
	var rear_view: Rect2 = rear.affine_inverse() * screen # 后层的当前可见范围。
	var front_view: Rect2 = front.affine_inverse() * screen # 船底旧前景云的实际可见范围。
	var rear_units: float = FlowSpace.reference_to_world(screen.size.x, rear, Wind.DIRECTION) # 参考 px 转后层坐标。
	var front_units: float = FlowSpace.reference_to_world(screen.size.x, front, Wind.DIRECTION) # 参考 px 转前层坐标。
	var visibility: float = lerpf(0.50, 1.0, atmosphere.motion_amount) * (0.90 if reduced else 1.0) # 保留兼容巡航参照。
	var drift: float = travel * lerpf(0.78, 1.0, atmosphere.motion_amount) * (0.83 + 0.17 * wind.airspeed_ratio) # 同时采样航迹和空气的相对速度。
	for index: int in _clouds.size(): # 七个固定质心，无随帧新增节点或纹理。
		var cloud: Sprite2D = _clouds[index] # 当前船底或棋盘后方的云块。
		if reduced and (index == 1 or index == 4 or index == 6):
			cloud.hide()
			continue
		var under_deck: bool = index < 3 # 只有 R4 船底云保留原有高度限制。
		var behind: bool = not under_deck or index == 1 # WakeCloud 与四片新云处在实体后方。
		var units: float = rear_units if behind else front_units # 参考速度换算为该 Sprite2D 的画层单位。
		var view: Rect2 = rear_view if behind else front_view # 目前能观察到该处云的画层矩形。
		var track: Vector2 = _cloud_tracks[index] # 投影后累计质心，不把当前速度乘绝对秒数。
		track.x += Wind.DIRECTION.x * FlowSpace.project_travel(drift, CLOUD_FOCAL, CLOUD_DEPTHS[index]) * units
		if track.x - _half_widths[index] > view.end.x + REENTRY_MARGIN:
			track.x = view.position.x - _half_widths[index] - REENTRY_MARGIN - _rng.randf_range(0.0, 165.0)
			track.y = _origins[index].y + _rng.randf_range(-12.0, 14.0) * (0.5 if under_deck else 2.2)
			_shapes[index] = Vector2(_rng.randf_range(0.83, 1.13), _rng.randf_range(0.80, 1.16))
			cloud.flip_h = _rng.randf() < 0.5
		_cloud_tracks[index] = track
		var gust: float = wind.gust_at(track.x, 0.045 + index * 0.028) * atmosphere.motion_amount # 云缘取当前位置风压。
		var sway: float = (2.3 if under_deck else 7.5) * sin(wind.seconds * 0.34 + index * 1.9) # 低频竖向细动。
		var y: float = track.y + sway - atmosphere.pose.z * (0.57 if under_deck else 0.34) # R4 姿态只在这一层应用一次。
		if under_deck:
			y = maxf(691.0 if behind else 754.0, y)
		cloud.position = Vector2(track.x, y)
		cloud.rotation = clampf(-atmosphere.pose.y, -0.04, 0.04)
		cloud.scale = _scales[index] * _shapes[index] * Vector2(1.0 + 0.21 * gust, 1.0 - 0.08 * gust)
		cloud.self_modulate.a = _opacity[index] * (0.96 + 0.24 * gust) * visibility * (1.0 - 0.52 * sweep_proximity)
		cloud.visible = view.intersects(cloud.transform * cloud.get_rect())

## [param atmosphere] 决定云的经过阶段。[param reduced] 下保留单块擦身云，降低局部不透明度和音量。
func _apply_sweep(atmosphere: Atmosphere, reduced: bool) -> void:
	var progress: float = atmosphere.sweep_phase # 轨道两端之外不可见，不回绕进场。
	sweep_proximity = 0.0
	sweep_pan = 0.0
	if progress <= 0.0 or progress >= 1.0:
		_sweep.visible = false
		return
	var across_bow: bool = atmosphere.event_kind == Atmosphere.Event.CLOUD_EDGE # 头顶云期间近景改走船底另一侧。
	var track: Vector2 = SWEEP_STARBOARD if across_bow else SWEEP_PORT # 同一风向上的两段局部轨道。
	var x: float = lerpf(track.x, track.y, progress) # 最快的经过段不随战斗倍速加速。
	var lift: float = smoothstep(0.05, 0.47, progress) # 从下缘靠近，再沿下缘淡出。
	var exit_drift: float = smoothstep(0.59, 0.98, progress) # 云团后缘离开船体后向下滑出。
	var y: float = 818.0 - 73.0 * lift + 88.0 * exit_drift - 0.29 * atmosphere.pose.z # 升沉只影响这里的前景位置一次。
	var envelope: float = smoothstep(0.04, 0.35, progress) * (1.0 - smoothstep(0.66, 0.99, progress)) # 无硬切入和硬退场。
	_sweep.position = Vector2(x, maxf(718.0, y))
	_sweep.scale = _sweep_scale * Vector2(0.96 + 0.16 * lift, 0.96 + 0.09 * lift)
	_sweep.rotation = clampf(-atmosphere.pose.y, -0.035, 0.035)
	var view_size: Vector2 = get_viewport_rect().size # 使用当前实际显示范围，包括受支持的窗口比例。
	var screen: Vector2 = _sweep.get_global_transform_with_canvas().origin / view_size # 云心在视口中的归一化位置。
	var framing: float = smoothstep(-0.17, 0.15, screen.x) * (1.0 - smoothstep(0.90, 1.19, screen.x)) # 侧缘之外只留极少远风。
	var lower_edge: float = 1.0 - smoothstep(0.94, 1.16, screen.y) # 越过下缘时声像一起淡出。
	sweep_proximity = envelope * framing * lower_edge * (0.70 if reduced else 1.0)
	sweep_pan = clampf((screen.x * 2.0 - 1.0) * 0.76, -0.69, 0.69)
	_sweep.self_modulate.a = (0.64 if reduced else 0.83) * envelope * atmosphere.motion_amount
	_sweep.visible = _sweep.self_modulate.a > 0.005
