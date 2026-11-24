## 桌面平台的后台加载后端；独立批次共享在途句柄，不缓存完成的资源。
## 取消与超时只撤销业务观察者，不会假称能终止 Godot 内部线程。
extends RefCounted
## 与 Android 共用的轻量加载断点记录，不保存任何玩家信息。
const Checkpoint = preload("res://scripts/ui/transitions/resource_load_checkpoint.gd")
## 所有请求仅保存路径、观察者和原生状态。
const NativeRequest = preload("res://scripts/ui/transitions/resource_load_native_request.gd")
## 单个批次同时等待的最大根资源数。
const MAX_IN_FLIGHT := 2
## 单条请求连续无进展时的停滞上限，单位真实毫秒。
const STALL_MSEC := 20_000
## 无观察者的请求低频回收间隔，单位真实秒。
const REAP_SECONDS := 0.25
## 无观察者的回收最多尝试次数，超过后隔离句柄而不无限注册定时器。
const MAX_REAP_PASSES := 20
## 当前仍受引擎管理的共享请求；终态及时移除，隔离项不重新提交。
static var _active: Dictionary[String, NativeRequest] = {}
## 本批次成功加载的资源强引用。
var resources: Array[Resource] = []
## 待处理路径按原始顺序提交。
var _paths := PackedStringArray()
## 下一条尚未提交的路径索引。
var _next := 0
## 当前批次仍在等待的共享请求。
var _pending: Dictionary[String, NativeRequest] = {}
## 已完成资源按路径索引。
var _loaded: Dictionary[String, Resource] = {}
## 发生任何资源失败后立即停止提交新任务。
var _failed := false

## 接收已去重的 [param paths]，利用引擎缓存并最多提交两条原生请求。
func start(paths: PackedStringArray) -> Error:
	_paths = paths
	return _fill_slots()

## 每帧查询共享状态；只有引擎确认完成才取得对应资源。
func poll() -> int:
	if _failed:
		return ResourceLoader.THREAD_LOAD_FAILED
	for path: String in _pending.keys():
		var request: NativeRequest = _pending[path]
		_refresh(request)
		if request.status == ResourceLoader.THREAD_LOAD_IN_PROGRESS and not request.quarantined:
			continue
		_pending.erase(path)
		request.observers = maxi(0, request.observers - 1)
		if request.resource != null:
			_retain(path, request.resource)
		else:
			_failed = true
	if _failed or _fill_slots() != OK:
		abandon()
		return ResourceLoader.THREAD_LOAD_FAILED
	return ResourceLoader.THREAD_LOAD_IN_PROGRESS if is_running() else ResourceLoader.THREAD_LOAD_LOADED
## 返回本批次尚有未提交或正在等待的路径。
func is_running() -> bool:
	return not _failed and (_next < _paths.size() or not _pending.is_empty())

## 把尚在加载的比例计入估计进度，不把它当作场景构造进度。
func progress() -> float:
	if _paths.is_empty():
		return 1.0
	var amount: float = float(_loaded.size())
	for request: NativeRequest in _pending.values():
		amount += request.progress
	return clampf(amount / float(_paths.size()), 0.0, 1.0)

## 只报告当前最早开始加载的有效资源，三秒门槛按单个请求计算。
func active_load() -> Dictionary:
	var chosen: NativeRequest
	for request: NativeRequest in _pending.values():
		if not request.quarantined and (chosen == null or request.started_msec < chosen.started_msec):
			chosen = request
	return {"path":chosen.path, "elapsed_msec":maxi(0, Time.get_ticks_msec() - chosen.started_msec)} if chosen != null else {}
## 返回当前等待的原生资源路径，供失败日志识别停滞对象。
func active_path() -> String:
	if not _pending.is_empty():
		return _pending.keys()[0]
	return _paths[_next] if _next < _paths.size() else ""

## 返回本批次确认完成并仍然持有的指定资源。
func get_resource(path: String) -> Resource:
	return _loaded.get(path)

