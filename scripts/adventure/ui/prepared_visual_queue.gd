## 窗口拥有的可见预览装配队列；使用共享资源批次，每帧最多装配一个预览。
## 不保存全局资源，不为滚动区外的物品创建卡牌或角色。
extends Node

## 唯一资源请求实现由场景切换与窗口共用。
const ResourceBatch = preload("res://scripts/ui/transitions/resource_load_batch.gd")
## 尚未可见或等待装配的表现任务，目标销毁后自动失效。
var _jobs: Array[Dictionary] = []
## 当前资源批次，窗口退出时由工具栏回收。
var _batch: ResourceBatch
## 当前装配目标和回调。
var _current: Dictionary = {}

## [param target] 为表现容器，[param paths] 为该格实际依赖，[param draw] 只在主线程装配。
func enqueue(target: Control, paths: PackedStringArray, draw: Callable) -> void:
	_jobs.append({"target": weakref(target), "paths": paths, "draw": draw})

## 资源准备和主线程装配按帧推进，旧目标和不可见目标不做工作。
func _process(_delta: float) -> void:
	if _batch != null:
		var status: int = _batch.poll() # 只获取已经完成的资源。
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return
		_complete_current(status)
		return
	for index: int in range(_jobs.size() - 1, -1, -1): # 清理被重绘释放的旧容器。
		if not _valid_target(_job_target(_jobs[index])):
			_jobs.remove_at(index)
	for index: int in _jobs.size(): # 按真实可见范围挑选下一格，不加载后续屏幕的卡面。
		if not _visible_target(_job_target(_jobs[index])):
			continue
		_current = _jobs[index]
		_jobs.remove_at(index)
		_batch = ResourceBatch.new()
		if _batch.start(_current.paths) != OK:
			AdventureToolbar.retire_resource_batch(_batch)
			_batch = null
			_current = {}
		elif not _batch.is_running():
			_complete_current(ResourceLoader.THREAD_LOAD_LOADED) # 已准备的首屏资源无需再人为等待一帧。
		return

## 完成 [param status] 对应的当前任务；每次调用只构造一个预览。
func _complete_current(status: int) -> void:
	var target: Control = _job_target(_current) # 弱引用先解析，列表刷新后的失效节点不会参与类型转换。
	if status == ResourceLoader.THREAD_LOAD_LOADED and _valid_target(target):
		target.set_meta("prepared_visual_resources", _batch.resources.duplicate())
		if _current.draw.is_valid():
			_current.draw.call()
	elif _valid_target(target):
		var message := Label.new() # 失败只影响本格预览，关闭和其他操作仍可用。
		message.text = "预览暂不可用"
		message.mouse_filter = Control.MOUSE_FILTER_IGNORE
		target.add_child(message)
	_batch = null
	_current = {}

## 当前可见范围完成后，窗口即可撤下首次打开的反馈。
func is_content_ready() -> bool:
	if _batch != null and _valid_target(_job_target(_current)) and _visible_target(_job_target(_current)):
		return false
	for job: Dictionary in _jobs:
		if _valid_target(_job_target(job)) and _visible_target(_job_target(job)):
			return false
	return true

## [param job] 只保存弱引用，异步完成后先解析存活对象，再交给类型化绘制接口。
func _job_target(job: Dictionary) -> Control:
	var reference: WeakRef = job.get("target") as WeakRef # 空任务和已释放目标都返回 null。
	return reference.get_ref() as Control if reference != null else null

## [param target] 必须仍属于活动场景树且未等待删除。
func _valid_target(target: Control) -> bool:
	return is_instance_valid(target) and target.is_inside_tree() and not target.is_queued_for_deletion()

## [param target] 与每一级滚动裁剪相交才是首屏内容；准备中的模态允许暂时隐藏根节点。
func _visible_target(target: Control) -> bool:
	if not _valid_target(target):
		return false
	var bounds: Rect2 = target.get_global_rect() # 多级滚动容器的交集决定可见范围。
	var ancestor: Node = target
	while ancestor is Control:
		var control: Control = ancestor # 普通隐藏页签无需准备，工具栏隐藏构造中的窗口除外。
		if not control.visible and not bool(control.get_meta("preparing_modal", false)):
			return false
		if control.clip_contents or control is ScrollContainer:
			bounds = bounds.intersection(control.get_global_rect())
			if not bounds.has_area():
				return false
		ancestor = ancestor.get_parent()
	return bounds.intersects(target.get_viewport_rect())

## 关闭窗口不等待后台线程，回收责任交还持久工具栏。
func _exit_tree() -> void:
	if _batch != null:
		AdventureToolbar.retire_resource_batch(_batch)
		_batch = null
	_jobs.clear()
