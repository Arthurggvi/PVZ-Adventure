## 苍穹公爵单个实例的图集页缓存。只保存当前播放窗口和即将切入的窗口。
extends RefCounted

## 沿用桌面线程、Android 分帧的共同资源加载入口。
const Batch = preload("res://scripts/ui/transitions/resource_load_batch.gd")

## 仍在播放窗口中的页纹理；移出窗口即交还引用。
var _textures: Dictionary[String, Texture2D] = {}
## 本场已失败的路径，避免每渲染帧重复提交同一缺失资源。
var _failed: Dictionary[String, bool] = {}
## 正在读取的单页批次；任一时刻至多推进一次分帧读取。
var _batch: Batch
## 批次当前请求的资源路径，空串表示没有在途请求。
var _loading_path := ""


## 每帧更新 [param wanted] 内的页；列表前项优先，已失效的结果不会交给播放器。
func update(wanted: Array[String]) -> void:
	for path: String in _textures.keys(): # 已离开播放窗口的页可立即放手。
		if not wanted.has(path):
			_textures.erase(path)
	if _batch != null:
		if wanted.has(_loading_path):
			var status: int = _batch.poll() # Android 本帧至多在这里解码一页。
			if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				return
			var page := _batch.get_resource(_loading_path) as Texture2D # 只读取已确认完成的资源。
			if status == ResourceLoader.THREAD_LOAD_LOADED and page != null:
				_textures[_loading_path] = page
			else:
				_fail(_loading_path)
		_cancel_request()
	for path: String in wanted: # 先补当前应显示的页，再预取后续页。
		if _textures.has(path) or _failed.has(path):
			continue
		_batch = Batch.new()
		_loading_path = path
		if _batch.start(PackedStringArray([path])) != OK:
			_fail(path)
			_cancel_request()
		return


## 返回 [param path] 的已就绪纹理，未就绪时返回 null，不进行磁盘读取。
func texture(path: String) -> Texture2D:
	return _textures.get(path)


## [param paths] 的任一必要页已经失败时返回 true，可安全放弃排队的动作。
func has_failed(paths: Array[String]) -> bool:
	for path: String in paths: # 只检查本次切换涉及的必要页。
		if _failed.has(path):
			return true
	return false


## [param paths] 全部已就绪时返回 true；空窗口没有可以启动的动作。
func is_ready(paths: Array[String]) -> bool:
	if paths.is_empty():
		return false
	for path: String in paths: # 起手和切换均须提前取得采样页。
		if not _textures.has(path):
			return false
	return true


## 退出、死亡或传送完成时撤销所有正在等待的页，并释放驻留页。
func clear() -> void:
	_cancel_request()
	_textures.clear()


## [param path] 为无法加载的图集页。每页只记录一次失败。
func _fail(path: String) -> void:
	_failed[path] = true
	push_warning("苍穹公爵图集页不可用：" + path)


## 取消当前批次的交付资格，底层请求由加载器回收。
func _cancel_request() -> void:
	if _batch != null:
		_batch.abandon()
	_batch = null
	_loading_path = ""
