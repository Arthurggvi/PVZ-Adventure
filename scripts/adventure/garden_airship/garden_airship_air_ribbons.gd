## 由同一航迹驱动的定容雾丝批次。战场后层和船身外层各批量提交一组局部面片。
extends MultiMeshInstance2D

## 局内风场及统一参考画幅投影。
const Wind := preload("res://scripts/adventure/garden_airship/garden_airship_wind.gd")
## 将虚拟纵深换算为各画布当前速度。
const FlowSpace := preload("res://scripts/adventure/garden_airship/garden_airship_flow_space.gd")
## 由正式船框变换支撑的外缘与桨流形状。
const HullWake := preload("res://scripts/adventure/garden_airship/garden_airship_hull_wake.gd")
## 兼容档保留两个桨尾、上梁和龙骨。高档增加不同节奏的沿边短丝。
const HULL_TRACKS: Array[int] = [HullWake.Track.RAIL, HullWake.Track.KEEL, HullWake.Track.PORT,
	HullWake.Track.RAIL, HullWake.Track.STARBOARD, HullWake.Track.KEEL, HullWake.Track.RAIL,
	HullWake.Track.PORT, HullWake.Track.STARBOARD, HullWake.Track.KEEL]
## 前八个浮点组成两行二维变换，后面各四个浮点为颜色和局部纹理参数。
const INSTANCE_STRIDE: int = 16
## 同一条参考投影的焦距。由深度决定速度，而不是另建速度时钟。
const FOCAL: float = 1000.0
## 后层宽条用稍偏蓝的云色，在暖日光下仍与现有云体一致。
const GAP_COLOR := Color(0.86, 0.94, 1.0)
## 贴身凝结丝用更亮但透明的水汽色。
const HULL_COLOR := Color(0.92, 0.96, 1.0)

## 是否为战斗前景中依船框定轨的近身批次，默认位于战斗背面。
@export var exterior: bool = false
## 两个气流批次共用的单位面片。
@export var ribbon_quad: QuadMesh

## 每个固定槽位只在不可见时改变形态，位置沿统一航迹推进。
class Filament:
	## 画层局部横坐标。INF 只用于尚未分配初始位置。
	var x: float = INF
	## 供后景分层或前景沿边分散的纵向设定，单位为战场像素。
	var lane: float
	## 雾丝虚拟深度。
	var depth: float
	## 参考画幅中软边四边形全宽。
	var width: float
	## 视觉曝光秒数，决定拖尾长度。
	var exposure: float
	## 当次轨道的峰值透明度。
	var alpha: float
	## 低频形变的初相。
	var phase: float
	## Shader 内的局部云纹编号，范围 [0, 7]。
	var variant: int

## 初始化后不再增删的槽位。
var _slots: Array[Filament] = []
## 局部表现专用可复测序列，与战斗随机隔离。
var _rng := RandomNumberGenerator.new()
## 前景场景独占的绕流曲线。
var _hull := HullWake.new()
## 裁剪后的二维变换、颜色和形态写入预分配实例缓冲。
var _instances := PackedFloat32Array()
## 当前帧成功写入网格的条数。
var _draw_count: int = 0

## 一次性建立固定 GPU 实例槽，逐帧只提交可见部分的变换和透明度。
func _ready() -> void:
	var count: int = HULL_TRACKS.size() if exterior else 18 # 两批次合计上限 28 条。
	_rng.seed = 0xA1757 if exterior else 0xA1753
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = ribbon_quad
	multimesh.instance_count = count
	multimesh.visible_instance_count = 0
	_instances.resize(count * INSTANCE_STRIDE)
	var tint: Color = HULL_COLOR if exterior else GAP_COLOR # 各批次的峰值颜色固定。
	for index: int in count: # 预建粒子和实例颜色，运行时只更新实例透明度和形态。
		_slots.append(Filament.new())
		_reseed(_slots[index], index)
		var offset: int = index * INSTANCE_STRIDE # 二维矩阵占用前八个槽位。
		_instances[offset + 8] = tint.r
		_instances[offset + 9] = tint.g
		_instances[offset + 10] = tint.b

