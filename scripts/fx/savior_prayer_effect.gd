## Savior 一次施法的世界表现。掌间黑泪随角色，落下的刻印固定在指定格子。
extends Node2D

## 技能可复用聚滴手势，并决定是否由本组件绘制黑泪与地贴。
enum Profile { GROUND_MARKS, PALMS_ONLY }
## 只使用掌间效果时，墨滴散开的战斗秒数。
const PALM_RELEASE_SECONDS := 0.16
## 黑泪从抬掌到着地的战斗秒数。
const FLIGHT_SECONDS := 0.28
## 最晚落点的扩散与消散时间，单位为战斗秒。
const FADE_SECONDS := 0.69
## 复数落点之间最多相隔的战斗秒数。
const MAX_STAGGER := 0.18
## 原画抬掌前的聚滴时间，实际出手由原画帧推进。
const GATHER_SECONDS := 0.70
## 黑蜡本体色，保留原画的紫灰色差。
const INK := Color(0.068, 0.049, 0.083)
## 细窄湿边的颜色，经同一个教堂世界光场合成。
const WET_EDGE := Color(0.67, 0.61, 0.69)
## 主墨滴头部朝局部正 X，尾部逐渐收窄。
const DROP: PackedVector2Array = [
	Vector2(-10.5, 0), Vector2(-5.8, -1.4), Vector2(-1.7, -3.7),
	Vector2(2.8, -4.3), Vector2(6.1, -2.2), Vector2(7.1, 0),
	Vector2(5.9, 2.3), Vector2(2.4, 4.0), Vector2(-1.4, 3.4), Vector2(-5.0, 1.9),
]
## 主墨滴上沿的不完整银灰细边。
const DROP_EDGE: PackedVector2Array = [Vector2(-5, -1.7), Vector2(-1.8, -3.5), Vector2(2.4, -4), Vector2(5.1, -2.5)]

## 角色实际双掌位置，随动作和角色变换更新。
var _palm: Node2D
## 已验证的世界格子，第一个是主滴落点。
var _targets: Array[Rect2] = []
## 起手后经过的动作秒数。
var _age := 0.0
## 聚滴跟随手部动作；已经出手的黑泪和地面特效继续使用战斗时间。
var gather_rate := 1.0
## 放出黑泪后经过的战斗秒数。负值表示还在掌中。
var _flight := -1.0
## 原画释放帧冻结下来的世界坐标。
var _departure: Vector2
## 出手到接触地面这段抛线的控制点。
var _flight_control: Vector2
## 主滴在地面的实际落点。
var _landing: Vector2
## 一次释放中最大的额外落点延迟。
var _last_stagger := 0.0
## 本次施法选择的表现。
var _profile: Profile = Profile.GROUND_MARKS
## 所有格子的共享平面批次。
@onready var _ground: MultiMeshInstance2D = $GroundMarks
## 当前演出的时间参数。场景为每次实例保留独立参数。
@onready var _ground_material := _ground.material as ShaderMaterial

## 入树前保存 [param palm]、有效的 [param target_areas] 及 [param profile]。保留至少一格时返回成功。
func prepare(palm: Node2D, target_areas: Array[Rect2], profile: Profile = Profile.GROUND_MARKS) -> bool:
	_palm = palm
	_profile = profile
	var seen: Dictionary[Rect2, bool] = {} # 上游同一次选择重复给出某格时只绘制一次。
	for area: Rect2 in target_areas: # 原顺序决定主滴落在哪格。
		if area.has_area() and area.position.is_finite() and area.size.is_finite() and not seen.has(area):
			seen[area] = true
			_targets.append(area)
	return not _targets.is_empty()

