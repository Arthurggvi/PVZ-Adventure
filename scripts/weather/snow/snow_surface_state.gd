## 低频雪面厚度、压实和潮湿状态。以浮点推进，仅在提交给地板着色器时量化。
extends RefCounted
class_name SnowSurfaceState

## 本关的同一物理雪面算法，独立文件通过静态依赖保证冷启动可识别。
const StepJob = preload("res://scripts/weather/snow/snow_surface_step_job.gd")

## 高档状态以及 CPU 静态遮罩尺寸，低档每轴减半。
const MASK_SIZE := Vector2i(256, 128)
## 动态纹理每像素四字节，第四通道保持常量。
const PIXEL_STRIDE: int = 4

## 当前状态采样网格尺寸。
var size := Vector2i.ZERO
## 对应当前档位的压实状态贴图，游戏帧间持续复用。
var texture: ImageTexture
## 静态容量与背风倾向，均为 0..1，只在本关卡配置时生成。
var _mask := PackedVector2Array()
## 抽样至当前精度的容量与背风倾向。
var _terrain := PackedVector2Array()
## 地形不变的单位降雪系数；换画质时重建，不在每次天气步内计算。
var _snow_rate := PackedFloat32Array()
## 地形不变的单位风蚀系数；仅天气风强和当前雪深需要逐步计算。
var _scour_rate := PackedFloat32Array()
## 当前精度下按行登记的可积雪格，换档时重建，固定步进可略过裸岩和透明区。
var _eligible := PackedInt32Array()
## R 松雪厚度、G 压实、B 暂时潮湿，均为 0..1。
var _values := PackedVector3Array()
## 每格当前回填速度，按秒，供细节压痕共享。
var _refill := PackedFloat32Array()
## 限频更新贴图使用的固定图像和量化缓冲。
var _image := Image.new()
## 量化的 RGBA8 数据，更新时不重建其尺寸。
var _pixels := PackedByteArray()
## 当前跨帧运行的独占雪面积雪计算；空值表示全部状态均已提交。
var _step_job: StepJob
## 计算期间收到的脚印、热源，按到达顺序在状态提交后重放。
var _pending_impacts: Array[Dictionary] = []

## [param frame] 是当前地板可见区域，已按 [constant MASK_SIZE] 缩放并应用翻转。
func read_ground(frame: Image) -> void:
	_mask.resize(MASK_SIZE.x * MASK_SIZE.y)
	for y: int in range(MASK_SIZE.y): # 地板绘制区内自上往下的像素行。
		for x: int in range(MASK_SIZE.x): # 地板绘制区内自左往右的列。
			var color: Color = frame.get_pixel(x, y) # 原图地板不透明度与可见岩雪明度。
			var brightness: float = maxf(color.r, maxf(color.g, color.b)) # 与场景抠像共用的明度定义。
			var coverage: float = color.a * smoothstep(0.06, 0.42, brightness) # 保留真实边缘和透明区域。
			var capacity: float = coverage * smoothstep(0.25, 0.68, brightness) # 暗岩和裸冰的松雪量受限。
			var drift: float = sin(float(x) * 0.083 + float(y) * 0.054) * 0.18 # 大尺度、缓变的横向风积倾向。
			var leeward: float = clampf(0.35 + capacity * 0.35 + drift, 0.0, 1.0) # 较粗糙的浅色雪地可留更多粉雪。
			_mask[y * MASK_SIZE.x + x] = Vector2(capacity, leeward)

## 用 [param high_quality] 选择分辨率，在换档时从原 CPU 浮点状态重采样，不清除积雪。
func set_quality(high_quality: bool) -> void:
	var target: Vector2i = MASK_SIZE if high_quality else Vector2i(128, 64) # 实际档位网格尺寸。
	if target == size:
		return
	var prior: PackedVector3Array = _values # 独立快照，供重采样使用。
	var prior_size: Vector2i = size # 旧状态步幅。
	size = target
	var count: int = size.x * size.y # 当前档位总像素数量。
	_values = PackedVector3Array()
	_values.resize(count)
	_terrain.resize(count)
	_snow_rate.resize(count)
	_scour_rate.resize(count)
	_eligible.clear()
	_refill.resize(count)
	_pixels.resize(count * PIXEL_STRIDE)
	for y: int in range(size.y): # 新网格中当前行。
		for x: int in range(size.x): # 新网格中当前列。
			var index: int = y * size.x + x # 新网格的连续索引。
			var uv: Vector2 = (Vector2(x, y) + Vector2(0.5, 0.5)) / Vector2(size) # 精确取像素中心。
			var land: Vector2 = _mask[_index_at(uv, MASK_SIZE)] # 统一静态遮罩在本档位的样本。
			_terrain[index] = land
			_snow_rate[index] = (0.013 + 0.032 * land.y) * land.x
			_scour_rate[index] = (1.0 - land.y) * 0.035
			if land.x > 0.001:
				_eligible.append(index)
			_values[index] = prior[_index_at(uv, prior_size)] if not prior.is_empty() else Vector3(land.x * 0.34, 0.0, 0.0)
			_refill[index] = 0.017
			_encode(index)
	_image.set_data(size.x, size.y, false, Image.FORMAT_RGBA8, _pixels)
	texture = ImageTexture.create_from_image(_image)

