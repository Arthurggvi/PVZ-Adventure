## 冥弹专属连续尾迹：一条非累积混合的墨烟流、一层银蓝芯和两条错相幽灵丝。
extends Node2D
class_name RepeaterHadesTrail

## 最多保留40个实际时间采样，密集弹幕时内存与绘制数量均有界。
const MAX_SAMPLES: int = 40
## 每六十分之一战斗秒采样，不用渲染帧数量控制尾迹密度。
const SAMPLE_STEP: float = 1.0 / 60.0
## 无论弹体飞多远，烟幕都不会超过两格半的像素长度。
const MAX_LENGTH: float = 204.0

## 只读取原生弹体的世界位置，不持有其命中、伤害或战斗状态。
var _body: Node2D
## 一颗弹体的世界空间路径采样，退场后由父视觉宿主渐隐。
var _history: PackedVector2Array = PackedVector2Array()
## 上一显示帧世界位置，用于均匀时间插值。
var _previous: Vector2
## 下次采样前剩余时间。
var _remainder: float = 0.0
## 只用于小范围错相振动的局部视觉秒数。
var _age: float = 0.0
## 弹体消失后停止加入采样，父节点仍可保留已存在尾迹。
var _stopped: bool = false
## 加色的第二层光丝，完全共用历史点，避免与烟芯偏离。
var _light: Node2D

## [param body] 为本次弹体身体；共享原生运动，不建立新的运动控制器。
func configure(body: Node2D) -> void:
	_body = body
	_previous = body.global_position
	_history.append(_previous)
	_light = Node2D.new()
	_light.z_index = -1
	_light.material = RepeaterVisualPalette.glow_material()
	_light.draw.connect(_draw_light)
	add_child(_light)

## 在暂停语义内按固定时间插入历史点；异常大帧最多增加40个样本。
func _process(delta: float) -> void:
	_age += delta
	if not _stopped and is_instance_valid(_body) and _body.is_inside_tree() \
			and not _body.is_queued_for_deletion() and _body.is_visible_in_tree():
		var now: Vector2 = _body.global_position
		_remainder += delta
		var count: int = mini(MAX_SAMPLES, floori(_remainder / SAMPLE_STEP))
		for index: int in range(count):
			var fraction: float = float(index + 1) / float(maxi(count, 1))
			_history.append(_previous.lerp(now, fraction))
			if _history.size() > MAX_SAMPLES:
				_history.remove_at(0)
		_remainder = fposmod(_remainder, SAMPLE_STEP)
		while _history.size() > 2 and _history[0].distance_to(now) > MAX_LENGTH:
			_history.remove_at(0)
		_previous = now
	else:
		_stopped = true
	queue_redraw()
	_light.queue_redraw()

## 返回当前保留的世界轨迹转为该视觉画布局部坐标的独立数组。
func _path() -> PackedVector2Array:
	var path := PackedVector2Array()
	for point: Vector2 in _history:
		path.append(to_local(point))
	return path

## [param path] 为完整时空采样；[param side] 表示主轨道两侧的灵丝分叉。
func _ghost_wisp(path: PackedVector2Array, side: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for index: int in range(path.size()):
		var previous: Vector2 = path[maxi(0, index - 1)]
		var next: Vector2 = path[mini(path.size() - 1, index + 1)]
		var tangent: Vector2 = (next - previous).normalized()
		var across := Vector2(-tangent.y, tangent.x)
		var oscillation: float = sin(float(index) * 0.57 - _age * 5.7 + side * 1.2)
		result.append(path[index] + across * side * (6.5 + oscillation * 4.0))
	return result

## 宽烟芯仅按整条路径混合一次，避免旧版分段叠色堆出方形深色条。
func _draw() -> void:
	var path: PackedVector2Array = _path()
	if path.size() < 2:
		return
	var black := PackedColorArray()
	var violet := PackedColorArray()
	var silver := PackedColorArray()
	for index: int in range(path.size()):
		var weight: float = float(index) / float(path.size() - 1)
		black.append(Color(0.035, 0.04, 0.10, 0.53 * pow(weight, 1.18)))
		violet.append(Color(0.31, 0.27, 0.63, 0.65 * pow(weight, 1.42)))
		silver.append(Color(0.75, 0.87, 1.0, 0.82 * pow(weight, 2.0)))
	draw_polyline_colors(path, black, 15.0, true)
	draw_polyline_colors(path, violet, 6.4, true)
	draw_polyline_colors(path, silver, 1.7, true)
	for side: float in [-1.0, 1.0]:
		var filament: PackedVector2Array = _ghost_wisp(path, side)
		var colors := PackedColorArray()
		for index: int in range(filament.size()):
			var weight: float = float(index) / float(filament.size() - 1)
			colors.append(Color(0.45, 0.75, 1.0, 0.58 * pow(weight, 2.0)))
		draw_polyline_colors(filament, colors, 1.1, true)
	for index: int in range(3, path.size(), 6):
		var weight: float = float(index) / float(path.size() - 1)
		var spot: Vector2 = path[index] + Vector2(sin(_age * 6.2 + index) * 3.0, cos(_age * 4.8 + index) * 3.0)
		var radius: float = 11.0 + weight * 6.0
		draw_texture_rect(RepeaterVisualPalette.halo_texture(), Rect2(spot - Vector2.ONE * radius, Vector2.ONE * radius * 2.0),
			false, Color(0.12, 0.17, 0.32, 0.24 * weight))
		draw_circle(spot, 0.80 + weight * 0.4, Color(0.82, 0.93, 1.0, weight * 0.55))

## 第二条光层亦用整条路径的渐变曲线，淡紫边缘与高光不产生重复叠段。
func _draw_light() -> void:
	var path: PackedVector2Array = _path()
	if path.size() < 2:
		return
	var aura := PackedColorArray()
	var glow := PackedColorArray()
	for index: int in range(path.size()):
		var weight: float = float(index) / float(path.size() - 1)
		aura.append(Color(0.29, 0.41, 0.96, 0.29 * pow(weight, 1.55)))
		glow.append(Color(0.71, 0.89, 1.0, 0.55 * pow(weight, 2.0)))
	_light.draw_polyline_colors(path, aura, 18.0, true)
	_light.draw_polyline_colors(path, glow, 3.2, true)
