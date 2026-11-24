## 保存最近一次可定位的加载断点；不依赖存档、窗口或场景生命周期。
## 阻塞调用之前同步写入，下一次正常启动可识别上次未完成的步骤。
extends RefCounted

## 正在进行的根请求快照文件，与玩家存档完全分离。
const ACTIVE_FILE := "user://load_checkpoint.json"
## 最近的异常或慢资源报告文件；玩家确认后保留复制能力。
const REPORT_FILE := "user://load_diagnostic.json"
## 单资源慢加载的最小耗时，单位真实毫秒。
const SLOW_MSEC := 3_000
## 路径长度上限，杜绝任意大内容被写入日志。
const MAX_PATH_LENGTH := 260
## 最多同时记录的根请求数量。
const MAX_ACTIVE := 8

## 本进程是否已经完成上次加载断点的归档。
static var _initialized := false
## 当前进程所有尚未结束的断点。
static var _active: Dictionary = {}
## 当前进程独立递增的请求身份。
static var _serial := 0
## 保留给玩家复制的最近一次有意义记录。
static var _report: Dictionary = {}

## 在 [param path] 对应的阻塞操作开始之前同步落盘；[param stage] 指明实际阶段。
## 返回本进程内唯一身份；业务在调用返回后应配对 [method finish]。
static func begin(path: String, stage: String) -> int:
	_initialize()
	_serial += 1
	var record: Dictionary = _environment() # 不允许添加用户姓名、存档数据或绝对路径。
	record["path"] = _safe_path(path)
	record["stage"] = stage.left(48)
	record["start_time"] = Time.get_datetime_string_from_system()
	record["start_msec"] = Time.get_ticks_msec()
	record["seq"] = _serial
	if _active.size() >= MAX_ACTIVE:
		_active.erase(_active.keys()[0])
	_active[str(_serial)] = record
	_save_active()
	return _serial

## [param outcome] 支持 ok/failed/timeout/cancelled，只有异常和慢成功会保留报告。
static func finish(id: int, outcome: String = "ok") -> void:
	_initialize()
	var key: String = str(id)
	if not _active.has(key):
		return
	var record: Dictionary = _active[key]
	_active.erase(key)
	var elapsed: int = maxi(0, Time.get_ticks_msec() - int(record.get("start_msec", 0)))
	_save_active()
	if outcome in ["failed", "timeout"] or (outcome == "ok" and elapsed >= SLOW_MSEC):
		record.erase("start_msec") # 跨进程不使用单调计时。
		record["elapsed_msec"] = elapsed
		record["status"] = "slow" if outcome == "ok" else outcome
		_store_report(record)

## 无法获得单条断点时仍可报告整体资源批次失败。
static func note_failure(path: String, stage: String, outcome: String) -> void:
	_initialize()
	var record: Dictionary = _environment()
	record["path"] = _safe_path(path)
	record["stage"] = stage.left(48)
	record["start_time"] = Time.get_datetime_string_from_system()
	record["status"] = outcome
	_store_report(record)

## 只在上次真正存在未完成步骤、失败或超时且玩家尚未确认时提示。
static func has_interruption() -> bool:
	_initialize()
	return str(_report.get("status", "")) in ["interrupted", "failed", "timeout"] and not bool(_report.get("acknowledged", false))

## 设置页允许重复复制包括慢成功在内的历史记录。
static func has_report() -> bool:
	_initialize()
	return not _report.is_empty()

## 玩家已复制后的记录不再反复打扰主菜单，但设置仍可复制。
static func acknowledge() -> void:
	_initialize()
	if _report.is_empty() or bool(_report.get("acknowledged", false)):
		return
	_report["acknowledged"] = true
	_write_json(REPORT_FILE, {"schema":1, "report":_report})

## 返回明确标注未完成不等于崩溃原因的纯文本诊断。
static func report_text() -> String:
	_initialize()
	if _report.is_empty():
		return "暂无加载诊断记录。"
	var status: String = str(_report.get("status", ""))
	var meaning: String = {"interrupted":"上次未记录完成（不等于已确认崩溃）",
		"failed":"资源准备失败", "timeout":"资源准备超时",
		"slow":"资源加载缓慢但已完成"}.get(status, status)
	var elapsed: String = "%d ms" % int(_report.get("elapsed_msec", 0)) if _report.has("elapsed_msec") else "未记录"
	return "PVZ-Adventure 加载诊断\n状态：%s\n版本：%s\n设备：%s / %s\n阶段：%s\n资源：%s\n开始：%s\n耗时：%s" % [
		meaning, _report.get("version", ""), _report.get("platform", ""), _report.get("model", ""),
		_report.get("stage", ""), _report.get("path", ""), _report.get("start_time", ""), elapsed]

## 本进程第一次使用时归档上次活跃资源，防止新会话覆盖旧证据。
static func _initialize() -> void:
	if _initialized:
		return
	_initialized = true
	var previous_report: Dictionary = _read_json(REPORT_FILE)
	var candidate: Variant = previous_report.get("report", {})
	_report = candidate if candidate is Dictionary else {}
	var snapshot: Dictionary = _read_json(ACTIVE_FILE)
	var pending: Variant = snapshot.get("active", {})
	if pending is Dictionary and not pending.is_empty():
		var latest: Dictionary = {}
		for item: Variant in pending.values(): # 按进程内序号而非 JSON 键的排列顺序选取。
			if item is Dictionary and int(item.get("seq", 0)) >= int(latest.get("seq", -1)):
				latest = item.duplicate(true)
		if not latest.is_empty():
			latest.erase("start_msec")
			latest["status"] = "interrupted"
			_store_report(latest)
	_active.clear()
	_save_active()

## 路径只允许 res:// 游戏资源；意外的私人路径不会写入诊断文件。
static func _safe_path(path: String) -> String:
	return path.left(MAX_PATH_LENGTH) if path.begins_with("res://") else "（非项目资源路径，已省略）"

## 生成不包含任何玩家身份或 user:// 真实路径的环境信息。
static func _environment() -> Dictionary:
	return {"version":str(ProjectSettings.get_setting("application/config/version", "unknown")),
		"platform":OS.get_name(), "model":OS.get_model_name()}

## 数据损坏、文件缺失和异常 schema 均不能导致正式游戏加载失败。
static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

## 覆盖当前活跃步骤；单文件最多八条记录，不累积历史。
static func _save_active() -> void:
	_write_json(ACTIVE_FILE, {"schema":1, "active":_active})

## 失败与中断优先于成功慢资源，保留最有价值的诊断信息。
static func _store_report(record: Dictionary) -> void:
	if record.get("status") == "slow" and str(_report.get("status", "")) in ["interrupted", "failed", "timeout"]:
		return
	record["acknowledged"] = false
	_report = record.duplicate(true)
	_write_json(REPORT_FILE, {"schema":1, "report":_report})

## 每次写入立即 flush；文件操作失败时不改变正式加载结果。
static func _write_json(path: String, data: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(data))
	file.flush()
	file.close()
