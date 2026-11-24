## JSON 玩家档案的独立磁盘事务。验证临时文件后替换正式档，并保留上次副本。
extends RefCounted
class_name SaveFileStore

const TEMP_SUFFIX := ".pending"
const BACKUP_SUFFIX := ".bak"

## 读取 [param path] 的 JSON；[param include_source] 为 true 时同时返回解析所用的原始字节。
static func read(path: String, include_source: bool = false) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": true, "exists": false, "data": {}}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "exists": true, "data": {}}
	var raw: PackedByteArray = file.get_buffer(file.get_length()) # 同一缓冲区既用于解析，也可辨认尚未迁移的旧档。
	var error: Error = file.get_error()
	file.close()
	if error != OK and error != ERR_FILE_EOF:
		return {"ok": false, "exists": true, "data": {}}
	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8()) # 存档协议始终使用 UTF-8。
	if not parsed is Dictionary or parsed.is_empty():
		return {"ok": false, "exists": true, "data": {}}
	var result: Dictionary = {"ok": true, "exists": true, "data": parsed} # 普通校验无需保留原始缓冲区。
	if include_source:
		result["source"] = raw
	return result

static func write(path: String, data: Dictionary) -> bool:
	if path.is_empty() or data.is_empty():
		return false
	var pending: String = path + TEMP_SUFFIX
	var backup: String = path + BACKUP_SUFFIX
	var file := FileAccess.open(pending, FileAccess.WRITE)
	if file == null:
		push_error("无法创建存档临时文件：" + pending)
		return false
	var payload: String = JSON.stringify(data, "\t")
	file.store_string(payload)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		push_error("存档临时文件写入失败：" + str(write_error))
		return false
	var checked: Dictionary = read(pending)
	if not checked.get("ok", false) or FileAccess.get_file_as_string(pending) != payload:
		push_error("存档临时文件校验失败，正式档保持不变。")
		return false
	if FileAccess.file_exists(path):
		var copy_error: Error = DirAccess.copy_absolute(path, backup)
		if copy_error != OK:
			push_error("存档备份失败，拒绝覆盖原始存档：" + str(copy_error))
			return false
	var promote: Error = DirAccess.rename_absolute(pending, path)
	if promote != OK:
		push_error("无法安全替换正式存档，原档及备份未被删除：" + str(promote))
		return false
	return true