## 推进完整固定步长；直接调用的旧入口仍同步结束，避免其它场景意外延迟。
func advance(delta: float, snow: float, wind: float) -> void:
	if has_pending_step():
		finish_step(_eligible.size())
	if begin_step(delta, snow, wind):
		finish_step(_eligible.size())

## [param delta] 等于当前固定天气步长，只捕获静态输入并启动新的分块计算。
## 返回 false 表示还在运行另一任务或雪地没有有效像素，不修改已发布的状态。
func begin_step(delta: float, snow: float, wind: float) -> bool:
	if has_pending_step() or _eligible.is_empty():
		return false
	_step_job = StepJob.new()
	_step_job.begin(self, delta, snow, wind)
	return true

## [param max_cells] 为本帧允许消费的有效雪地像素个数；完成时才更新纹理并重放脚印。
## 返回 true 表示原子提交已经完成，便于外部同步更新雪痕回填。
func finish_step(max_cells: int) -> bool:
	if not has_pending_step() or not _step_job.consume(max_cells):
		return false
	_values = _step_job.values
	_refill = _step_job.refill
	_pixels = _step_job.pixels
	_step_job = null
	_image.set_data(size.x, size.y, false, Image.FORMAT_RGBA8, _pixels)
	texture.update(_image)
	for impact: Dictionary in _pending_impacts: # 这些效果在原算法中发生于本次雪面推进之后。
		_apply_local_now(impact.uv, impact.radius, impact.strength, impact.heat)
	_pending_impacts.clear()
	return true

## 对外显式报告是否仍在进行计算，不依赖渲染帧或线程状态。
func has_pending_step() -> bool:
	return _step_job != null

## 计算并行推进所需的有效像素数；无雪地时为零。
func eligible_count() -> int:
	return _eligible.size()

## 当前待处理像素数；没有在途步骤时为零。
func remaining_step_cells() -> int:
	return _step_job.remaining_cells() if has_pending_step() else 0

## 返回 [param uv] 处的静态容量、松雪厚度和压实，均为 0..1。
func sample(uv: Vector2) -> Vector3:
	var index: int = _index_at(uv, size) # 局部纹理中的中心采样。
	return Vector3(_mask[_index_at(uv, MASK_SIZE)].x, _values[index].x, _values[index].y)

## 返回当前回填速度的只读快照；细节纹理与状态网格同原点。
func refill_rates() -> PackedFloat32Array:
	return _refill

## 以 [param uv] 为中心，记录当前真实脚印或热源，分帧推进结束后按相同顺序重放。
func apply_local(uv: Vector2, radius_uv: Vector2, strength: float, heat: bool = false) -> void:
	if has_pending_step():
		_pending_impacts.append({"uv": uv, "radius": radius_uv, "strength": strength, "heat": heat})
	_apply_local_now(uv, radius_uv, strength, heat)

## 将一项已验证的接触直接应用到当前可读状态；旧同步入口也复用相同数值实现。
func _apply_local_now(uv: Vector2, radius_uv: Vector2, strength: float, heat: bool) -> void:
	var center: Vector2 = uv * Vector2(size) # 低分辨率 texel 坐标。
	var radius: Vector2 = (radius_uv * Vector2(size)).max(Vector2(0.85, 0.85)) # 单脚仍可作用到一个网格。
	var clip := Rect2i(Vector2i((center - radius).floor()), Vector2i((radius * 2.0).ceil()) + Vector2i.ONE) # 局部更新范围。
	clip = clip.intersection(Rect2i(Vector2i.ZERO, size))
	for y: int in range(clip.position.y, clip.end.y): # 形状覆盖的纵向 texel。
		for x: int in range(clip.position.x, clip.end.x): # 形状覆盖的横向 texel。
			var index: int = y * size.x + x # 运行状态索引。
			var distance: float = ((Vector2(x, y) + Vector2(0.5, 0.5) - center) / radius).length_squared() # 相对局部范围的归一化距离。
			var impact: float = maxf(0.0, 1.0 - distance) * strength * _terrain[index].x # 岩石和无覆盖区域抑制压痕。
			if impact <= 0.0:
				continue
			var value: Vector3 = _values[index] # 当前低频积雪状态，不触碰任何战斗层数据。
			if heat:
				value.x = maxf(0.0, value.x - impact * 0.28)
				value.z = maxf(value.z, impact)
			else:
				value.y = maxf(value.y, impact * (0.3 + value.x * 0.7))
				value.x = maxf(0.0, value.x * (1.0 - impact * 0.25))
			_values[index] = value

## 将 [param uv] 裁至 [param grid] 网格范围并返回行优先索引。
static func _index_at(uv: Vector2, grid: Vector2i) -> int:
	var xy: Vector2i = Vector2i(uv * Vector2(grid)).clamp(Vector2i.ZERO, grid - Vector2i.ONE) # UV=1 时取内侧边界。
	return xy.y * grid.x + xy.x

## 在分配或换档时，将 [param index] 的浮点状态量化，并初始化恒定的不透明通道。
func _encode(index: int) -> void:
	var offset: int = index * PIXEL_STRIDE # RGBA8 交错字节位置。
	var value: Vector3 = _values[index] # 三个覆盖通道均已裁至合法范围。
	_pixels[offset] = roundi(value.x * 255.0)
	_pixels[offset + 1] = roundi(value.y * 255.0)
	_pixels[offset + 2] = roundi(value.z * 255.0)
	_pixels[offset + 3] = 255