## 撤销业务资格；[param reason] 只用于断点结果，不改变 Godot 原生请求生命周期。
func abandon(reason: String = "cancelled") -> void:
	_failed = true
	_next = _paths.size()
	for request: NativeRequest in _pending.values():
		request.observers = maxi(0, request.observers - 1)
		if request.observers == 0 and request.status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			if request.checkpoint_id > 0:
				Checkpoint.finish(request.checkpoint_id, reason)
				request.checkpoint_id = 0
			_begin_reap(request)
	_pending.clear()
	resources.clear()
	_loaded.clear()
## 填充本批次的有限请求槽；引擎已缓存的资源不占请求槽。
func _fill_slots() -> Error:
	while not _failed and _next < _paths.size() and _pending.size() < MAX_IN_FLIGHT:
		var path: String = _paths[_next]
		_next += 1
		var cached: Resource = ResourceLoader.get_cached_ref(path)
		if cached != null:
			_retain(path, cached)
			continue
		var request: NativeRequest = _active.get(path)
		if request != null:
			_refresh(request) # 先检查历史句柄是否已经结束，再判断能否复用。
		if request == null:
			var token: int = Checkpoint.begin(path, "后台读取资源")
			var result: Error = ResourceLoader.load_threaded_request(path, "", false)
			if result != OK:
				Checkpoint.finish(token, "failed")
				push_warning("后台请求提交失败：" + path)
				_failed = true
				return result
			request = NativeRequest.new()
			request.path = path
			request.checkpoint_id = token
			_active[path] = request
		if request.resource != null:
			_retain(path, request.resource)
		elif request.quarantined or request.status != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			push_warning("资源线程请求不可复用：" + path)
			_failed = true
			return FAILED
		else:
			if request.checkpoint_id == 0: # 之前已取消的健康请求恢复观察时重新记录断点。
				request.checkpoint_id = Checkpoint.begin(path, "后台读取资源")
			request.observers += 1
			_pending[path] = request
	return OK

## 保存单次成功结果，强引用由调用方在窗口或场景交接后继续持有。
func _retain(path: String, resource: Resource) -> void:
	if _loaded.has(path):
		return
	_loaded[path] = resource
	resources.append(resource)

## 每帧最多查询一次原生状态，只有 LOADED 才调用可能同步等待的 get。
static func _refresh(request: NativeRequest) -> void:
	if request.status != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	var frame: int = Engine.get_process_frames()
	if request.polled_frame == frame:
		return
	request.polled_frame = frame
	var amount: Array = []
	request.status = ResourceLoader.load_threaded_get_status(request.path, amount)
	if request.status != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		_active.erase(request.path)
		if request.status == ResourceLoader.THREAD_LOAD_LOADED:
			request.resource = ResourceLoader.load_threaded_get(request.path)
		if request.checkpoint_id > 0:
			Checkpoint.finish(request.checkpoint_id, "ok" if request.resource != null else "failed")
			request.checkpoint_id = 0
		return
	var now: int = Time.get_ticks_msec()
	if not amount.is_empty() and float(amount[0]) > request.progress:
		request.progress = clampf(float(amount[0]), 0.0, 1.0)
		request.advanced_at_msec = now
	if now - request.advanced_at_msec >= STALL_MSEC and not request.quarantined:
		request.quarantined = true
		if request.checkpoint_id > 0:
			Checkpoint.finish(request.checkpoint_id, "timeout")
			request.checkpoint_id = 0
		push_warning("资源线程长时间无进展，隔离请求：" + request.path)
## 第一个观察者退出后才开始低频回收；新的观察者可继续复用健康请求。
static func _begin_reap(request: NativeRequest) -> void:
	if request.reaping or request.quarantined:
		return
	request.reaping = true
	request.reap_passes = 0
	_schedule_reap(request)

## 用主场景树计时器回收原生句柄，不依附已离场窗口。
static func _schedule_reap(request: NativeRequest) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.create_timer(REAP_SECONDS, true, false, true).timeout.connect(_reap.bind(request))

## 有界检查：结束即释放；仍卡死则隔离，不再无限安排计时器。
static func _reap(request: NativeRequest) -> void:
	if request.observers > 0 or request.status != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		request.reaping = false
		return
	_refresh(request)
	if request.status != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		request.reaping = false
		return
	request.reap_passes += 1
	if request.quarantined or request.reap_passes >= MAX_REAP_PASSES:
		request.quarantined = true
		request.reaping = false
		return
	_schedule_reap(request)
