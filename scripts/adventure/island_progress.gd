## 第一阶段独立进度与幂等赠卡；不读写原版全局存档。
extends RefCounted

## 当前状态文件格式，未来升级必须显式迁移。
const VERSION := 1
## 本实例唯一文件路径，可由验收脚本指定隔离路径。
var save_path: String
## 是否已经创建冒险。
var started := false
## 七句引导是否已完成或跳过。
var intro_completed := false
## 第一关是否经过真实胜利结算。
var stage_1_cleared := false
## 临时卡片所有权；每种初始植物只有一份，不是消耗品背包。
var cards: Dictionary = {}
## 最近错误供界面显示，不静默吞掉 IO 错误。
var error_message := ""
## 新游戏创建前保留的上一份文件。
var last_backup_path := ""
## 读取失败时禁止自动保存，避免覆盖损坏或新版文件。
var _write_allowed := true

## [param path] 为版本化状态文件路径。
func _init(path: String) -> void:
	save_path = path

## 读取已知版本；缺失表示尚未开始，损坏文件保持原样并返回 false。
func load_progress() -> bool:
	started = false
	intro_completed = false
	stage_1_cleared = false
	cards = {}
	error_message = ""
	_write_allowed = true
	if not FileAccess.file_exists(save_path):
		return true
	# 先校验全部字段，再一次性恢复运行状态。
	var parser := JSON.new() # 实例解析允许把损坏文件作为可恢复错误处理。
	if parser.parse(FileAccess.get_file_as_string(save_path)) != OK:
		return _invalid_save()
	var data: Variant = parser.data # 完成语法校验的 JSON 数据。
	if not data is Dictionary or data.get("version") != VERSION:
		return _invalid_save()
	for key: String in ["started", "intro_completed", "stage_1_cleared"]: # 必须是布尔字段。
		if not data.get(key) is bool:
			return _invalid_save()
	if not data.get("cards") is Dictionary:
		return _invalid_save()
	if not data.cards.is_empty():
		if data.cards.size() != 2 or data.cards.get("sunflower") != 1 or data.cards.get("peashooter") != 1:
			return _invalid_save()
	if (data.intro_completed or data.stage_1_cleared) and (not data.started or data.cards.is_empty()):
		return _invalid_save()
	started = data.started
	intro_completed = data.intro_completed
	stage_1_cleared = data.stage_1_cleared
	# JSON 将数字读为浮点数；所有权适配层统一恢复为整数计数。
	cards = {} if data.cards.is_empty() else {"sunflower": 1, "peashooter": 1}
	return true

## 仅在文件真正不存在时创建默认进度；保存失败恢复未开始状态，可安全重试。
func initialize_if_missing() -> bool:
	if FileAccess.file_exists(save_path):
		return _write_allowed
	if not _write_allowed or DirAccess.dir_exists_absolute(save_path):
		error_message = "冒险存档路径不可写，未创建进度。"
		return false
	started = true
	if _save():
		return true
	started = false
	return false

## 仅供测试或未来专用管理操作：创建新冒险前备份旧文件，普通入口不可调用。
func start_new() -> bool:
	if FileAccess.file_exists(save_path):
		last_backup_path = save_path + ".backup-%s-%s" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
		if DirAccess.copy_absolute(save_path, last_backup_path) != OK:
			error_message = "无法备份上一份冒险，已保留原进度。"
			return false
	_write_allowed = true
	started = true
	intro_completed = false
	stage_1_cleared = false
	cards = {}
	return _save()

## 第四句与跳过共用的赋值式赠卡；重复调用不会累计数量。
func grant_starter_cards() -> bool:
	if not _write_allowed or not started:
		return false
	cards = {"sunflower": 1, "peashooter": 1}
	return _save()

## 完成和跳过都保证两张卡已经持久化。
func complete_intro() -> bool:
	if not _write_allowed or not started:
		return false
	cards = {"sunflower": 1, "peashooter": 1}
	intro_completed = true
	return _save()

## 仅供战斗适配在已验证胜利后调用；不提供退出或失败解锁入口。
func record_victory() -> bool:
	if not _write_allowed or not started or not intro_completed:
		return false
	stage_1_cleared = true
	return _save()

## 标记无效文件且禁止后续自动覆盖。
func _invalid_save() -> bool:
	_write_allowed = false
	error_message = "冒险存档损坏或版本不兼容，原文件已保留，请检查存档。"
	return false

## 同目录临时写入后替换，降低中途退出损坏进度的风险。
func _save() -> bool:
	if not _write_allowed:
		return false
	if DirAccess.make_dir_recursive_absolute(save_path.get_base_dir()) != OK:
		error_message = "无法创建冒险存档目录。"
		return false
	# 临时文件与目标文件在同一文件系统。
	var file := FileAccess.open(save_path + ".tmp", FileAccess.WRITE)
	if file == null:
		error_message = "无法写入冒险存档。"
		return false
	file.store_string(JSON.stringify({"version": VERSION, "started": started,
		"intro_completed": intro_completed, "stage_1_cleared": stage_1_cleared, "cards": cards}, "\t"))
	file.flush()
	# 关闭前取得写入错误码，失败时不替换原文件。
	var write_error := file.get_error()
	file.close()
	if write_error != OK or DirAccess.rename_absolute(save_path + ".tmp", save_path) != OK:
		error_message = "保存冒险进度失败，请检查磁盘空间与文件权限。"
		return false
	error_message = ""
	return true
