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
	Global.user_manager.curr_user_name = second_name
	Global.reload_session_for_current_user()
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
	assert(Global.adventure_inventory.add_card(CharacterRegistry.PlantType.P001PeaShooterSingle) == "PC000002")
	Global.user_manager.curr_user_name = original_name
	print("PASS: adventure global save/load, selected_cards preservation, new profile isolation")
	get_tree().quit(0)
