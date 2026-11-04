## 用户档案路径与索引的唯一管理器，保存失败时不发布档案切换事件。
extends Node
class_name UserManager

signal signal_users_update
signal signal_user_renamed(old_name: String, new_name: String)

var curr_user_name: String = ""
var all_user_name: Array[String] = []
const CURRENT_USER_CONFIG_PATH := "user://current_user.ini"
const _RESERVED: Array[String] = ["CON", "PRN", "AUX", "NUL", "COM1", "COM2",
	"COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
	"LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"]

static func is_valid_user_name(name: String) -> bool:
	if name.is_empty() or name.length() > 64 or name.strip_edges() != name:
		return false
	if name.begins_with(".") or name.ends_with(".") or name.contains(".."):
		return false
	for char: String in name:
		if char.unicode_at(0) < 32 or char in "/\\:*?\"<>|":
			return false
	return not _RESERVED.has(name.get_slice(".", 0).to_upper())

static func _user_directory(name: String) -> String:
	return "user://" + name if is_valid_user_name(name) else ""

func load_current_user() -> bool:
	var config := ConfigFile.new()
	if config.load(CURRENT_USER_CONFIG_PATH) != OK:
		curr_user_name = ""
		all_user_name.clear()
		return false
	all_user_name.clear()
	var stored: Variant = config.get_value("user", "all_user", [])
	if not stored is Array:
		return false
	for value: Variant in stored:
		if value is String and is_valid_user_name(value) and not all_user_name.has(value):
			all_user_name.append(value)
	var candidate: String = str(config.get_value("user", "current_user", ""))
	curr_user_name = candidate if all_user_name.has(candidate) else ""
	return true

func save_user_names() -> bool:
	var config := ConfigFile.new()
	config.set_value("user", "current_user", curr_user_name)
	config.set_value("user", "all_user", all_user_name)
	var code: Error = config.save(CURRENT_USER_CONFIG_PATH)
	if code != OK:
		push_error("保存用户索引失败：" + str(code))
	return code == OK

func set_current_user(user_name: String) -> bool:
	if not is_valid_user_name(user_name) or not all_user_name.has(user_name):
		return false
	var previous: String = curr_user_name
	curr_user_name = user_name
	if not save_user_names():
		curr_user_name = previous
		return false
	signal_users_update.emit()
	return true

func ensure_save_directory_exists(user_name: String) -> bool:
	var directory: String = _user_directory(user_name)
	if directory.is_empty():
		return false
	var path: String = directory.path_join(SaveService.MAIN_GAME_SAVE_DIR_NAME)
	return DirAccess.dir_exists_absolute(path) or DirAccess.make_dir_recursive_absolute(path) == OK

func add_user(new_user_name: String) -> String:
	var name: String = new_user_name.strip_edges()
	if not is_valid_user_name(name):
		return "用户名包含无效字符、路径符号或保留名称"
	if all_user_name.has(name) or DirAccess.dir_exists_absolute(_user_directory(name)):
		return "用户已存在"
	if not ensure_save_directory_exists(name):
		return "无法创建用户存档目录"
	all_user_name.append(name)
	if not save_user_names():
		all_user_name.erase(name)
		return "无法保存用户索引"
	signal_users_update.emit()
	return ""

## 先隔离待删目录，再持久化用户索引；索引失败时恢复目录。
func delete_user(user_name: String) -> String:
	if not is_valid_user_name(user_name) or not all_user_name.has(user_name):
		return "用户不存在或用户名不合法"
	if user_name == curr_user_name:
		return "不能删除当前登录用户"
	var source: String = _user_directory(user_name)
	var quarantine: String = "user://__deleted_%d" % Time.get_ticks_usec()
	var moved: bool = DirAccess.dir_exists_absolute(source)
	if moved and DirAccess.rename_absolute(source, quarantine) != OK:
		return "无法保护性迁移待删除存档目录"
	var position: int = all_user_name.find(user_name)
	all_user_name.remove_at(position)
	if not save_user_names():
		all_user_name.insert(position, user_name)
		if moved:
			DirAccess.rename_absolute(quarantine, source)
		return "用户索引保存失败，已撤销删除"
	signal_users_update.emit()
	if moved and not delete_folder(quarantine):
		push_warning("用户索引已移除，待清理存档目录：" + quarantine)
	return ""

func rename_user(old_name: String, new_name: String) -> String:
	var new_user_name: String = new_name.strip_edges()
	if not is_valid_user_name(old_name) or not is_valid_user_name(new_user_name):
		return "用户名包含非法路径字符或保留名称"
	if old_name == new_user_name:
		return "新用户名不能与原用户名相同"
	if not all_user_name.has(old_name):
		return "原用户不存在"
	var old_path: String = _user_directory(old_name)
	var new_path: String = _user_directory(new_user_name)
	if all_user_name.has(new_user_name) or DirAccess.dir_exists_absolute(new_path):
		return "新用户名已存在"
	var was_current: bool = curr_user_name == old_name
	if was_current and (not Global.save_service.is_current_profile_loaded() or not Global.save_service.save_now()):
		return "当前玩家存档未成功保存，不能重命名"
	var moved: bool = DirAccess.dir_exists_absolute(old_path)
	if moved and DirAccess.rename_absolute(old_path, new_path) != OK:
		return "迁移存档目录失败"
	var index: int = all_user_name.find(old_name)
	all_user_name[index] = new_user_name
	if was_current:
		curr_user_name = new_user_name
	if not save_user_names():
		if was_current:
			curr_user_name = old_name
		all_user_name[index] = old_name
		if moved:
			DirAccess.rename_absolute(new_path, old_path)
		return "无法保存用户索引"
	signal_user_renamed.emit(old_name, new_user_name)
	signal_users_update.emit()
	return ""

func delete_folder(path: String) -> bool:
	# 禁止从此递归删除器接收用户根目录以外的路径。
	var root: String = ProjectSettings.globalize_path("user://").simplify_path()
	var absolute: String = ProjectSettings.globalize_path(path).simplify_path()
	if not absolute.begins_with(root + "/") and not absolute.begins_with(root + "\\"):
		return false
	var dir := DirAccess.open(path)
	if dir == null:
		return false
	for file: String in dir.get_files():
		if dir.remove(file) != OK:
			return false
	for sub: String in dir.get_directories():
		if not delete_folder(path.path_join(sub)):
			return false
	return DirAccess.remove_absolute(path) == OK
