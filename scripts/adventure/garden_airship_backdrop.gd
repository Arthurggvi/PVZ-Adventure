## 本关的远方天幕、地表投影和后方云带。各层复用固定精灵和虚拟相机。
extends Node2D

## 由同一局内导演提供当前的环境姿态、镜头与气流事件。
const Atmosphere := preload("res://scripts/adventure/garden_airship/garden_airship_atmosphere.gd")
## 本局的航迹及预测来源，背景没有额外的航速状态。
const Wind := preload("res://scripts/adventure/garden_airship/garden_airship_wind.gd")
## 从虚拟航迹映射到默认投影平面的光流换算。
const FlowSpace := preload("res://scripts/adventure/garden_airship/garden_airship_flow_space.gd")
## 和地表着色器共用的画面中心，单位为战场世界像素。
const VIEW_ORIGIN := Vector2(620.0, 408.0)
## 60° 垂直视场的默认焦距，单位为战场世界像素。
const VIEW_FOCAL_PIXELS: float = 742.31
## 一像素升沉对应的虚拟高度单位，与地表投影一致。
const HEIGHT_PER_HEAVE: float = 3.9
## 纵向虚拟纹理单元比横向稍长，让高空浅角度下的田块保持可辨轮廓。
const GROUND_DEPTH_RATIO: float = 1.6
## 远景散云及贴近地表的薄云的虚拟纵深，和地表虚拟高度同单位。
const FAR_DEPTH: Array[float] = [7900.0, 6900.0, 6530.0, 6120.0]
## 各团远云相对飞艇的航迹比例，保留慢速并错开回绕周期。
const FAR_TRAVEL_RATIOS: Array[float] = [0.62, 0.67, 0.73, 0.78]
## 三片船下云缘的虚拟纵深，较远云更靠近虚拟相机。
const BANK_DEPTH: Array[float] = [2750.0, 2850.0, 2360.0]
## 各片船下云相对飞艇的航迹比例，保留相邻云团的速度差。
const BANK_TRAVEL_RATIOS: Array[float] = [1.18, 1.39, 1.44]
## 巡航云底的虚拟纵深，位于远云与船下云缘之间。
const CEILING_DEPTH: float = 3400.0
## 头顶云的相对航迹比例，使其在巡航时慢于船下云缘。
const CEILING_TRAVEL_RATIO: float = 1.15
## 远云的屏外回绕区，单位为默认投影平面像素，包含最宽机位及姿态余量。
const FAR_LIMITS := Vector2(-840.0, 2750.0)
## 船下云缘在这两个最大轮廓完全离屏的位置回绕。
const BANK_LIMITS := Vector2(-1180.0, 2940.0)
## 巡航云底的纹理更宽，两端预留更大的屏外边界。
const CEILING_LIMITS := Vector2(-1250.0, 3140.0)
## R4 的稳定观察窗口中段，用于选择各片云缘的离场侧。
const GAP_PEAK: float = 0.43
## 在默认投影平面上，云心退到这些 X 坐标后露出战场下方。
const GAP_EDGES := Vector2(-535.0, 1755.0)
## 开口偏移的上限，单位为默认投影平面像素。
const GAP_MAX_OFFSET: float = 1650.0
## 开口偏移每秒最多校正的像素数，留出跟上航速变化的余量。
const GAP_CORRECTION_SPEED: float = 600.0

## 地表贴图一个横向周期的虚拟世界尺寸，与虚拟高度共同决定密度。
@export_range(2100.0, 5200.0, 25.0) var ground_tile_size: float = 3550.0
## 每虚拟航迹单位的地表纹理 X/Z 偏移。负 X 使地面纹理缓缓退向船尾。
@export var ground_travel_ratio := Vector2(-0.16, 0.025)

