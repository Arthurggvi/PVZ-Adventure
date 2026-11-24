## 桌面版原始存档写出器：先提交完整临时文件，再替换目标，永不触碰游戏原档。
extends RefCounted
class_name DesktopSaveExportWriter

## 将 [param original] 的已捕获字节保存到 [param destination]；失败保持旧文件内容。
static func write_snapshot(destination: String, original: PackedByteArray) -> bool:
	if destination.is_empty() or original.is_empty():
		return false
	var target: String = destination if destination.to_lower().ends_with(".json") else destination + ".json" # 统一扩展名。
	var temp: String = target + ".pvz-export-" + str(Time.get_ticks_usec()) + ".tmp" # 与目标同目录，便于原子重命名。
	var output: FileAccess = FileAccess.open(temp, FileAccess.WRITE) # 只打开新临时文件。
	if output == null:
		return false
	output.store_buffer(original) # 保留原始 JSON 字节，绝不重新序列化。
	output.flush()
	var written_ok: bool = output.get_error() == OK # 校验写入成功，不将半成品暴露为存档。
	output.close()
	if not written_ok or FileAccess.get_file_as_bytes(temp) != original:
		DirAccess.remove_absolute(temp)
		return false
	if not FileAccess.file_exists(target):
		if DirAccess.rename_absolute(temp, target) == OK:
			return true
		DirAccess.remove_absolute(temp)
		return false
	# 用户在系统保存对话框确认覆盖时，先挪开已有目标；失败时恢复。
	var previous: String = target + ".pvz-previous-" + str(Time.get_ticks_usec()) + ".tmp" # 仅本轮短期回滚用途。
	if DirAccess.rename_absolute(target, previous) != OK:
		DirAccess.remove_absolute(temp)
		return false
	if DirAccess.rename_absolute(temp, target) == OK:
		DirAccess.remove_absolute(previous)
		return true
	DirAccess.rename_absolute(previous, target) # 写入失败后尝试恢复原有目标文件。
	DirAccess.remove_absolute(temp)
	return false
