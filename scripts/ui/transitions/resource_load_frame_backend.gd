## Android 专用的分帧加载后端；不创建 Godot 原生线程请求。
## 每个渲染帧最多执行一次同步根资源加载，不能中断单次 ResourceLoader.load()。
extends RefCounted

## 同步阻塞前落盘的唯一断点记录器。
const Checkpoint = preload("res://scripts/ui/transitions/resource_load_checkpoint.gd")
## 所有并行批次共用的帧闸门，避免同一帧多次进行同步磁盘加载。
static var _last_load_frame := -1

## 批次实际需要处理的资源数量，进度仅表示资源准备。
var _total := 0
## 尚未处理的资源路径。
var _queue := PackedStringArray()
## 下一条待处理资源的索引。
var _next := 0
## 已完成资源与对应路径的关联。
var _loaded: Dictionary[String, Resource] = {}
## 已完成资源的强引用，随批次交付给调用方。
var resources: Array[Resource] = []
## 后端是否发生不可恢复的资源错误。
var _failed := false

## 接收已验证、去重的 [param paths]，仅读取现有缓存，不在调用帧同步加载。
func start(paths: PackedStringArray) -> Error:
	_total = paths.size()
	for path: String in paths:
		var cached: Resource = ResourceLoader.get_cached_ref(path) # 命中引擎缓存不触发磁盘读取。
		if cached != null:
			_loaded[path] = cached
			resources.append(cached)
		else:
			_queue.append(path)
	return OK

## 每次至多完成一个未缓存的根资源，过长的单次加载只能在返回后检测失败。
func poll() -> int:
	if _failed:
		return ResourceLoader.THREAD_LOAD_FAILED
	if not is_running():
		return ResourceLoader.THREAD_LOAD_LOADED
	var frame: int = Engine.get_process_frames() # 全部 Android 批次共享一次同步加载额度。
	if _last_load_frame == frame:
		return ResourceLoader.THREAD_LOAD_IN_PROGRESS
	_last_load_frame = frame
	var path: String = _queue[_next]
	var token: int = Checkpoint.begin(path, "同步读取资源") # 在潜在阻塞前 flush，以供下次启动诊断。
	var resource: Resource = ResourceLoader.load(path) # Android 不调用 load_threaded_request/get。
	Checkpoint.finish(token, "ok" if resource != null else "failed")
	if resource == null:
		push_warning("Android 资源无法加载：" + path)
		_failed = true
		return ResourceLoader.THREAD_LOAD_FAILED
	_loaded[path] = resource
	resources.append(resource)
	_next += 1
	return ResourceLoader.THREAD_LOAD_IN_PROGRESS if is_running() else ResourceLoader.THREAD_LOAD_LOADED

## Android 加载是单次同步操作，跨帧等待队列并不等于正在加载某个资源。
func active_load() -> Dictionary:
	return {}

## 当前批次是否还有待处理的根资源。
func is_running() -> bool:
	return not _failed and _next < _queue.size()

## 只报告本批次已完成的资源比例。
func progress() -> float:
	return 1.0 if _total == 0 else float(_loaded.size()) / float(_total)

## 返回当前未缓存资源的路径，供业务超时日志明确定位。
func active_path() -> String:
	return _queue[_next] if is_running() else ""

## 只返回本批次实际已加载的资源。
func get_resource(path: String) -> Resource:
	return _loaded.get(path)

## 同步结束业务交付；没有后台任务需要额外轮询或回收。
func abandon() -> void:
	_failed = true
	_queue.clear()
	_next = 0
	_loaded.clear()
	resources.clear()
