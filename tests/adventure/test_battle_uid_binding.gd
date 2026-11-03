## 用原生菜单/草坪完成短流程，验证同物种多 UID 贯通到实际植物实例。
extends "res://tests/adventure/test_island_flow.gd"

func _run() -> void:
	assert(OS.get_user_data_dir().contains("battle-binding-test"))
	var username: String = "binding-%s" % Time.get_ticks_usec()
	get_tree().change_scene_to_file("res://scenes/main/01StartMenuV8.tscn")
	await _frames()
	Global.save_service.stop_autosave()
	var user: User = get_tree().current_scene.user
	user.panel_create_new_user.line_edit.text = username
	user.panel_create_new_user.button_ok.pressed.emit()
	_select_user(username)
	await _enter_island_from_menu()
	await _frames()
	var intro: Control = get_tree().current_scene.canvas.get_node("Intro")
	intro._finish()
	await _frames()
	assert(AdventureSession.progress.intro_completed)
	var inventory: AdventureInventoryService = Global.adventure_inventory
	var first: String = inventory.add_card(CharacterRegistry.PlantType.P001PeaShooterSingle, 1)
	var second: String = inventory.add_card(CharacterRegistry.PlantType.P001PeaShooterSingle, 2)
	assert(not first.is_empty() and not second.is_empty() and first != second)
	var selected: Array[String] = [first, second]
	assert(inventory.set_deck(selected))
	assert(Global.save_service.save_now())
	AdventureSession.enter_lawn()
	await _frames()
	var battle: MainGameManager = Global.main_game
	while not battle.card_manager.is_norm_appeared:
		await get_tree().process_frame
	assert(battle.main_game_progress == MainGameManager.E_MainGameProgress.CHOOSE_CARD)
	assert(battle.game_para.look_show_zombie and battle.game_para.can_choosed_card)
	assert(battle.zombie_manager.zombie_show_in_start.show_zombies_array.size() > 0)
	var chooser: CardSlotNorm = battle.card_manager.card_slot_norm
	assert(chooser.card_slot_candidate.candidate_containers.is_empty())
	assert(chooser.card_slot_candidate.adventure_candidates.size() == inventory.list_cards().size())
	var first_candidate: CardCandidateContainer = chooser.card_slot_candidate.get_adventure_candidate(first)
	var second_candidate: CardCandidateContainer = chooser.card_slot_candidate.get_adventure_candidate(second)
	assert(first_candidate != null and second_candidate != null and first_candidate != second_candidate)
	assert(not first_candidate.card.is_choosed_pre_card)
	chooser._on_texture_button_pressed() # 空卡组必须不能开战。
	assert(battle.main_game_progress == MainGameManager.E_MainGameProgress.CHOOSE_CARD)
	assert(AdventureSession.battle_loadout.is_empty())
	chooser._on_re_card_button_pressed() # 原版重选按钮改为载入本玩家上一次 UID 卡组。
	assert(chooser.card_slot_battle.curr_cards.size() == 2)
	chooser._on_cancal_card_button_pressed()
	assert(chooser.card_slot_battle.curr_cards.is_empty())
	first_candidate.card._on_button_pressed()
	assert(first_candidate.card.is_choosed_pre_card)
	first_candidate.card._on_button_pressed()
	assert(not first_candidate.card.is_choosed_pre_card)
	first_candidate.card._on_button_pressed()
	second_candidate.card._on_button_pressed()
	assert(chooser.card_slot_battle.curr_cards.size() == 2)
	chooser._on_texture_button_pressed()
	await _wait_battle()
	assert(Global.global_game_state.adventure_state.selected_card_uids == selected)
	var cards: Array[Card] = battle.card_manager.card_slot_battle.curr_cards
	assert(cards.size() == 2)
	assert(cards[0].battle_card_data["uid"] == first)
	assert(cards[1].battle_card_data["uid"] == second)
	assert(cards[0].battle_card_data["stars"] == 1 and cards[1].battle_card_data["stars"] == 2)
	assert(cards[0].card_reference.content_id == cards[1].card_reference.content_id)
	Global.global_game_state.adventure_state.cards[first].stars = 9
	assert(cards[0].battle_card_data["stars"] == 1)
	battle.card_manager.card_slot_battle.sun_value = 500
	for index: int in range(2):
		var card: Card = cards[index]
		var cell: PlantCell = battle.plant_cell_manager.all_plant_cells[2][index]
		battle.hand_manager._click_card(card)
		battle.hand_manager._on_cell_mouse_enter(cell)
		battle.hand_manager._on_click_cell(cell)
		await _frames()
		var plant: Plant000Base = cell.plant_in_cell[CharacterRegistry.PlacePlantInCell.Norm]
		assert(plant != null and plant.battle_card_data["uid"] == selected[index])
		assert(plant.battle_card_data["stars"] == index + 1)
		card.battle_card_data["stars"] = 99
		assert(plant.battle_card_data["stars"] == index + 1)
	print("PASS: duplicate-species UID / card slot / plant / frozen snapshots")
	get_tree().quit(0)