## 初次进入世界时提交所有刻印的静态几何。
func _ready() -> void:
	if _targets.is_empty() or not is_instance_valid(_palm):
		queue_free()
		return
	global_transform = Transform2D.IDENTITY
	if _profile == Profile.PALMS_ONLY:
		return
	_landing = _ground_center(_targets[0])
	var batch: MultiMesh = _ground.multimesh # 单批着色所有实际影响格子。
	batch.instance_count = _targets.size()
	var extent := Rect2() # 包括屏幕以外但可能回到镜头里的目标。
	for index: int in range(_targets.size()): # 所有实例共用同一个时间与网格。
		var area: Rect2 = _targets[index] # 每格按实际宽高压成透视椭圆。
		var center: Vector2 = _ground_center(area) # 刻印落在格心略靠下的石面。
		var radius: Vector2 = area.size * Vector2(0.54, 0.38) # 留出水痕碎边的局部画幅。
		var delay: float = minf(MAX_STAGGER, center.distance_to(_landing) * 0.00095) # 离主落点更远的余痕稍晚扩开。
		var salt: float = fposmod(center.dot(Vector2(0.013, 0.019)), 1.0) # 固定位置种子，保持细裂痕稳定。
		batch.set_instance_transform_2d(index, Transform2D(0.0, radius, 0.0, center))
		batch.set_instance_custom_data(index, Color(delay, salt, 0.0, 1.0))
		_last_stagger = maxf(_last_stagger, delay)
		var bounds := Rect2(center - radius, radius * 2.0) # 圈与飞散碎边都处于该面片内。
		extent = extent.merge(bounds) if extent.has_area() else bounds
	batch.custom_aabb = AABB(Vector3(extent.position.x, extent.position.y, -1.0), Vector3(extent.size.x, extent.size.y, 2.0))
	_ground_material.set_shader_parameter(&"flight_seconds", FLIGHT_SECONDS)

## 按 [param cell] 的真实尺寸把落点放在格子的近侧。
func _ground_center(cell: Rect2) -> Vector2:
	return cell.get_center() + Vector2(0.0, cell.size.y * 0.14)

## 双掌展开帧调用一次，冻结起点并开始飞行。再次调用返回 false。
func release() -> bool:
	if _flight >= 0.0 or not is_instance_valid(_palm):
		return false
	_flight = 0.0
	if _profile == Profile.PALMS_ONLY:
		return true
	_departure = _palm.global_position
	_flight_control = _departure.lerp(_landing, 0.52) - Vector2(0.0, minf(_departure.distance_to(_landing) * 0.29, 73.0)) # 先扬起再贴向地砖。
	return true

## [param delta] 是随战场暂停和速度变化的演出秒数。
func _process(delta: float) -> void:
	_age += delta * gather_rate if _flight < 0.0 else delta
	if _flight >= 0.0:
		_flight += delta
		var duration: float = PALM_RELEASE_SECONDS if _profile == Profile.PALMS_ONLY else FLIGHT_SECONDS + _last_stagger + FADE_SECONDS # 根据实际表现回收。
		if _flight >= duration:
			queue_free()
			return
		if _profile == Profile.GROUND_MARKS:
			_ground_material.set_shader_parameter(&"released_time", _flight)
	if _profile == Profile.GROUND_MARKS:
		_ground_material.set_shader_parameter(&"age", _age)
	queue_redraw()

## 掌间、飞行和第一处溅落使用同一个世界画布。
func _draw() -> void:
	if not is_instance_valid(_palm):
		return
	if _flight < 0.0:
		_draw_buildup(_palm.global_position)
	elif _profile == Profile.PALMS_ONLY:
		_draw_buildup(_palm.global_position, 1.0 - smoothstep(0.0, PALM_RELEASE_SECONDS, _flight))
	elif _flight <= FLIGHT_SECONDS:
		_draw_flight(clampf(_flight / FLIGHT_SECONDS, 0.0, 1.0))
	elif _flight <= FLIGHT_SECONDS + 0.25:
		_draw_splatter((_flight - FLIGHT_SECONDS) / 0.25)

