## 场景和模态共用的临时资源请求批次；不拥有业务状态，也不是全局缓存。
## 宿主持有本对象及 resources，直到目标完成构造；所有场景树操作仍由主线程执行。
extends RefCounted

## 限制同时提交的根资源数，避免首次打开页面时大量加载线程争抢主线程。
const MAX_IN_FLIGHT := 2
## 已完成的资源强引用，防止准备与实际构造之间被资源缓存释放。
var resources: Array[Resource] = []
## 去重后的准备清单，只保存路径。
var _paths := PackedStringArray()
## 下一条尚未提交的路径位置。
var _next := 0
## 正在加载的路径及最近一次完成比例。
var _pending: Dictionary[String, float] = {}
## 已完成路径的索引，与 resources 共用相同资源对象。
var _loaded: Dictionary[String, Resource] = {}
## 请求失败后不再提交后续路径，已有请求仍须回收。
var _failed := false
## 取消只终止结果交付，不在游戏帧中同步等待工作线程。
var _cancelled := false

## 提交 [param paths] 的去重清单；非法路径整体拒绝，返回 Godot 错误码。
func start(paths: PackedStringArray) -> Error:
	if not _paths.is_empty() or not _pending.is_empty():
		return ERR_ALREADY_IN_USE
	for path: String in paths: # 先完整校验，避免半个非法请求进入加载。
		if not path.begins_with("res://") or not ResourceLoader.exists(path):
			return ERR_FILE_NOT_FOUND
		if not _paths.has(path):
			_paths.append(path)
	_submit_available()
	return FAILED if _failed else OK

## 每帧查询一次；只有资源已完成才调用 load_threaded_get，不阻塞正常交互。
func poll() -> int:
	for path: String in _pending.keys(): # 使用快照允许完成后删除对应请求。
		var amount: Array = [] # 引擎填入单条请求的完成比例。
		var status: int = ResourceLoader.load_threaded_get_status(path, amount) # 当前资源状态。
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var resource: Resource = ResourceLoader.load_threaded_get(path) # 此时读取不会等待。
			_pending.erase(path)
			if resource == null:
				_failed = true
			else:
				_loaded[path] = resource
				resources.append(resource)
		elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_pending.erase(path)
			_failed = true
		elif not amount.is_empty():
			_pending[path] = clampf(float(amount[0]), 0.0, 1.0)
	_submit_available()
	if not _pending.is_empty():
		return ResourceLoader.THREAD_LOAD_IN_PROGRESS
	if _failed or _cancelled:
		return ResourceLoader.THREAD_LOAD_FAILED
	return ResourceLoader.THREAD_LOAD_LOADED

## 返回整批读取的估计比例；不把它冒充为界面构造或实际可交互进度。
func progress() -> float:
	if _paths.is_empty():
		return 1.0
	var completed := float(_loaded.size()) # 已完成资源和正在加载资源等权计算。
	for amount: float in _pending.values():
		completed += amount
	return completed / float(_paths.size())

## 返回 [param path] 已完成的资源；未完成或不属于本批次时返回 null。
func get_resource(path: String) -> Resource:
	return _loaded.get(path)

## 取消交付并停止提交新任务；宿主继续 poll 回收已提交任务。
func cancel() -> void:
	_cancelled = true

## 返回是否还有引擎线程请求需要轮询回收。
func is_running() -> bool:
	return not _pending.is_empty()

## 仅程序退出或宿主销毁时回收未完成请求；普通取消必须通过 poll 异步回收。
func finish_on_exit() -> void:
	_cancelled = true
	for path: String in _pending.keys(): # 退出时引擎线程不能遗留无人接收的任务。
		var status: int = ResourceLoader.load_threaded_get_status(path) # 不触发新请求。
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS or status == ResourceLoader.THREAD_LOAD_LOADED:
			ResourceLoader.load_threaded_get(path)
	_pending.clear()

## 填充有限的后台请求槽；已缓存资源直接持有，不重复启动线程。
func _submit_available() -> void:
	while not _failed and not _cancelled and _next < _paths.size() and _pending.size() < MAX_IN_FLIGHT:
		var path: String = _paths[_next] # 依赖清单中的下一条根资源。
		_next += 1
		var cached: Resource = ResourceLoader.get_cached_ref(path) # 只取现有引用，不触发加载。
		if cached != null:
			_loaded[path] = cached
			resources.append(cached)
			continue
		var error: Error = ResourceLoader.load_threaded_request(path, "", false) # 根请求后台化，避免额外子线程放大争用。
		if error != OK:
			_failed = true
			push_error("资源请求失败：" + path)
			return
		_pending[path] = 0.0
