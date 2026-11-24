## 真实地面步段触发步行扬雪和连续雪槽。接触资格与原生事件由 SnowContactTrack 提供。
extends RefCounted

## 扫掠每段在 X 轴的最大世界像素；每段端点单独采样坡面。
const SWEEP_STEP: float = 7.0

## 相邻扬雪点的地面步距，单位为世界像素。
var _stride: float
## 两侧扬雪点相对步行中心的偏移，单位为世界像素。
var _step_offset: float
## 到下一次交替落脚的剩余地面距离，单位为世界像素。
var _remaining: float = 0.0
## 左右脚交替的法线方向符号。
var _side: float = 1.0
## 上次地面位移的横向符号。
var _heading: float = 0.0
## 本段最后一次触发扬雪的世界脚点，空段为 INF。
var latest_step: Vector2 = Vector2.INF

## 用 [param stride] 和 [param foot_width] 控制步行节奏和扬雪偏移，均为世界像素。
func _init(stride: float, foot_width: float) -> void:
	_stride = stride
	_step_offset = foot_width * 0.44
	reset()

## 清掉起步前的步距、方向和前一帧扬雪位置。
func reset() -> void:
	_remaining = _stride * 0.5
	_side = 1.0
	_heading = 0.0
	latest_step = Vector2.INF

## 在 [param surface] 的 [param lane] 处理 [param from] 到 [param to] 的真实地面位移。
## [param offset_x] 为原影子的像素对齐量，[param puffs] 接收雪晶，返回使用的 [param budget]。
func walk(surface: SnowSurface, puffs: SnowContactPuffs, from: Vector2, to: Vector2, lane: int, offset_x: float, budget: int) -> int:
	latest_step = Vector2.INF
	if not surface.allows_contact(from) or not surface.allows_contact(to):
		_remaining = _stride * 0.5
		return 0
	var direction: float = signf(to.x - from.x) # 魅惑或转身后重新起步。
	if _heading != direction:
		reset()
		_heading = direction
	var distance: float = from.distance_to(to) # 坡面路长，减少陡坡上的步间距误差。
	var next: float = _remaining # 当前步段中下一次落脚到起点的距离。
	var used: int = 0 # 超预算仍消费距离，保持两侧扬雪的交替节奏。
	while next <= distance:
		if used < budget:
			var x: float = lerpf(from.x, to.x, next / distance) + offset_x # 沿用原影子的横向对齐。
			var tangent: Vector2 = surface.ground_tangent(x, lane) # 从坡面导出双脚错位的方向。
			var center: Vector2 = surface.ground_point(x, lane) \
				+ Vector2(-tangent.y, tangent.x) * (_step_offset * _side * direction) # 双脚沿法线交错。
			if surface.allows_contact(center):
				puffs.burst(center, false)
				latest_step = center
				used += 1
		_side = -_side
		next += _stride
	_remaining = next - distance
	return used

## 将 [param surface] 的 [param lane] 中 [param from_x] 到 [param to_x] 分段贴坡绘制。
## [param width] 为世界像素，[param strength] 为归一压实，返回不超过 [param budget] 的有效段数。
static func sweep(surface: SnowSurface, from_x: float, to_x: float, lane: int, width: float,
		strength: float, budget: int) -> int:
	var count: int = ceili(absf(to_x - from_x) / SWEEP_STEP) # 调用方过滤传送，常规最多八段。
	var start: Vector2 = surface.ground_point(from_x, lane) # 首端贴真实坡面。
	var used: int = 0 # 仅有效片段占预算。
	for index: int in range(1, count + 1): # 相邻片段共用边界。
		var end: Vector2 = surface.ground_point(lerpf(from_x, to_x, float(index) / count), lane) # 按坡高生成末端。
		if used < budget and surface.allows_contact(start) and surface.allows_contact(end):
			surface.sweep(start, end, width, strength)
			used += 1
		start = end
	return used
