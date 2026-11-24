extends RefCounted
## 菜单输入资源的唯一加载入口：正式运行读原生资源，制作目录可读原始像素。
## 受光纹理保留原 RGB，未使用的 alpha 储存同坐标、同采样方式的灰度场。
const RELIGHT_ALPHA_SOURCES := {
	"working_base.png": "maps/spill.png",
	"maps/controls.png": "finish_maps/base_group_emission.png",
}
## 工作目录或res包路径，不持有全局玩家状态。
var root := ""
## 逻辑输入名到原生Texture2D资源的显式映射。
var catalog: Dictionary = {}
## 每宿主只加载一次相同贴图；宿主释放时随引用归零。
var cache: Dictionary = {}

## [param folder] 为制作或正式资源根目录；缺失或无效目录返回空字典。
static func read_catalog(folder: String) -> Dictionary:
	var path := folder.path_join("texture_catalog.json") # 制作源可没有运行期映射。
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) # 正式映射必须是对象。
	return parsed if parsed is Dictionary else {}

## [param folder] 和 [param key] 定位制作 PNG。预览与发布共用通道布局；尺寸不匹配时返回空值。
static func load_source_image(folder: String, key: String) -> Image:
	var color := Image.load_from_file(folder.path_join(key)) # 普通 RGB、灰度和预乘 PNG 保持原格式。
	var mask_key: String = RELIGHT_ALPHA_SOURCES.get(key, "") # 只有两个受光输入拥有可复用通道。
	if mask_key.is_empty() or color == null or color.is_empty():
		return color
	var mask := Image.load_from_file(folder.path_join(mask_key)) # 旧材质读取灰度场的 R 分量。
	if mask == null or mask.is_empty() or mask.get_size() != color.get_size():
		push_error("城镇受光蒙版缺失或尺寸不一致：" + mask_key)
		return null
	color.convert(Image.FORMAT_RGBA8)
	mask.convert(Image.FORMAT_RGBA8)
	var pixels := color.get_data() # 原 RGB 字节保持不变。
	var mask_pixels := mask.get_data() # 只复制 R 字节，保留旧材质的采样语义。
	for red_offset: int in range(0, pixels.size(), 4): # 对应同一像素的 RGBA 起始字节。
		pixels[red_offset + 3] = mask_pixels[red_offset]
	return Image.create_from_data(color.get_width(), color.get_height(), false, Image.FORMAT_RGBA8, pixels)

## [param folder] 包含config和可选texture_catalog.json；设置后不可换根复用旧缓存。
func configure(folder: String) -> void:
	root=folder.trim_suffix("/")
	cache.clear()
	catalog=read_catalog(root)
	assert(not root.begins_with("res://") or not catalog.is_empty(),"Runtime menu pack missing catalog")

## [param path] 为逻辑图片路径，返回已缓存Texture2D；无额外颜色转换。
func texture(path: String) -> Texture2D:
	if cache.has(path):
		return cache[path]
	var key := path.trim_prefix(root+"/") # 相对母图工作根的稳定名称。
	var result: Texture2D # 正式资源或制作侧原始图片。
	if not catalog.is_empty():
		assert(catalog.has(key),"Menu asset absent: "+key)
		result=load(root.path_join(catalog[key])) as Texture2D
	else:
		var source := load_source_image(root, key) # 制作预览按正式发布布局读取 PNG。
		assert(source!=null and not source.is_empty(),path)
		result=ImageTexture.create_from_image(source)
	assert(result!=null,path)
	cache[path]=result
	return result

## [param path] 为小端RGBA32F原始场；正式包已无损转换为原生ImageTexture。
func floating(path: String, size: Vector2i) -> Texture2D:
	if not catalog.is_empty() or cache.has(path):
		return texture(path)
	var bytes := FileAccess.get_file_as_bytes(path) # 保留32位浮点与透明预乘值。
	assert(bytes.size()==size.x*size.y*16,path)
	var image := Image.create_from_data(size.x,size.y,false,Image.FORMAT_RGBAF,bytes) # 数值不是sRGB颜色。
	var result := ImageTexture.create_from_image(image) # 同一纹理供多个材质共享。
	cache[path]=result
	return result
