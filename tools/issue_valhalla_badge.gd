## 为维护者指定的玩家档案制作限量徽章发放副本。本工具不随游戏发行。
extends Node

## 只发放已登记、刻有首通者姓名的第一枚纪念徽章。
const EDITION_UID: int = 1
## 角色装备目录中的圣徽定义。
const BADGE_ID: StringName = &"valhalla_temple_light"

## 等待自动加载初始化后执行一次发放。
func _ready() -> void:
	call_deferred("_issue")

## 读取显式指定的存档并将结果写进全新目录。由维护者确认存档归属，昵称不能证明身份。
func _issue() -> void:
	var isolation_root: String = OS.get_environment("PVZ_BADGE_ISSUE_ISOLATED").replace("\\", "/") # 启动器本次创建的目录。
	var user_data: String = OS.get_user_data_dir().replace("\\", "/") # Godot 实际解析的用户存档根。
	if DisplayServer.get_name() != "headless" or isolation_root.is_empty() \
			or not user_data.begins_with(isolation_root + "/"):
		_stop("请通过 tools/issue_valhalla_badge.py 启动发放工具。")
		return
	var args: PackedStringArray = OS.get_cmdline_user_args() # 只读取 -- 之后明确提供的路径。
	if args.size() != 2 or not args[0].is_absolute_path() or not args[1].is_absolute_path() \
			or args[0].get_file() != SaveService.SaveGameFileName:
		_stop("需要首通者的 GlobalSaveGame.json 和一个尚未创建的输出目录。")
		return
	var source: Dictionary = SaveService.read_profile_snapshot(args[0]) # 复用正式档案读取规则，不写入来源。
	if not source.ok or source.new or not source.data.has("adventure"):
		_stop("指定的档案没有可用的冒险存档。")
		return
	var profile: Dictionary = source.data # 保留原有角色装备之外的所有存档字段。
	var adventure: AdventureState = source.adventure # 校验后独立恢复的冒险状态。
	var equipment := PlayerEquipmentService.new(adventure.equipment) # 复用正式装备的发放和序列号规则。
	if equipment.grant_numbered(BADGE_ID, EDITION_UID).is_empty():
		_stop("发放失败。请确认目标档案符合归属规则、徽章资源已导入且当前未持有 UID #1。")
		return
	profile[SaveProfileIdentity.FIELD] = adventure.equipment.profile_uid
	profile.adventure.equipment = adventure.equipment.to_dict()
	var destination: String = args[1].simplify_path() # 每次发放使用一个独立的新目录。
	if DirAccess.make_dir_absolute(destination) != OK:
		_stop("无法创建输出目录。请指定一个尚不存在的目录，且其父目录必须存在。")
		return
	var output_path: String = destination.path_join(SaveService.SaveGameFileName) # 保持游戏识别的文件名。
	if not SaveFileStore.write(output_path, profile):
		DirAccess.remove_absolute(output_path + SaveFileStore.TEMP_SUFFIX)
		DirAccess.remove_absolute(destination) # 只清理由本次调用创建的空目录。
		_stop("无法写入发放副本。")
		return
	print("已写入英灵殿 · 神殿之光 UID #1 的存档副本：", output_path)
	get_tree().quit()

## 输出 [param message] 并以非零状态退出，保证维护者能区分失败和已生成副本。
func _stop(message: String) -> void:
	printerr(message)
	get_tree().quit(1)
