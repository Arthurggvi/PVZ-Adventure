## Single narrow smoke: a temporary profile, authoritative mutations and restore.
extends Node
func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var previous: String = Global.user_manager.curr_user_name
	var name := "cheat-p0-test-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute("user://" + name)
	Global.user_manager.curr_user_name = name
	assert(Global.reload_session_for_current_user())
	assert(PVZCheat.implementation != null)
	var f9 := InputEventKey.new()
	f9.physical_keycode = KEY_F9
	f9.pressed = true
	get_viewport().push_input(f9)
	await get_tree().process_frame
	assert(PVZCheat.is_open(), "F9 popup toggle failed")
	var screen: Control = PVZCheat.implementation.window
	for section: String in ["cards", "items", "coins", "stages", "saves"]:
		screen.select_section(section)
		assert(screen.content.get_child_count() > 0, "Missing module " + section)
	screen.select_section("coins")
	var set_button: Button
	var coin_input: SpinBox
	for control: Node in screen.content.find_children("*", "SpinBox", true, false):
		coin_input = control as SpinBox
	for control: Node in screen.content.find_children("*", "Button", true, false):
		if (control as Button).text == "设为":
			set_button = control as Button
	assert(set_button != null and coin_input != null)
	coin_input.value = 0
	set_button.pressed.emit()
	assert(Global.global_game_state.coin_value == 0)
	PVZCheat.toggle()
	assert(not PVZCheat.is_open())
	var commands: RefCounted = PVZCheat.implementation.commands
	var got: Dictionary = commands.add_cards(CharacterRegistry.PlantType.P001PeaShooterSingle, 3, 2)
	assert(got.ok, got.message)
	assert(Global.adventure_inventory.list_cards().size() == 2)
	assert(Global.adventure_inventory.list_cards()[0].get("stars") == 3)
	got = commands.change_item("nut_fragments", 5)
	assert(got.ok and Global.adventure_inventory.get_item_count("nut_fragments") == 5)
	got = commands.change_item("nut_fragments", -2)
	assert(got.ok and Global.adventure_inventory.get_item_count("nut_fragments") == 3)
	got = commands.change_item("nut_fragments", -4)
	assert(not got.ok and Global.adventure_inventory.get_item_count("nut_fragments") == 3)
	got = commands.grant_category("key", 1)
	assert(got.ok and Global.adventure_inventory.get_item_count("lawn_nightmare_key") == 1)
	got = commands.change_coin(150, "add")
	assert(got.ok and Global.global_game_state.coin_value == 150)
	got = commands.snapshot()
	assert(got.ok, got.message)
	got = commands.clear_stage(3, false)
	assert(got.ok, got.message)
	assert(AdventureStageCatalog.is_cleared(Global.global_game_state.adventure_state,
		AdventureStageRegistry.stage_id(3), StagePhaseDefinition.Kind.NORMAL))
	var entry_issue: String = AdventureStageCatalog.entry_error(3, StagePhaseDefinition.Kind.NORMAL,
		Global.global_game_state.adventure_state, Global.adventure_inventory)
	print("CHEAT_STAGE_ENTRY_PREFLIGHT " + ("READY" if entry_issue.is_empty() else entry_issue))
	got = commands.restore()
	assert(got.ok, got.message)
	assert(Global.adventure_inventory.list_cards().size() == 2)
	assert(Global.adventure_inventory.get_item_count("nut_fragments") == 3)
	assert(not AdventureStageCatalog.is_cleared(Global.global_game_state.adventure_state,
		AdventureStageRegistry.stage_id(3), StagePhaseDefinition.Kind.NORMAL))
	assert(Global.global_game_state.coin_value == 150)
	Global.user_manager.curr_user_name = previous
	Global.reload_session_for_current_user()
	AdventureSession._on_profile_changed()
	print("PVZ_CHEAT_P0_PASS modules=5 cards items coin stage snapshot")
	get_tree().quit(0)
