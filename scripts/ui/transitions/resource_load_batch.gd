## 全部场景和窗口唯一使用的临时资源批次门面。
## Android 分帧同步读取，桌面有限线程读取；调用方无需知道平台差异。
extends RefCounted

## 不依赖场景、美术或玩家状态的 Android 后端。
const FrameBackend = preload("res://scripts/ui/transitions/resource_load_frame_backend.gd")
## 只在非 Android 平台运行的原生线程后端。
const ThreadBackend = preload("res://scripts/ui/transitions/resource_load_threaded_backend.gd")
## 只记录批次错误，不存储资源实体或玩家档案。
const Checkpoint = preload("res://scripts/ui/transitions/resource_load_checkpoint.gd")
## 场景切换默认的完整批次期限，单位真实毫秒。
const DEFAULT_TIMEOUT_MSEC := 45_000

## 本批次交付的全部资源强引用，窗口或目标场景负责接续持有。
var resources: Array[Resource] = []
## 当前平台的实际后端；可在验证脚本中显式选择分帧后端。
var _backend
## 是否已调用过 start，禁止再次重复提交。
var _started := false
## 整批资源进入的最终状态；与 Godot 原有 THREADED 状态值兼容。
var _status := ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
## 本次批次的单调时间截止点，避免每条资源微小进度重置期限。
var _deadline_msec := 0
## 去重后路径集合，只用于失败定位，不保留全局缓存。
var _paths := PackedStringArray()

## [param force_frame_backend] 仅供跨平台验收强制执行 Android 同步分帧策略。
func _init(force_frame_backend: bool = false) -> void:
	_backend = FrameBackend.new() if OS.has_feature("android") or force_frame_backend else ThreadBackend.new()

## 提交去重后的 [param paths]；[param timeout_msec] 是整个批次的业务期限。
## start 只提交请求或命中缓存，不在 Android 点击回调里同步读取文件。
func start(paths: PackedStringArray, timeout_msec: int = DEFAULT_TIMEOUT_MSEC) -> Error:
	if _started:
		return ERR_ALREADY_IN_USE
	_started = true
	for path: String in paths: # 校验完成前不得向任何后端提交部分资源。
		if not path.begins_with("res://") or not ResourceLoader.exists(path):
			Checkpoint.note_failure(path, "资源路径校验", "failed")
			push_warning("资源准备路径缺失：" + path)
			_status = ResourceLoader.THREAD_LOAD_FAILED
			return ERR_FILE_NOT_FOUND
		if not _paths.has(path):
			_paths.append(path)
	_deadline_msec = Time.get_ticks_msec() + maxi(1, timeout_msec)
	var result: Error = _backend.start(_paths)
	if result != OK:
		_backend.abandon()
		_status = ResourceLoader.THREAD_LOAD_FAILED
		return result
	_status = ResourceLoader.THREAD_LOAD_IN_PROGRESS if _backend.is_running() else ResourceLoader.THREAD_LOAD_LOADED
	_copy_resources()
	return OK

## 每帧驱动一次加载；超时和失败统一撤销交付，不等待无法取消的原生线程。
func poll() -> int:
	if _status != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return _status
	if Time.get_ticks_msec() >= _deadline_msec:
		_timeout()
		return _status
	var outcome: int = _backend.poll() # Android 单帧最多一项，桌面仅查询线程终态。
	if Time.get_ticks_msec() >= _deadline_msec and outcome == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		_timeout()
		return _status
	if outcome == ResourceLoader.THREAD_LOAD_LOADED:
		_status = outcome
		_copy_resources()
	elif outcome != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		_status = ResourceLoader.THREAD_LOAD_FAILED
		_backend.abandon()
		resources.clear()
	return _status

## 只返回实际准备完成的比例，未构造的窗口和战场不计入此进度。
func progress() -> float:
	return _backend.progress() if _started else 0.0

## 当前真正执行中的资源活动，仅用于三秒后可选的文字提示。
func activity() -> Dictionary:
	return _backend.active_load() if is_running() else {}

## 返回当前批次已准备的 [param path]，不可触发新的同步加载。
func get_resource(path: String) -> Resource:
	return _backend.get_resource(path)

## 取消将立即结束业务状态；Godot 底层线程由后端有限回收。
func cancel() -> void:
	abandon()

## 返回业务层仍然需要继续轮询的状态，非底层线程是否已经真实终止。
func is_running() -> bool:
	return _status == ResourceLoader.THREAD_LOAD_IN_PROGRESS

## 释放结果并终止当前批次，不阻塞当前帧或把旧结果交给下个窗口。
func abandon() -> void:
	_status = ResourceLoader.THREAD_LOAD_FAILED # 已完成但尚未交付的请求也必须撤销发布资格。
	_backend.abandon()
	resources.clear()

## 将后端已有资源同步到唯一公共数组，避免跨后端类型差异。
func _copy_resources() -> void:
	resources.clear()
	for resource: Resource in _backend.resources:
		resources.append(resource)

## 超时记录正在等待的路径，仅释放业务请求；不谎称原生线程已终止。
func _timeout() -> void:
	var path: String = _backend.active_path()
	Checkpoint.note_failure(path, "批次超时（路径可能是下一待处理项）", "timeout")
	push_warning("资源批次超时 [%s] %s，已完成 %.1f%%" % [OS.get_name(), path, _backend.progress() * 100.0])
	abandon()
