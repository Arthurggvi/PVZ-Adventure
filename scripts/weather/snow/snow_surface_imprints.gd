## 世界压痕批量合成纹理。每像素保存最深压陷及较高雪沿，合并短轨迹且始终有界。
extends RefCounted
class_name SnowSurfaceImprints

## 细节网格与低频状态对齐，每个状态 texel 对应 3×3 个细节像素。
const DETAIL_SCALE: int = 3

## 当前档位的归一化压陷/雪沿贴图。
var texture: ImageTexture
## 当前细节栅格尺寸，覆盖地板的完整绘制矩形。
var _size := Vector2i.ZERO
## 各像素浮点压陷和雪沿，重复踩踏取逐通道最大值。
var _marks := PackedVector2Array()
## 尚有痕迹的 texel 索引，仅在压痕从空白转为可见时登记一次。
var _active := PackedInt32Array()
## 量化的 RG8 缓冲，数据纹理无需颜色空间校正。
var _pixels := PackedByteArray()
## 用于限频更新的独立固定尺寸图像。
var _image := Image.new()
## CPU 缓冲在上次提交后是否有字节改写，画入印迹时就记录并保留到下次提交。
var _texture_dirty: bool = false

## 将细节网格对齐到 [param state_size] 的低频雪面，换档时保留已有的痕迹。
func resize(state_size: Vector2i) -> void:
	var target: Vector2i = state_size * DETAIL_SCALE # 统一原点下的不同分辨率。
	if target == _size:
		return
	var prior: PackedVector2Array = _marks # 完整的原档位积雪印迹。
	var prior_size: Vector2i = _size # 原纹理宽高。
	_size = target
	_marks = PackedVector2Array()
	_marks.resize(_size.x * _size.y)
	_pixels.resize(_marks.size() * 2)
	_pixels.fill(0)
	_active.clear()
	if not prior.is_empty():
		for y: int in range(_size.y): # 新精度下的纵向像素位置。
			for x: int in range(_size.x): # 新精度下的横向像素位置。
				var index: int = y * _size.x + x # 新纹理位置。
				var uv: Vector2 = (Vector2(x, y) + Vector2(0.5, 0.5)) / Vector2(_size) # 新纹理像素中心。
				var old_at := Vector2i(uv * Vector2(prior_size)) # 在同一地板位置取原像素。
				var mark: Vector2 = prior[old_at.y * prior_size.x + old_at.x] # 原压痕与雪沿。
				if mark != Vector2.ZERO:
					_active.append(index)
					_store(index, mark)
	_image.set_data(_size.x, _size.y, false, Image.FORMAT_RG8, _pixels)
	texture = ImageTexture.create_from_image(_image)
	_texture_dirty = false

## 将 [param shape_to_uv] 变换的拖行/滚动雪槽写入 CPU 细节纹理。
## [param strength] 为雪深调制后的深度，[param span] 为胶囊中心段半长除半径。
func draw_mark(shape_to_uv: Transform2D, strength: float, span: float) -> void:
	if strength <= 0.001:
		return
	var raster := Transform2D(Vector2(_size.x, 0.0), Vector2(0.0, _size.y), Vector2.ZERO) # UV 到细节 texel 的分辨率变换。
	var to_raster: Transform2D = raster * shape_to_uv # 压痕局部坐标到细节纹理。
	var to_shape: Transform2D = to_raster.affine_inverse() # 反向变换便于按像素中心计算轮廓。
	var extent := Vector2(span + 1.12, 1.12) # 形状边缘留亚像素雪沿余量。
	var bounds: Rect2 = to_raster * Rect2(-extent, extent * 2.0) # 当前印迹的像素包围框。
	var start := Vector2i(bounds.position.floor()) # 向外取整后的格首位置。
	var limit := Vector2i(bounds.end.ceil()) # 向外取整后的格尾位置，开区间。
	var clip: Rect2i = Rect2i(start, limit - start).intersection(Rect2i(Vector2i.ZERO, _size)) # 只更新实际地板 UV 范围。
	for y: int in range(clip.position.y, clip.end.y): # 印迹投影下的像素行。
		for x: int in range(clip.position.x, clip.end.x): # 印迹投影下的像素列。
			var local: Vector2 = to_shape * (Vector2(x, y) + Vector2(0.5, 0.5)) # 以像素中心求局部位置。
			var distance: float = Vector2(maxf(0.0, absf(local.x) - span), local.y).length() # 归一化到雪槽边缘的半径。
			if distance >= 1.1:
				continue
			var depth: float = strength * (1.0 - smoothstep(0.59, 0.94, distance)) # 核心压陷柔边，轨迹中心连续。
			var rim: float = strength * 0.63 * smoothstep(0.64, 0.90, distance) * (1.0 - smoothstep(0.92, 1.1, distance)) # 少量推至边缘的浅雪。
			var index: int = y * _size.x + x # 纹理中的压痕样本。
			var prior: Vector2 = _marks[index] # 旧深度与雪沿可盖在同一位置。
			if prior == Vector2.ZERO:
				_active.append(index)
			var merged: Vector2 = prior.max(Vector2(depth, rim)) # 两通道各自只保留更强的印迹。
			if merged != prior:
				_store(index, merged)

## 按 [param delta] 秒和低频 [param refill_rates] 在局部消减压陷并先软化雪沿；提交一次合并后的纹理。
func advance(delta: float, refill_rates: PackedFloat32Array) -> void:
	if _active.is_empty() and not _texture_dirty:
		return
	var kept: int = 0 # 当前仍可见的稀疏索引数，原位压缩以复用缓冲。
	@warning_ignore("integer_division")
	var state_width: int = _size.x / DETAIL_SCALE # 每三列对应一个回填速率值。
	for index: int in _active: # 仅推进仍有压陷或雪沿的格子。
		@warning_ignore("integer_division")
		var row: int = index / _size.x / DETAIL_SCALE # 对齐到低频网格的行坐标。
		@warning_ignore("integer_division")
		var col: int = (index % _size.x) / DETAIL_SCALE # 对齐到低频网格的列坐标。
		var soften: float = refill_rates[row * state_width + col] * delta # 局部降雪和自然松弛在本步内填回的深度。
		var prior: Vector2 = _marks[index] # 回填前的细节强度。
		var mark := Vector2(maxf(0.0, prior.x - soften), maxf(0.0, prior.y - soften * 1.3)) # 雪沿较核心压陷更早消散。
		_store(index, mark)
		if mark != Vector2.ZERO:
			_active[kept] = index
			kept += 1
	_active.resize(kept)
	if _texture_dirty:
		_image.set_data(_size.x, _size.y, false, Image.FORMAT_RG8, _pixels)
		texture.update(_image)
		_texture_dirty = false

## 保存 [param index] 的浮点 [param mark]，同时更新对应的 RG8 数据。
func _store(index: int, mark: Vector2) -> void:
	_marks[index] = mark
	var offset: int = index * 2 # 细节像素的 RG8 双字节位置。
	var depth: int = roundi(mark.x * 255.0) # 量化后的压陷值。
	var rim: int = roundi(mark.y * 255.0) # 量化后的雪沿值。
	_texture_dirty = _texture_dirty or _pixels[offset] != depth or _pixels[offset + 1] != rim
	_pixels[offset] = depth
	_pixels[offset + 1] = rim
