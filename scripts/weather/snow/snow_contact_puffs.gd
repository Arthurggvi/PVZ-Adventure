## 将脚步和加重落地的少量雪晶批量画在战场空间，出生后随风漂移。
extends Node2D
class_name SnowContactPuffs

## 全场同时可见的短命雪晶上限；满时直接放弃新雪晶。
const MAX_FLAKES: int = 96
## 单个亮点由十二段有界扇形组成；小于四像素的雪晶仍保持近似圆形。
const CIRCLE_SIDES: int = 12
## 每个亮点唯一中心加十二个圆周点，所有亮点合并到一个渲染命令。
const VERTICES_PER_FLAKE: int = CIRCLE_SIDES + 1
## 所有活跃亮点的共享方向，不在绘制帧计算三角函数。
var _circle_directions := PackedVector2Array()
## 为最大并发数预留的绘制顶点，实际提交只截取活跃长度。
var _points := PackedVector2Array()
## 按亮点寿命赋予各顶点同一颜色和透明度。
var _colors := PackedColorArray()
## 只初始化一次的三角形索引，各亮点占十二个三角形。
var _indices := PackedInt32Array()

## 预建独立圆盘和全局索引；动画帧中仅更新坐标与透明度。
func _ready() -> void:
	for sector: int in range(CIRCLE_SIDES):
		_circle_directions.append(Vector2.RIGHT.rotated(TAU * float(sector) / float(CIRCLE_SIDES)))
	_points.resize(MAX_FLAKES * VERTICES_PER_FLAKE)
	_colors.resize(_points.size())
	_indices.resize(MAX_FLAKES * CIRCLE_SIDES * 3)
	for flake_index: int in range(MAX_FLAKES):
		var base: int = flake_index * VERTICES_PER_FLAKE # 本雪晶的中心顶点。
		for sector: int in range(CIRCLE_SIDES):
			var offset: int = (flake_index * CIRCLE_SIDES + sector) * 3 # 三角索引的首项。
			_indices[offset] = base
			_indices[offset + 1] = base + 1 + sector
			_indices[offset + 2] = base + 1 + (sector + 1) % CIRCLE_SIDES
## 本批次保存绘制局部坐标，速度以世界像素/秒计。
class Flake:
	## 漂移中的位置。
	var point: Vector2
	## 初始弹散速度与重力累积。
	var velocity: Vector2
	## 总可见时长，单位战斗秒。
	var duration: float
	## 尚未消散的战斗秒数。
	var remaining: float
	## 初始亮点半径，单位世界像素。
	var radius: float

## 只存活跃雪晶，可交换移除且无独立节点。
var _flakes: Array[Flake] = []
## 视觉随机数独立于战斗随机序列。
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## 在 [param world_position] 处弹散雪末；[param heavy] 为较重的落地，[param rolling] 为滚动末梢的少量细雪。
func burst(world_position: Vector2, heavy: bool, rolling: bool = false) -> void:
	var count: int = mini(1 if rolling else (4 if heavy else 2), MAX_FLAKES - _flakes.size()) # 有界短脉冲。
	for index: int in range(count): # 保证雪晶重叠区域很小。
		var flake: Flake = Flake.new() # 每个亮点只保存短时位置和速度。
		flake.point = to_local(world_position) + Vector2(_rng.randf_range(-4.0, 4.0), 0.0)
		flake.velocity = Vector2(_rng.randf_range(-23.0, 23.0), _rng.randf_range(-23.0, -8.0))
		flake.duration = _rng.randf_range(0.22, 0.42)
		flake.remaining = flake.duration
		flake.radius = _rng.randf_range(0.8, 1.7)
		_flakes.append(flake)

## [param delta] 采用战斗秒，[param wind] 为同一雪天气系统的世界风速。
func advance(delta: float, wind: Vector2) -> void:
	if _flakes.is_empty():
		return
	var seconds: float = clampf(delta, 0.0, 0.1) # 碰到卡顿不会补做一连串所属脚步。
	for index: int in range(_flakes.size() - 1, -1, -1): # 倒序移除已退场的亮点。
		var flake: Flake = _flakes[index] # 当帧待推进的雪晶。
		flake.remaining -= seconds
		if flake.remaining <= 0.0:
			_flakes[index] = _flakes.back()
			_flakes.pop_back()
			continue
		flake.velocity.y += 68.0 * seconds
		flake.point += (flake.velocity + wind * 0.24) * seconds
	queue_redraw()

## 所有短寿命圆形亮点以一条 triangle-array 命令绘制，不改变出生、运动和消隐。
func _draw() -> void:
	var count: int = _flakes.size() # 本帧活跃雪晶数，受 MAX_FLAKES 约束。
	if count == 0:
		return
	for flake_index: int in range(count):
		var flake: Flake = _flakes[flake_index] # 当前世界风场推进后的雪晶。
		var base: int = flake_index * VERTICES_PER_FLAKE # 预分配缓冲中该雪晶的起点。
		var fade: float = flake.remaining / flake.duration # 沿用原雪晶的线性透明衰减。
		var tint: Color = Color(0.82, 0.93, 0.99, fade * 0.67) # 保留现有冷白亮度和透明度。
		_points[base] = flake.point
		_colors[base] = tint
		for sector: int in range(CIRCLE_SIDES):
			var index: int = base + sector + 1 # 按固定方向构造有界扇面。
			_points[index] = flake.point + _circle_directions[sector] * flake.radius
			_colors[index] = tint
	var vertices: int = count * VERTICES_PER_FLAKE # 本帧实际使用的顶点数。
	var triangles: int = count * CIRCLE_SIDES * 3 # 本帧实际使用的三角索引数。
	var points: PackedVector2Array = _points if vertices == _points.size() else _points.slice(0, vertices)
	var colors: PackedColorArray = _colors if vertices == _colors.size() else _colors.slice(0, vertices)
	var indices: PackedInt32Array = _indices if triangles == _indices.size() else _indices.slice(0, triangles)
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), indices, points, colors)
