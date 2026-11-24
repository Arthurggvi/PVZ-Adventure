## 从雪山地板的实际帧读取积雪遮罩和绘制用山脊轮廓。
extends RefCounted
class_name SnowSurfaceMask

## 山脊横向采样上限。只保留一行数据，天空和地板共用。
const RIDGE_COLUMNS: int = 512
## RGB 雪线从黑底到实雪之间的亮度阈值。
const RIDGE_KEY: float = 0.50
## 二分后的原图像素复查范围。雪脊的少量高光可能在阈值附近断开。
const RIDGE_REFINE_ROWS: int = 6

## 读取 [param sprite] 的当前显示帧，保持裁切及翻转，失败时返回空值。
static func read_frame(sprite: Sprite2D) -> Image:
	var source: Image = _texture_image(sprite.texture) # 帧表裁切前的源图，仅配置时读取。
	if source == null:
		return null
	var base: Rect2 = sprite.region_rect if sprite.region_enabled else Rect2(Vector2.ZERO, sprite.texture.get_size()) # 可绘制源区域。
	var frame_size: Vector2 = base.size / Vector2(sprite.hframes, sprite.vframes) # 单帧在源图中的尺寸。
	var frame_rect := Rect2i(Rect2(base.position + Vector2(sprite.frame_coords) * frame_size, frame_size)) # 当前帧像素矩形。
	if not frame_rect.has_area():
		return null
	var result: Image = source.get_region(frame_rect) # 裁切后独立于导入纹理，不修改共享图像。
	if sprite.flip_h:
		result.flip_x()
	if sprite.flip_v:
		result.flip_y()
	return result

## 从 [param frame] 提取实际雪线并按 [param bounds] 映射到世界。[param slope] 提供地表明暗所需的投影高度。
## 高低字节分别存于 RG 与 BA，线性采样后还原雪线、坡面高度。没有连续轮廓时返回空值。
static func read_ridge(frame: Image, bounds: Rect2, slope: MainGameSlope) -> ImageTexture:
	if frame.get_height() < 2 or not bounds.has_area():
		return null
	var columns: int = mini(RIDGE_COLUMNS, frame.get_width()) # 一行连续数据足以覆盖整个世界画幅。
	var samples := Image.create_empty(columns, 1, false, Image.FORMAT_RGBA8) # 避免移动端浮点纹理过滤限制。
	for column: int in range(columns): # 一次采样同时绑定实际雪线和同列坡面高度。
		var u: float = (float(column) + 0.5) / float(columns) # 与 GPU 线性过滤的像素中心对齐。
		var ridge: float = _ridge_y(frame, floori(u * frame.get_width())) # 以原图像素为单位的雪线交点。
		if ridge < 0.0:
			return null
		var world_x: float = bounds.position.x + bounds.size.x * u # 对应实际战场投影。
		var height: float = slope.get_all_slope_y(world_x) if is_instance_valid(slope) else 0.0 # 水平基线以上的屏幕纵向偏移。
		var edge_code: int = roundi(ridge / float(frame.get_height()) * 65535.0) # 雪线在画布高度内的 16 位值。
		var slope_code: int = roundi(clampf(height / bounds.size.y, 0.0, 1.0) * 65535.0) # 归一化的斜面偏移。
		samples.set_pixel(column, 0, Color8(edge_code >> 8, edge_code & 255, slope_code >> 8, slope_code & 255))
	return ImageTexture.create_from_image(samples)

## 在 [param frame] 的 [param x] 列二分黑底到雪面的过渡，返回插值后的像素坐标，缺边界时为 -1。
static func _ridge_y(frame: Image, x: int) -> float:
	var sky: int = 0 # 黑底像素的最近位置。
	var snow: int = frame.get_height() - 1 # 实雪像素的最近位置。
	if _matte(frame.get_pixel(x, sky)) >= RIDGE_KEY or _matte(frame.get_pixel(x, snow)) < RIDGE_KEY:
		return -1.0
	while snow - sky > 1:
		var y: int = (sky + snow) >> 1 # 固定画幅内只检查对数次像素。
		if _matte(frame.get_pixel(x, y)) >= RIDGE_KEY:
			snow = y
		else:
			sky = y
	for y: int in range(maxi(1, snow - RIDGE_REFINE_ROWS), snow): # 短距离复查，恢复雪线薄亮边与底雪之间的间断。
		if _matte(frame.get_pixel(x, y)) >= RIDGE_KEY:
			snow = y
			break
	var upper: float = _matte(frame.get_pixel(x, snow - 1)) # 边界上方像素中心。
	var lower: float = _matte(frame.get_pixel(x, snow)) # 边界下方第一个实雪像素中心。
	var fraction: float = clampf((RIDGE_KEY - upper) / maxf(lower - upper, 0.001), 0.0, 1.0) # 还原两中心之间的交点。
	return float(snow) - 0.5 + fraction

## [param color] 的最大颜色通道乘以原透明度，适用于黑底 RGB 与透明图集。
static func _matte(color: Color) -> float:
	return maxf(color.r, maxf(color.g, color.b)) * color.a

## 展开 [param texture] 的逻辑像素画布，保留 AtlasTexture 裁去的透明边，失败时返回空值。
static func _texture_image(texture: Texture2D) -> Image:
	if texture == null:
		return null
	var atlas: AtlasTexture = texture as AtlasTexture # 图集逻辑画布可能含裁切余量。
	if atlas != null:
		var backing: Image = _texture_image(atlas.atlas) # 展开底层资源，也兼容嵌套图集。
		if backing == null:
			return null
		var region := Rect2i(atlas.region) # 图集需要呈现的像素范围。
		if region.size.x == 0:
			region.size.x = backing.get_width()
		if region.size.y == 0:
			region.size.y = backing.get_height()
		var canvas: Image = Image.create_empty(atlas.get_width(), atlas.get_height(), false, Image.FORMAT_RGBA8) # 裁切余量保留透明。
		backing.convert(Image.FORMAT_RGBA8)
		canvas.blit_rect(backing, region, Vector2i(atlas.margin.position))
		return canvas
	var source: Image = texture.get_image() # 仅在关卡装配时读取，天气帧不做纹理读回。
	if source == null or source.is_empty() or (source.is_compressed() and source.decompress() != OK):
		return null
	return source
