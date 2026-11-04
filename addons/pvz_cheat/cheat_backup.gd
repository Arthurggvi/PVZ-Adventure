## Explicit per-profile disk snapshot; never replace a damaged or unvalidated backup.
extends RefCounted
const BACKUP := "CheatSnapshot.json"

static func _response(ok: bool, message: String) -> Dictionary:
	return {"ok": ok, "message": message}

func _paths() -> Dictionary:
	if Global.save_service == null or not Global.save_service.is_current_profile_loaded():
		return {}
	var profile: String = Global.user_manager.curr_user_name
	var root: String = "user://" + profile + "/"
	return {"main": root + SaveService.SaveGameFileName, "backup": root + BACKUP,
		"rollback": root + "CheatPreRestore.json"}

func _copy(source: String, target: String) -> bool:
	return DirAccess.copy_absolute(ProjectSettings.globalize_path(source),
		ProjectSettings.globalize_path(target)) == OK

func snapshot() -> Dictionary:
	var paths: Dictionary = _paths()
	if paths.is_empty():
		return _response(false, "请先加载有效的玩家存档。")
	if AdventureSession.active_level != null:
		return _response(false, "请先离开战斗后再备份。")
	if not Global.save_service.save_now():
		return _response(false, "当前存档写入失败，不能建立备份。")
	if not _copy(paths.main, paths.backup):
		return _response(false, "无法创建玩家专属备份文件。")
	return _response(true, "备份已创建：%s（同一玩家再次备份会覆盖）。" % BACKUP)

func restore() -> Dictionary:
	var paths: Dictionary = _paths()
	if paths.is_empty() or AdventureSession.active_level != null:
		return _response(false, "恢复需要已加载的玩家存档，且不能处于战斗中。")
	if not FileAccess.file_exists(paths.backup):
		return _response(false, "当前玩家没有修改器备份。")
	var checked: Dictionary = Global.save_service._decode_profile(paths.backup)
	if not checked.get("ok", false) or checked.get("new", true):
		return _response(false, "备份未通过正式存档校验，已拒绝恢复。")
	# Last-resort copy permits recovering if a later reload unexpectedly fails.
	if not _copy(paths.main, paths.rollback):
		return _response(false, "无法保存恢复前的保护副本。")
	if not _copy(paths.backup, paths.main):
		return _response(false, "替换存档文件失败。")
	if not Global.reload_session_for_current_user():
		_copy(paths.rollback, paths.main)
		Global.reload_session_for_current_user()
		return _response(false, "恢复后加载失败，已尝试回滚原存档。")
	AdventureSession._on_profile_changed()
	var scene: Node = Engine.get_main_loop().current_scene
	if scene != null and scene.scene_file_path == AdventureSession.MAP_SCENE:
		AdventureSession.open_adventure()
	return _response(true, "已恢复当前玩家的备份；背包和进度已重新加载。")
