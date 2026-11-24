## 在隔离用户目录的真实战斗中回归邮差硬到期与钟表匠统一时间轴。
extends Node

const Slow = preload("res://scripts/adventure/skills/battle_action_slowdown.gd")
const Parcel = preload("res://scripts/adventure/skills/rainy_postman_parcel_expiry.gd")
const POSTMAN = preload("res://resources/adventure/skills/rainy_postman_airmail.tres")

## 测试节点必须在换场后继续运行，且有独立的真实时间失败出口。
func _ready() -> void:
	get_tree().current_scene = null
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(45.0, true, false, true).timeout.connect(func() -> void:
		push_error("SKILL LIFECYCLE FAIL: test timeout")
		get_tree().quit(1))
	_run.call_deferred()

## 不依赖旧海滨菜单或地图的工具函数，直接等待真实选卡及战斗入口。
func _wait_battle() -> void:
	while not is_instance_valid(Global.main_game):
		await get_tree().process_frame
	var battle: MainGameManager = Global.main_game
	while battle.main_game_progress != MainGameManager.E_MainGameProgress.CHOOSE_CARD:
		await get_tree().process_frame
	while not battle.card_manager.is_norm_appeared:
		await get_tree().process_frame
	var chooser: CardSlotNorm = battle.card_manager.card_slot_norm
	for uid: String in Global.global_game_state.adventure_state.selected_card_uids:
		var candidate: CardCandidateContainer = chooser.card_slot_candidate.get_adventure_candidate(uid)
		assert(candidate != null, "starter deck candidate must be visible")
		candidate.card._on_button_pressed()
	chooser._on_texture_button_pressed()
	while battle.main_game_progress != MainGameManager.E_MainGameProgress.MAIN_GAME:
		await get_tree().process_frame
	await get_tree().create_timer(1.2, true, false, true).timeout

## 检查失败时明确以退出码 1 结束；不依赖调试断言是否启用。
func _check(ok: bool, message: String) -> bool:
	if not ok:
		push_error("SKILL LIFECYCLE FAIL: " + message)
		get_tree().quit(1)
	return ok

