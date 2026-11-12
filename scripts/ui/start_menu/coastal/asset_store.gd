extends RefCounted
## 菜单输入资源的唯一加载入口：正式运行读原生资源，制作目录可读原始像素。
## 工作目录或res包路径，不持有全局玩家状态。
var root := ""
## 逻辑输入名到原生Texture2D资源的显式映射。
var catalog: Dictionary = {}
## 每宿主只加载一次相同贴图；宿主释放时随引用归零。
var cache: Dictionary = {}

## [param folder] 包含config和可选texture_catalog.json；设置后不可换根复用旧缓存。
func configure(folder: String) -> void:
	root=folder.trim_suffix("/")
	cache.clear()
	catalog.clear()
	var path := root.path_join("texture_catalog.json") # 正式发布包的映射。
	if FileAccess.file_exists(path):
		catalog=JSON.parse_string(FileAccess.get_file_as_string(path))
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
		var source := Image.load_from_file(path) # 仅离线制作输入使用原PNG。
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