## XY 是实际头顶云沿光线投到战场的影心，Z 为浓度，W 为水平半宽。
var cloud_shadow := Vector4.ZERO
## 仅地表美术尺寸变动时更新对应着色器常量。
var _terrain_extent := Vector2.ZERO
## 开口事件首帧记录的各片云自然相位，单位为默认投影平面像素。
var _gap_start_x := Vector3.ZERO
## 开口事件首帧的有向虚拟航迹，方便预测跨过回绕点的自然位置。
var _gap_start_travel: float = 0.0
## 按峰值选择的两侧离场位置，带有各片云的回绕圈数。
var _gap_edges := Vector3.ZERO
## 各片云渐变后的偏移量，渲染时还会乘以共用的开口包络。
var _gap_displacement := Vector3.ZERO
## 只有开口事件类型刚切换时才重新选侧。
var _gap_kind: int = Atmosphere.Event.CRUISE
## 上帧环境时钟，用于限速修正开口预测。
var _last_seconds: float = 0.0
## 本帧环境姿态，包含以世界像素表示的升沉。
var _pose := Vector3.ZERO
## 本帧俯角的正弦、余弦及透视焦距，所有云共用。
var _projection := Vector3(0.0, 1.0, VIEW_FOCAL_PIXELS)

## 本关天幕材质独占，退出时与节点一起销毁。
@onready var _sky_material := $Skybox.material as ShaderMaterial
## 飞艇后方的远、中景云与更靠近花田的两团薄云。
@onready var _far_clouds: Array[Sprite2D] = [$FarCloud, $MiddleCloud, $DeepDrift, $DeepBreak]
## 船下近一些的三块断续云体。
@onready var _banks: Array[Sprite2D] = [$BelowPort, $BelowStarboard, $BelowWake]
## 后方云的美术初始位置和缩放，运行时不累积变换。
@onready var _far_layout := _remember_layout(_far_clouds)
## 船下云缘的初始布局，既提供云心也保留不规则轮廓大小。
@onready var _bank_layout := _remember_layout(_banks)
## 巡航云底和经过头顶的独立近云属于同一类纹理。
@onready var _ceiling: Sprite2D = $Ceiling
## 经过的积云是局部战场云影的唯一来源。
@onready var _passing: Sprite2D = $CeilingPass
## 保留美术摆放的巡航云底轮廓比例。
@onready var _ceiling_scale: Vector2 = _ceiling.scale
## 头顶积云比飞艇更宽，透视时以场景初始比例为基准。
@onready var _passing_scale: Vector2 = _passing.scale

## [param seconds] 为环境时钟。[param atmosphere] 提供地表与云共用的姿态和事件。
## [param air_direction] 为船尾方向的横向符号。[param reduced] 精简重叠云体。
## [param wind] 提供累计虚拟航迹和事件峰值前的航迹预测。
func apply_flight(seconds: float, atmosphere: Atmosphere, air_direction: float, reduced: bool, wind: Wind) -> void:
	var step: float = maxf(0.0, seconds - _last_seconds) # 限速修正只使用新增的环境秒数。
	_last_seconds = seconds
	_pose = atmosphere.pose
	var focal: float = 1.0 / tan(deg_to_rad((60.0 + atmosphere.fov_boost) * 0.5)) # 以垂直半画幅为单位。
	_projection = Vector3(sin(_pose.x), cos(_pose.x), 428.57 * focal)
	var travel: float = wind.travel_distance * air_direction # 地表及各云层共用的有向虚拟航迹。
	var extent := Vector2(ground_tile_size, ground_tile_size * GROUND_DEPTH_RATIO) # 地面 X/Z 两轴的虚拟尺寸。
	var phase := Vector2(fposmod(ground_travel_ratio.x * travel, extent.x), # 回绕时采样同一个地面纹理位置。
		fposmod(ground_travel_ratio.y * travel, extent.y)) / extent
	_sky_material.set_shader_parameter(&"view_pose", _pose)
	_sky_material.set_shader_parameter(&"view_focal", focal)
	_sky_material.set_shader_parameter(&"ground_motion", phase)
	if extent != _terrain_extent:
		_terrain_extent = extent
		_sky_material.set_shader_parameter(&"terrain_extent", extent)
	for index: int in _far_clouds.size(): # 远云和薄云沿同一方向在各自深度上漂移。
		var cloud: Sprite2D = _far_clouds[index] # 对应画面中的一团已有云。
		cloud.visible = not reduced or index != 3
		if not cloud.visible:
			continue
		var layout: Vector4 = _far_layout[index] # 初始位置和非等比绘制大小。
		var drift: float = FlowSpace.project_travel(travel * FAR_TRAVEL_RATIOS[index], VIEW_FOCAL_PIXELS, FAR_DEPTH[index]) # 默认平面的光流。
		var x: float = wrapf(layout.x + drift, FAR_LIMITS.x, FAR_LIMITS.y) # 在云完整离屏时回绕。
		_place(cloud, Vector2(x, layout.y), FAR_DEPTH[index], Vector2(layout.z, layout.w))
	_place_banks(step, atmosphere, travel, air_direction, reduced, wind)
	_place_ceiling(travel, atmosphere, reduced)