## [param palm] 附近的黑蜡逐滴汇聚到实际手势，[param opacity] 用于原位消散。
func _draw_buildup(palm: Vector2, opacity: float = 1.0) -> void:
	var gather: float = clampf(_age / GATHER_SECONDS, 0.0, 1.0) # 原画抬掌时五粒滴痕向中心收拢。
	var reveal: float = smoothstep(0.06, 0.47, gather) * opacity # 合掌和原位消散都只留细轮廓。
	var spread: float = lerpf(23.0, 3.1, gather) # 逐滴聚成主黑泪。
	for index: int in range(5): # 保持少量大小不等的墨点。
		var turn: float = index * 2.399963 + gather * 1.15 # 各滴从不同方向沉向掌心。
		var bead: Vector2 = palm + Vector2(cos(turn) * spread, sin(turn) * spread * 0.55 - 5.0 - 6.0 * (1.0 - gather)) # 压扁环面。
		var radius: float = (1.6 + index % 3 * 0.55) * reveal # 同一时间出现不同大小。
		draw_circle(bead, radius, Color(INK, reveal * 0.92), true, -1.0, true)
		draw_arc(bead, radius, 3.55, 5.20, 6, Color(WET_EDGE, reveal * 0.43), 0.9, true)
	draw_circle(palm + Vector2(0.0, -4.5), 3.7 * gather * opacity, Color(INK, reveal), true, -1.0, true)

## 根据 [param progress] 绘制沿抛线落下的黑泪和短拖尾。
func _draw_flight(progress: float) -> void:
	var trail := PackedVector2Array() # 预留一条短带，避免整段轨迹一直留在空中。
	for sample: int in range(8): # 同一曲线的均匀样本。
		trail.append(_flight_position(lerpf(maxf(0.0, progress - 0.24), progress, float(sample) / 7.0)))
	var strength: float = smoothstep(0.0, 0.14, progress) # 刚出手时从原掌间位置长出来。
	if strength > 0.0:
		draw_polyline(trail, Color(INK, strength * 0.78), 3.6, true)
		draw_polyline(trail, Color(WET_EDGE, strength * 0.38), 0.85, true)
	var nose := _flight_position(progress) # 墨滴头的位置。
	var tangent := _flight_position(minf(progress + 0.018, 1.0)) - _flight_position(maxf(progress - 0.018, 0.0)) # 短笔触顺着实际飞行方向。
	var size: float = lerpf(0.65, 1.03, smoothstep(0.0, 0.62, progress)) # 出掌后稍微拉长。
	draw_set_transform(nose, tangent.angle(), Vector2(size, 1.0))
	draw_colored_polygon(DROP, Color(INK, 0.98))
	draw_polyline(DROP_EDGE, Color(WET_EDGE, 0.58), 1.35, true)
	draw_set_transform(Vector2.ZERO)

## [param progress] 对应离手到落地的连续二次曲线。
func _flight_position(progress: float) -> Vector2:
	return _departure.lerp(_flight_control, progress).lerp(_flight_control.lerp(_landing, progress), progress)

## 以 [param progress] 推进主落点的少量飞溅碎滴。
func _draw_splatter(progress: float) -> void:
	var opacity: float = 1.0 - smoothstep(0.15, 1.0, progress) # 碎滴先散开后消失。
	var extent: Vector2 = _targets[0].size * Vector2(0.36, 0.22) # 飞溅始终贴近实际地块。
	for index: int in range(7): # 小型固定飞溅，避免持续分配粒子节点。
		var turn: float = index * 2.399963 + 0.8 # 不等距飞溅。
		var motion := Vector2(cos(turn), sin(turn)) * extent * pow(progress, 0.55) # 在石面上扩散减速。
		var size: float = (1.6 + index % 3 * 0.58) * opacity # 碎滴同时失去边缘。
		draw_circle(_landing + motion, size, Color(INK, opacity * 0.9), true, -1.0, true)
		draw_arc(_landing + motion, size, 3.35, 5.0, 6, Color(WET_EDGE, opacity * 0.41), 0.8, true)