## [param ship_frame] 只供前景批次读取可见船体轮廓。
func bind_hull(ship_frame: Sprite2D) -> void:
	_hull.bind(ship_frame)

## 消费 [param wind] 与其新增虚拟 [param travel]，不维护独立时钟。
## [param heave] 为背层云漂移，[param amount] 为气流可见度，[param reduced] 控制提交预算。
func apply_flow(wind: Wind, travel: float, heave: float, amount: float, reduced: bool) -> void:
	var canvas: Transform2D = get_global_transform_with_canvas() # 按各节点真实画布换算参考像素。
	_draw_count = 0
	if exterior and not _hull.refresh(canvas):
		if multimesh.visible_instance_count != 0:
			multimesh.visible_instance_count = 0
		return
	var screen: Rect2 = get_viewport_rect() # 伸缩保留的实际世界视口，含原有相机位移。
	var view: Rect2 = canvas.affine_inverse() * screen # 进出场及裁剪均以当前局部可见区域为界。
	var units: float = FlowSpace.reference_to_world(screen.size.x, canvas, Wind.DIRECTION) # 1920 参考像素到本层单位。
	var baseline_distance: float = travel * Wind.CRUISE_SPEED / maxf(wind.ship_speed, 1.0) # 由同一航迹换回相对风可用的基准路程。
	var margin: float = 142.0 * units # 大于最长雾丝半幅和软边，回收时整条离开视图。
	var count: int = mini(_slots.size(), 5 if exterior else 11) if reduced else _slots.size() # 低档仍有 16 条固定参照。
	for index: int in count: # 先分布到可见航路，再仅提交实际会画到的部分。
		_advance_slot(index, wind, baseline_distance, view, units, margin, heave, amount)
	if _draw_count > 0:
		multimesh.buffer = _instances
	if multimesh.visible_instance_count != _draw_count:
		multimesh.visible_instance_count = _draw_count

## 推进 [param index] 槽位，按 [param wind]、虚拟 [param travel] 和 [param view] 裁剪。
## [param units] 为参考缩放，[param margin] 为离场余量；[param heave] 和 [param amount] 只影响外观。
func _advance_slot(index: int, wind: Wind, travel: float, view: Rect2, units: float,
		margin: float, heave: float, amount: float) -> void:
	var slot: Filament = _slots[index] # 沿已有风向积分的可见雾丝。
	var track: int = HULL_TRACKS[index] if exterior else HullWake.Track.RAIL # 背层只读自己的分层带。
	var rotor: bool = exterior and HullWake.is_rotor(track) # 只有桨流在局部下风侧形成和消散。
	var load: float = clampf(wind.cruise_load, 0.0, 1.0) # 影响桨流消散范围和中心浓度。
	var bounds: Vector2 = _hull.rotor_bounds(track, load) if rotor else Vector2(view.position.x, view.end.x) # 局部或视口轨道。
	if rotor:
		var gust: float = wind.gust_at(to_global(Vector2(bounds.x, 0.0)).x, 0.037) # 单侧短时扰动只增加其桨流长度和浓度。
		load = minf(1.0, load + 0.28 * gust)
		bounds = _hull.rotor_bounds(track, load)
	if is_inf(slot.x):
		var phase: float = fposmod(0.13 + index * 0.618034, 1.0) # 错开的首帧相位，避免相邻轨全部排在上风侧。
		slot.x = lerpf(bounds.x - (margin * 2.0 if rotor else margin), bounds.y, phase)
	var flow_ratio: float = wind.sample_flow_ratio(to_global(Vector2(slot.x, 0.0)).x, 0.037, 0.28) # 阵风和飞越只作用于其实际位置。
	slot.x += Wind.DIRECTION.x * FlowSpace.project_travel(travel * flow_ratio, FOCAL, slot.depth) * units
	if slot.x > bounds.y + (0.0 if rotor else margin):
		_reseed(slot, index)
		# 桨后从透明涡丝生成，其他轨道均在完整画幅以外重生。
		slot.x = bounds.x - margin - _rng.randf_range(0.0, margin * (1.8 if rotor else 0.85))
	var speed: float = FlowSpace.project_travel(Wind.CRUISE_SPEED * flow_ratio, FOCAL, slot.depth) # 当前参考 px/s，决定局部拖尾。
	var length: float = clampf(speed * slot.exposure, 19.0, 177.0) * units # 保持短曝光范围及有限透明面积。
	if slot.x + length < view.position.x or slot.x - length > view.end.x:
		return
	var opacity: float = slot.alpha * amount # 整条丝峰值，着色器还会软化两端和横截面。
	if exterior:
		opacity *= _hull.opacity_at(track, slot.x, length, bounds) * (lerpf(0.76, 1.10, load) if rotor else 1.0)
	if opacity < 0.009:
		return
	var phase: float = slot.phase + wind.seconds * 0.93 # 共用有效飞行秒，保证回绕之间的弯曲连续。
	var left: float = slot.x - 0.5 * length # 曝光拖尾的上风端。
	var right: float = slot.x + 0.5 * length # 曝光拖尾的下风端。
	var a: float = _height(track, left, slot.lane, phase, bounds, heave) # 左端贴合实船或后景散流高度。
	var b: float = _height(track, right, slot.lane, phase, bounds, heave) # 右端形成真实绕流切线。
	var width: float = slot.width * units # 本批次局部像素宽度。
	if maxf(a, b) + width >= view.position.y and minf(a, b) - width <= view.end.y:
		_write_quad(Vector2(left, a), Vector2(right, b), width, opacity, slot.variant)