## 使用实际新玩家、选卡、出怪管理器、僵王工厂和手持路径。
func _run() -> void:
	if not _check(is_equal_approx(POSTMAN.cooldown_seconds, 50.0), "postman cooldown 50s"):
		return
	var username: String = "postman-clockmaker-%s" % Time.get_ticks_usec()
	Global.save_service.stop_autosave()
	if not _check(Global.user_manager.add_user(username).is_empty(), "isolated user created"):
		return
	if not _check(Global.user_manager.set_current_user(username) 			and Global.reload_session_for_current_user(), "isolated user loaded"):
		return
	if not _check(AdventureSession.prepare_adventure() and AdventureSession.complete_intro(),
			"starter profile and intro completed"):
		return
	var inventory: AdventureInventoryService = Global.adventure_inventory
	var selected: Array[String] = []
	for snapshot: Dictionary in inventory.list_cards():
		selected.append(str(snapshot["uid"]))
	if not _check(selected.size() >= 1 and inventory.set_deck(selected), "starter cards and deck"):
		return
	if not _check(AdventureSession.enter_stage(1), "stage 1 accepted"):
		return
	await _wait_battle()
	if TreePauseManager.is_paused_for(TreePauseManager.E_PauseFactor.CharacterSkillTutorial):
		TreePauseManager.end_tree_pause(TreePauseManager.E_PauseFactor.CharacterSkillTutorial)
	if not _check(not get_tree().paused, "battle is not paused after tutorial dismissal"):
		return
	var battle: MainGameManager = Global.main_game
	if not _check(is_instance_valid(battle) and battle.adventure_runtime != null,
			"actual adventure battle started"):
		return
	var manager: ZombieManager = battle.zombie_manager
	var row: ZombieRow = manager.all_zombie_rows[0]
	var spawn_x: float = row.zombie_create_position.global_position.x
	# 用战斗身份和真实管理器；没有敌人时施放的时钟也可以覆盖后续增援。
	var source := RepeaterShotContext.new()
	source.game = battle
	source.board = battle.board
	source.round_index = battle.curr_game_round
	source.phase = AdventureSession.get_active_phase(battle.game_para)
	if not _check(source.is_active(), "stage identity valid"):
		return
	var targets: Array[Character000Base] = []
	var clock := Slow.new(source, targets, 12.0, 0.10, Vector2(0.60, 0.0), Vector2(0.88, 0.06))
	battle.adventure_runtime.add_child(clock)
	var first: Zombie000Base = manager.create_skill_zombie(CharacterRegistry.ZombieType.Z001Norm, 0, spawn_x)
	if not _check(first != null and is_equal_approx(first.action_rate(), 0.10),
			"first spawned enemy inherits 10% rate"):
		return
	clock._physics_process(7.0)
	var current_rate: float = first.action_rate()
	var second: Zombie000Base = manager.create_skill_zombie(CharacterRegistry.ZombieType.Z001Norm, 0, spawn_x)
	if not _check(second != null and is_equal_approx(second.action_rate(), current_rate) 			and is_equal_approx(clock.elapsed, 7.0) 			and is_equal_approx(clock.remaining_fraction(), 5.0 / 12.0),
			"new zombie shares remaining 5s and current rate"):
		return
	# 效果持续期间登场的真实 Boss 从管理器登记事件接入现有时钟。
	var boss: ZB000Base = manager.try_create_boss_from_card(CharacterRegistry.ZombieBossType.ZB002BlackGeneral)
	if not _check(boss != null and is_equal_approx(boss.action_rate(), current_rate),
			"new Boss shares the current Clockmaker rate"):
		return
	clock._physics_process(4.0)
	if not _check(is_equal_approx(first.action_rate(), second.action_rate()) \
			and is_equal_approx(boss.action_rate(), second.action_rate()) \
			and is_equal_approx(clock.remaining_fraction(), 1.0 / 12.0),
			"ordinary zombies and the Boss share recovery"):
		return
	clock._physics_process(1.0)
	if not _check(is_equal_approx(first.action_rate(), 1.0) 			and is_equal_approx(second.action_rate(), 1.0) 			and is_equal_approx(boss.action_rate(), 1.0) 			and not manager.signal_zombie_created.is_connected(clock._on_zombie_created),
			"all sources and spawn subscriptions cleared"):
		return
	var after: Zombie000Base = manager.create_skill_zombie(CharacterRegistry.ZombieType.Z001Norm, 0, spawn_x)
	if not _check(after != null and is_equal_approx(after.action_rate(), 1.0),
			"spawning after expiry is unaffected"):
		return
	# 用真实临时卡与原生手持管理器检查邮差卡到期时不留下虚影或库存引用。
	var reference := ResourceCardReference.create(ResourceCardReference.CardType.Plant,
		CharacterRegistry.PlantType.P001PeaShooterSingle)
	var card: Card = AllCards.create_card(reference, Card.CardContext.Battle)
	if not _check(card != null, "postman plant card constructed"):
		return
	card.is_free_temporary = true
	var delivery := Control.new()
	battle.canvas_layer_ui.add_child(delivery)
	delivery.add_child(card)
	battle.card_manager.register_temp_card(card)
	var expiry := Parcel.new()
	expiry.configure(card, battle.card_manager)
	card.add_child(expiry)
	expiry._process(14.0)
	if not _check(battle.card_manager.curr_temp_cards.has(card) and not card.is_queued_for_deletion(),
			"parcel still present before fifteen seconds"):
		return
	battle.hand_manager._click_card(card)
	if not _check(battle.hand_manager.hm_character.curr_card == card, "parcel can be held"):
		return
	expiry._process(1.01)
	if not _check(card.is_queued_for_deletion() and not battle.card_manager.curr_temp_cards.has(card) 			and battle.hand_manager.curr_hm_status == HandManager.E_HandManagerStatus.Null 			and battle.hand_manager.hm_character.curr_card == null 			and not card.is_can_click and expiry.get_parent() == battle.canvas_layer_ui,
			"at fifteen seconds parcel unregisters, cancels hand, and plays detached effect"):
		return
	expiry._process(0.37)
	if not _check(expiry.is_queued_for_deletion(), "vanish effect stops without a timer leak"):
		return
	print("PASS: postman 50s CD, strict 15s and held expiration. Clockmaker shared decay for late zombies and Boss, plus cleanup.")
	get_tree().quit(0)
