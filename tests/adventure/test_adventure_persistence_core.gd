## 只验证冒险数据的全局持久化接入，不运行地图/战斗；须隔离 APPDATA。
extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	assert(OS.get_user_data_dir().contains("adventure-persist-test"))
	var original_name: String = Global.user_manager.curr_user_name
	var first_name := "persist-a-%d" % Time.get_ticks_usec()
	var second_name := first_name + "-b"
	DirAccess.make_dir_recursive_absolute("user://" + first_name)
	DirAccess.make_dir_recursive_absolute("user://" + second_name)
	Global.user_manager.curr_user_name = first_name
	Global.reload_session_for_current_user()
	assert(Global.adventure_inventory.list_cards().is_empty())
	var first_uid: String = Global.adventure_inventory.add_card(CharacterRegistry.PlantType.P001PeaShooterSingle)
	assert(first_uid == "PC000001")
	assert(Global.adventure_inventory.add_item("nut_fragments", 3))
	assert(Global.adventure_inventory.set_deck([first_uid]))
	Global.global_game_state.adventure_state.regions["zombie_island"] = {"started": true, "intro_completed": false}
	Global.save_service.save_now()
	var first_path := "user://%s/GlobalSaveGame.json" % first_name
	assert(FileAccess.file_exists(first_path))
	var first_data: Variant = JSON.parse_string(FileAccess.get_file_as_string(first_path))
	assert(first_data is Dictionary and first_data.has("adventure"))
	assert(first_data["adventure"]["cards"].size() == 1)
	Global.save_service.save_selected_cards()
	var after_selected: Variant = JSON.parse_string(FileAccess.get_file_as_string(first_path))
	assert(after_selected["adventure"]["items"]["nut_fragments"] == 3)
	await _verify_scheduled_save(first_path)
	var before_switch: int = _saved_sweep_count(first_path) # 合并窗口还未提交的击杀应写入离开的档案。
	Global.record_zombie_defeat()
	assert(_saved_sweep_count(first_path) == before_switch)
	Global.user_manager.curr_user_name = second_name
	assert(Global.reload_session_for_current_user())
	assert(_saved_sweep_count(first_path) == before_switch + 1)
	assert(Global.adventure_inventory.list_cards().is_empty())
	assert(Global.adventure_inventory.get_item_count("nut_fragments") == 0)
	assert(Global.global_game_state.adventure_state.regions.is_empty())
	assert(Global.adventure_inventory.add_card(CharacterRegistry.PlantType.P002SunFlower) == "PC000001")
	Global.user_manager.curr_user_name = first_name
	Global.reload_session_for_current_user()
	assert(Global.adventure_inventory.get_card(first_uid)["plant_type"] == CharacterRegistry.PlantType.P001PeaShooterSingle)
	assert(Global.adventure_inventory.get_item_count("nut_fragments") == 3)
	assert(Global.global_game_state.adventure_state.selected_card_uids == [first_uid])
	assert(Global.global_game_state.adventure_state.regions["zombie_island"]["started"])
	var second_uid: String = Global.adventure_inventory.add_card(CharacterRegistry.PlantType.P001PeaShooterSingle)
	assert(second_uid == "PC000002")
	assert(Global.adventure_inventory.move_card(second_uid, 0))
	assert(Global.global_game_state.adventure_state.selected_card_uids == [first_uid])
	assert(Global.save_service.save_now())
	assert(Global.reload_session_for_current_user())
	assert(Global.adventure_inventory.get_card_order() == [second_uid, first_uid])
	assert(Global.global_game_state.adventure_state.selected_card_uids == [first_uid])
	Global.user_manager.curr_user_name = original_name
	print("PASS: adventure global save/load, ordered scheduled save, selected_cards preservation, profile isolation")
	get_tree().quit(0)

## [param path] 为隔离档案。等待普通写入接纳后，立即提交更新版本并核对备份顺序。
func _verify_scheduled_save(path: String) -> void:
	var progress: int = _saved_sweep_count(path) # 之前已持久化的起点。
	Global.record_zombie_defeat()
	Global.refresh_quests()
	assert(_saved_sweep_count(path) == progress, "任务刷新不应同步写盘")
	var deadline: int = Time.get_ticks_msec() + 5000 # 等待调度器接纳后台快照，超时明确失败。
	while Global.save_service._writing_path != path and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	assert(Global.save_service._writing_path == path, "普通变更应由后台线程持久化")
	Global.record_zombie_defeat()
	assert(Global.save_service.save_now())
	assert(_saved_sweep_count(path) == progress + 2)
	assert(_saved_sweep_count(path + SaveFileStore.BACKUP_SUFFIX) == progress + 1)

## 读取 [param path] 中前线扫荡的持久化计数。
func _saved_sweep_count(path: String) -> int:
	var saved: Dictionary = SaveFileStore.read(path) # 从文件核对持久版本，不读取内存状态。
	assert(saved.get("ok") and saved.get("exists"))
	return int(saved.data.adventure.quests.records["daily_frontline_sweep"].progress)