## [param atmosphere] 指定开口包络。[param travel] 是沿 [param air_direction] 的虚拟航迹。
## [param wind] 预测到事件峰值的额外位移。[param step] 限制每帧校正量，[param reduced] 保留两团主云。
func _place_banks(step: float, atmosphere: Atmosphere, travel: float, air_direction: float, reduced: bool, wind: Wind) -> void:
	var kind: int = atmosphere.event_kind # 介绍云隙和主下降都使用同一云带。
	var opening: bool = kind == Atmosphere.Event.CLOUD_GAP or kind == Atmosphere.Event.DOWNDRAFT # 云缘穿越只用头顶积云。
	var ahead: float = maxf(0.0, GAP_PEAK - atmosphere.phase) * atmosphere.duration_seconds # 峰值前剩余的环境秒数。
	var forecast: float = wind.predict_travel(ahead) * air_direction if opening and ahead > 0.0 else 0.0 # 峰值前的有向虚拟航迹增量。
	if opening and kind != _gap_kind:
		_plan_opening(travel, forecast)
	_gap_kind = kind
	var gap: float = (atmosphere.gap - 0.25 * atmosphere.anticipation) * lerpf(0.63, 1.0, atmosphere.motion_amount) # 先兆短暂收拢云缘，再移开真实云体。
	for index: int in _banks.size(): # 低画质仍保留两块独立近层云缘。
		var cloud: Sprite2D = _banks[index] # 对应一种尺寸和高度的俯视轮廓。
		cloud.visible = not reduced or index < 2
		var layout: Vector4 = _bank_layout[index] # 初始位置及不规则轮廓尺寸。
		var natural: float = layout.x + _bank_travel(index, travel) # 未被开口改变的自然轨道。
		if opening:
			natural = _gap_start_x[index] + _bank_travel(index, travel - _gap_start_travel)
			var desired: float = _opening_offset(index, natural, natural + _bank_travel(index, forecast)) # 同时照顾当前和预测位置。
			_gap_displacement[index] = move_toward(_gap_displacement[index], desired, GAP_CORRECTION_SPEED * step)
		if not cloud.visible:
			continue
		var x: float = wrapf(natural + _gap_displacement[index] * gap, BANK_LIMITS.x, BANK_LIMITS.y) # 关闭后连续回到自然轨道。
		var lift: float = 46.0 + absf(_gap_displacement[index]) * 0.065 # 云缘在开窗时向外侧下方散开。
		if kind == Atmosphere.Event.DOWNDRAFT:
			lift *= 0.31 # 下降时保留近处云边更强的向上光流。
		_place(cloud, Vector2(x, layout.y + lift * gap), BANK_DEPTH[index], Vector2(layout.z, layout.w))

## 保存 [param travel] 时的自然相位，用 [param forecast] 的航迹增量为每团云挑选离场侧。
func _plan_opening(travel: float, forecast: float) -> void:
	_gap_start_travel = travel
	for index: int in _banks.size(): # 同一事件内各片云不因回绕或预测变化重新选侧。
		_gap_start_x[index] = wrapf(_bank_layout[index].x + _bank_travel(index, travel), BANK_LIMITS.x, BANK_LIMITS.y)
		var peak: float = _gap_start_x[index] + _bank_travel(index, forecast) # 保留峰值圈数以避免位移在边界翻转。
		var wrapped: float = wrapf(peak, BANK_LIMITS.x, BANK_LIMITS.y) # 仅用画面内的坐标选出距离较近的一侧。
		var edge: float = GAP_EDGES.x if wrapped < VIEW_ORIGIN.x else GAP_EDGES.y # 在稳定观测段露出船下地表。
		_gap_edges[index] = edge + peak - wrapped
		_gap_displacement[index] = _opening_offset(index, peak, peak)

