## 单次雪面积雪的可分块 CPU 运算；只读静态地形，所有可变结果独占缓冲。
extends RefCounted
class_name SnowSurfaceStepJob

## 当前快照的有效雪地像素；循正式行序处理以保持原算法数学顺序。
var _eligible := PackedInt32Array()
## 本阶段只读的真实地形容量与积雪上限。
var _terrain := PackedVector2Array()
## 本阶段只读的单位降雪系数。
var _snow_rate := PackedFloat32Array()
## 本阶段只读的单位风蚀系数。
var _scour_rate := PackedFloat32Array()
## 完成时一次性交还的浮点雪、压实与潮湿状态。
var values := PackedVector3Array()
## 完成时一次性交还的当前局部回填速率。
var refill := PackedFloat32Array()
## 完成时一次性上传的 RGBA8 雪面纹理。
var pixels := PackedByteArray()
## 本次模拟固定步长和天气强度。
var _delta: float = 0.0
var _snow: float = 0.0
var _wind_squared: float = 0.0
var _drying: float = 0.0
## 已处理的有效像素数，严格递增，不跨帧重新计算。
var _cursor: int = 0

## 从 [param source] 冻结计算输入并复制本步独占的结果缓冲，不改写仍被接触查询读取的状态。
func begin(source: RefCounted, delta: float, snow: float, wind: float) -> void:
	_eligible = source.get("_eligible")
	_terrain = source.get("_terrain")
	_snow_rate = source.get("_snow_rate")
	_scour_rate = source.get("_scour_rate")
	var current_values: PackedVector3Array = source.get("_values") # 原战场的上一已完成雪面。
	var current_refill: PackedFloat32Array = source.get("_refill") # 原战场的上一回填速率。
	var current_pixels: PackedByteArray = source.get("_pixels") # 原战场的上一纹理。
	values = current_values.duplicate()
	refill = current_refill.duplicate()
	pixels = current_pixels.duplicate()
	_delta = delta
	_snow = snow
	_wind_squared = wind * wind
	_drying = delta * 0.042
	_cursor = 0

## 本次工作尚待处理的像素数，可将用不完的帧预算交给下一固定步。
func remaining_cells() -> int:
	return _eligible.size() - _cursor

## 最多更新 [param max_cells] 个真实有雪像素；返回 true 表示计算完成，可由所有者原子提交。
func consume(max_cells: int) -> bool:
	var limit: int = mini(_eligible.size(), _cursor + maxi(1, max_cells)) # 禁止零预算造成永久等待。
	for cursor: int in range(_cursor, limit):
		var index: int = _eligible[cursor] # 与原算法完全一致的有效索引。
		var land: Vector2 = _terrain[index] # 原有静态容量。
		var value: Vector3 = values[index] # 本次结果缓冲，未发布之前外界不可读取。
		var fall: float = _snow * _snow_rate[index] * (1.0 - value.z * 0.8) # 保留既有降雪公式。
		var scour: float = _wind_squared * _scour_rate[index] * value.x # 保留既有风蚀公式。
		var net_snow: float = fall - scour # 仍按相同次序进行浮点计算。
		var rate: float = 0.015 + maxf(0.0, net_snow) * 3.1 + value.z * 0.035
		var offset: int = index * 4 # RGBA8 首字节。
		value.x = clampf(value.x + net_snow * _delta, 0.0, land.x)
		pixels[offset] = roundi(value.x * 255.0)
		if value.y != 0.0:
			value.y = move_toward(value.y, 0.0, _delta * rate)
			pixels[offset + 1] = roundi(value.y * 255.0)
		if value.z != 0.0:
			value.z = move_toward(value.z, 0.0, _drying)
			pixels[offset + 2] = roundi(value.z * 255.0)
		values[index] = value
		refill[index] = rate
	_cursor = limit
	return _cursor >= _eligible.size()
