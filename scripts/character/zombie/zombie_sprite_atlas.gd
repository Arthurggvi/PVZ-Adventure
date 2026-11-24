## 逐步合并同一僵尸外观的分件。现有实例的动画轨道共享可换底图的同尺寸切片。
extends RefCounted
class_name ZombieSpriteAtlas

## 角色小分件之外的大图保存原材质，单位为像素。
const MAX_PART_EDGE := 384
## 每张运行时图集允许的最大边长，单位为像素。
const MAX_ATLAS_EDGE := 1024
## 为线性过滤预留一圈边缘像素。
const BORDER := Vector2i.ONE

## 完成后的 RGBA8 纹理字节数。
var bytes := 0
## 原纹理到切片的映射，打包前先指向原纹理。
var textures: Dictionary = {}

## 等待读取像素的贴图，按编译顺序一次读取一张。
var _pending: Array[Texture2D] = []
## 成功解码的源纹理，顺序对应 [member _images] 与 [member _points]。
var _sources: Array[Texture2D] = []
## 按需解码的源图，上传后立即释放。
var _images: Array[Image] = []
## 包含采样边缘的分件尺寸。
var _sizes := PackedVector2Array()
## 已解码分件占用的理论像素数，超额可提前退出。
var _pixels := 0
## 各分件在图集里的左上角，包含预留边缘。
var _points := PackedVector2Array()
## 上传前按块填充的图集像素。
var _sheet: Image
## 上传后由现有切片共享的显存纹理。
var _atlas: ImageTexture
## 已放入当前图集的分件数。
var _blitted := 0
## 已切换为图集的分件数。
var _bound := 0


## 为 [param parts] 中的合格小分件建立等尺寸切片，保留现有绘制。
## 只准备引用，不从显存读取像素。
func prepare(parts: Dictionary) -> void:
	for source: Texture2D in parts: # 去重表保证每张纹理只准备一次。
		var size := Vector2i(source.get_size()) # 原有区域大小，用于保留动画关键帧及视觉偏移。
		if size.x <= 0 or size.y <= 0 or size.x > MAX_PART_EDGE or size.y > MAX_PART_EDGE:
			continue
		if not source is CompressedTexture2D and not source is ImageTexture and not source is AtlasTexture:
			continue
		var part := AtlasTexture.new() # 原尺寸的代理，后续切换时不重启动画。
		if source is AtlasTexture:
			if source.margin != Rect2() or source.atlas == null or source.atlas is AtlasTexture:
				continue
			part.atlas = source.atlas
			part.region = source.region
			part.filter_clip = source.filter_clip
		else:
			part.atlas = source
			part.region = Rect2(Vector2.ZERO, Vector2(size))
		textures[source] = part
		_pending.append(source)
	if _pending.size() < 2:
		_pending.clear()
		textures.clear()


## 推进一个分件大小的工作。完成或超出 [param byte_budget] 时返回 true。
## 放弃打包时切片仍引用原美术，可安全由现有动画使用。
func advance(byte_budget: int) -> bool:
	if _pending.is_empty() and _images.is_empty() and _atlas == null:
		return true
	if not _pending.is_empty():
		_decode(_pending.pop_back())
		return _pixels * 4 > byte_budget
	if _sheet == null and _atlas == null and not _allocate_sheet(byte_budget):
		return true
	if _blitted < _images.size():
		_blit_with_border(_sheet, _images[_blitted], Vector2i(_points[_blitted]) + BORDER)
		_blitted += 1
		if _blitted < _images.size():
			return false
	if _atlas == null:
		_atlas = ImageTexture.create_from_image(_sheet)
		_sheet = null
		_images.clear()
		return false
	var part: AtlasTexture = textures[_sources[_bound]] # 同一分件所有已入场的引用一起更新。
	part.atlas = _atlas
	part.region = Rect2(_points[_bound] + Vector2.ONE, _sizes[_bound] - Vector2(2, 2))
	part.filter_clip = true
	_bound += 1
	return _bound >= _sources.size()


## 解码一张 [param source]，跳过无法得到完整像素的分件。
func _decode(source: Texture2D) -> void:
	var image: Image = source.get_image() # 图形后端可能同步读回，按单个分件控制每帧工作。
	if image == null or image.get_size() != Vector2i(source.get_size()) \
			or (image.is_compressed() and image.decompress() != OK):
		return
	image.convert(Image.FORMAT_RGBA8)
	var padded: Vector2i = image.get_size() + 2 * BORDER # 为滤镜区分相邻小图。
	_pixels += padded.x * padded.y
	_sources.append(source)
	_images.append(image)
	_sizes.append(Vector2(padded))


## [param byte_budget] 为本场剩余显存额度，成功时只分配一张图集的工作图。
func _allocate_sheet(byte_budget: int) -> bool:
	if _images.size() < 2:
		return false
	var layout: Dictionary = Geometry2D.make_atlas(_sizes) # 引擎计算互不重叠的分件区域。
	var size := Vector2i(layout["size"]) # 图集实际大小可能稍大于各分件之和。
	if size.x > MAX_ATLAS_EDGE or size.y > MAX_ATLAS_EDGE or size.x * size.y * 4 > byte_budget:
		return false
	bytes = size.x * size.y * 4
	_points = layout["points"]
	_sheet = Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	return true


## 将 [param source] 贴到 [param target] 的 [param origin]，扩展各边一像素防止线性采样串色。
func _blit_with_border(target: Image, source: Image, origin: Vector2i) -> void:
	var size: Vector2i = source.get_size() # 当前分件有效像素。
	target.blit_rect(source, Rect2i(Vector2i.ZERO, size), origin)
	target.blit_rect(source, Rect2i(0, 0, 1, size.y), origin - Vector2i(1, 0))
	target.blit_rect(source, Rect2i(size.x - 1, 0, 1, size.y), origin + Vector2i(size.x, 0))
	target.blit_rect(source, Rect2i(0, 0, size.x, 1), origin - Vector2i(0, 1))
	target.blit_rect(source, Rect2i(0, size.y - 1, size.x, 1), origin + Vector2i(0, size.y))
	target.set_pixelv(origin - BORDER, source.get_pixel(0, 0))
	target.set_pixelv(origin + Vector2i(size.x, -1), source.get_pixel(size.x - 1, 0))
	target.set_pixelv(origin + Vector2i(-1, size.y), source.get_pixel(0, size.y - 1))
	target.set_pixelv(origin + size, source.get_pixelv(size - BORDER))