## 返回第 [param index] 片云将 [param natural] 与 [param peak] 都留在开口外侧所需的有界偏移。
func _opening_offset(index: int, natural: float, peak: float) -> float:
	var edge: float = _gap_edges[index] # 与事件首帧预测同圈的离场位置。
	if wrapf(edge, BANK_LIMITS.x, BANK_LIMITS.y) < VIEW_ORIGIN.x:
		return clampf(edge - maxf(natural, peak), -GAP_MAX_OFFSET, 0.0)
	return clampf(edge - minf(natural, peak), 0.0, GAP_MAX_OFFSET)

## 把第 [param index] 片云的有向虚拟 [param travel] 转成默认投影平面位移。[method _place] 再叠加实际姿态。
func _bank_travel(index: int, travel: float) -> float:
	return FlowSpace.project_travel(travel * BANK_TRAVEL_RATIOS[index], VIEW_FOCAL_PIXELS, BANK_DEPTH[index])

## [param travel] 推进巡航云底。[param atmosphere] 决定经过的积云和投影，[param reduced] 降低局部叠画。
func _place_ceiling(travel: float, atmosphere: Atmosphere, reduced: bool) -> void:
	var concentration: float = atmosphere.cloud_pass # 本次经过可见云缘的真实遮光浓度。
	var drift: float = FlowSpace.project_travel(travel * CEILING_TRAVEL_RATIO, VIEW_FOCAL_PIXELS, CEILING_DEPTH) # 默认平面的光流。
	var x: float = wrapf(914.0 + drift, CEILING_LIMITS.x, CEILING_LIMITS.y) # 巡航云底从上游重新进入。
	_place(_ceiling, Vector2(x, -104.0), CEILING_DEPTH, _ceiling_scale)
	_ceiling.self_modulate.a = (0.68 if reduced else 0.83) * (1.0 - 0.78 * concentration)
	_passing.visible = concentration > 0.002
	cloud_shadow = Vector4.ZERO
	if _passing.visible:
		var moving := Vector2(lerpf(-475.0, 1680.0, atmosphere.phase), -150.0 + 166.0 * concentration) # 积云从上梁后方经过。
		_place(_passing, moving, 2420.0, _passing_scale)
		_passing.self_modulate.a = concentration * (0.78 if reduced else 0.99)
		cloud_shadow = Vector4(_passing.position.x + 112.0, _passing.position.y + 396.0,
			concentration * (0.75 if reduced else 1.0), 578.0) # 影心随同一可见云体沿甲板横移。

## 将 [param cloud] 的已标定默认投影位置 [param origin] 和 [param depth] 恢复为虚拟空间，再投影实际姿态。
## [param rest_scale] 保留原画轮廓，实际大小跟随透视距离变化。
func _place(cloud: Sprite2D, origin: Vector2, depth: float, rest_scale: Vector2) -> void:
	var relative: Vector2 = (origin - VIEW_ORIGIN) * (depth / VIEW_FOCAL_PIXELS) # 从默认平面恢复相机相对 X、负 Y。
	var height: float = -relative.y + _pose.z * HEIGHT_PER_HEAVE # 虚拟世界向上为正，观察点下沉时云体相对变高。
	var view_height: float = height * _projection.y + depth * _projection.x # 和地面射线使用同一俯角基底的逆变换。
	var forward: float = depth * _projection.y - height * _projection.x # 当前相机空间的纵深。
	var magnification: float = _projection.z / maxf(forward, depth * 0.52) # 保护离屏云的最小安全投影距离。
	cloud.position = VIEW_ORIGIN + (Vector2(relative.x, -view_height) * magnification).rotated(-_pose.y)
	cloud.rotation = -_pose.y
	cloud.scale = rest_scale * (magnification * depth / VIEW_FOCAL_PIXELS)

## 把 [param clouds] 的二维初始位置和缩放保存为紧凑数组，供每帧绝对采样。
func _remember_layout(clouds: Array[Sprite2D]) -> PackedVector4Array:
	var layout := PackedVector4Array() # XY 为位置，ZW 为美术缩放。
	for cloud: Sprite2D in clouds: # 只在当前场景就绪时读一次原始位置。
		layout.append(Vector4(cloud.position.x, cloud.position.y, cloud.scale.x, cloud.scale.y))
	return layout