## 返回 [param track] 在 [param x] 的位置，叠加预置 [param lane]、连续 [param phase]。
## [param bounds] 限定桨流扰动区域，[param heave] 只传给后景。
func _height(track: int, x: float, lane: float, phase: float, bounds: Vector2, heave: float) -> float:
	if exterior:
		return _hull.height_at(track, x, lane, phase, bounds)
	return lane - heave + 3.9 * sin(phase + x * 0.012)

## 只在 [param slot] 隐藏时改形和分道；[param index] 保证每档都覆盖整个纵向空域。
func _reseed(slot: Filament, index: int) -> void:
	var elongated: bool = not exterior and index % 4 == 0 # 常态约五条较长云剥离纹，其余使用短曝光。
	var lane: float = float(index * 7 % 11) / 10.0 # 低档前 11 条仍遍布船梁后方至船底。
	slot.lane = _rng.randf_range(5.0, 20.0) if exterior else lerpf(203.0, 656.0, lane) + _rng.randf_range(-23.0, 23.0)
	slot.depth = _rng.randf_range(286.0, 386.0) if exterior else _rng.randf_range(458.0, 680.0)
	slot.width = _rng.randf_range(7.7, 11.1) if elongated else _rng.randf_range(4.7, 8.8)
	slot.exposure = _rng.randf_range(0.078, 0.104) if elongated else _rng.randf_range(0.017, 0.036)
	slot.alpha = _rng.randf_range(0.20, 0.31) if exterior else _rng.randf_range(0.37, 0.59)
	slot.phase = _rng.randf_range(0.0, TAU)
	slot.variant = _rng.randi_range(0, 7)

## 用实际 [param start]、[param end] 及 [param width] 装填单位面片的二维变换。
## [param opacity] 为峰值不透明度，[param variant] 由实例数据传给共享的雾丝 Shader。
func _write_quad(start: Vector2, end: Vector2, width: float, opacity: float, variant: int) -> void:
	var axis: Vector2 = end - start # 将单位面片沿轨道切线伸长到实际端点。
	var flank: Vector2 = axis.normalized().orthogonal() * width # 柔边宽度在切线的法向。
	var center: Vector2 = start + axis * 0.5 # 面片中心与旧两三角的质心相同。
	var offset: int = _draw_count * INSTANCE_STRIDE # 同一画层中已剔除屏外雾丝的实例编号。
	_instances[offset] = axis.x
	_instances[offset + 1] = flank.x
	_instances[offset + 3] = center.x
	_instances[offset + 4] = axis.y
	_instances[offset + 5] = flank.y
	_instances[offset + 7] = center.y
	_instances[offset + 11] = opacity
	_instances[offset + 12] = float(variant) / 7.0
	_draw_count += 1
