## Isolated end-to-end battle entry/return via the canonical threaded transition.
## This driver is intentionally outside current_scene so it survives scene changes.
extends Node

func _ready() -> void:
	assert(OS.get_user_data_dir().contains("startup-battle-test"), "测试必须使用隔离玩家目录")
	get_tree().current_scene = null
	get_tree().create_timer(30.0, true, false, true).timeout.connect(func():
		push_error("FAIL: battle route timeout")
		get_tree().quit(1))
	_run.call_deferred()

func _run() -> void:
	Global.save_service.stop_autosave()
	var username: String = "boot-battle-%d" % Time.get_ticks_usec()
	if not _check(Global.user_manager.add_user(username).is_empty(), "create profile"):
		return
	if not _check(Global.user_manager.set_current_user(username), "select profile"):
		return
	if not _check(Global.reload_session_for_current_user(), "load profile"):
		return
	if not _check(AdventureSession.prepare_adventure(), "prepare adventure"):
		return
	if not _check(AdventureSession.complete_intro(), "grant cards and complete intro"):
		return
	if not _check(get_tree().change_scene_to_file(AdventureSession.MAP_SCENE) == OK, "open map"):
		return
	if not await _wait_for_scene(AdventureSession.MAP_SCENE):
		return
	var map: Node = get_tree().current_scene
	var transition: Node = map.get_node("SceneTransition")
	while transition.busy:
		await get_tree().process_frame
	var expected: String = Global.main_scene_registry.MainScenesMap[MainSceneRegistry.MainScenes.MainGameFront]
	if not _check(Global.game_para == null, "game parameter must be absent on map"):
		return
	var accepted: bool = AdventureSession.enter_stage(1, StagePhaseDefinition.Kind.NORMAL, transition)
	if not _check(accepted, "stage loading accepted: " + AdventureSession.error_message):
		return
	if not _check(Global.game_para == null and transition.busy, "no premature battle commit"):
		return
	if not await _wait_for_scene(expected):
		return
	if not _check(AdventureSession.active_stage_number == 1 and Global.game_para != null
			and AdventureSession.owns_battle(Global.game_para), "battle handoff and identity"):
		return
	if not _check(is_instance_valid(Global.main_game) and Global.main_game.game_para == Global.game_para,
			"game manager reads authoritative battle level"):
		return
	# A player cannot click the pause/leave UI before the battle curtain reveals.
	# Reproduce that input boundary rather than issuing a synthetic mid-transition exit.
	var battle_transition: Node = get_tree().current_scene.get_node("SceneTransition")
	while battle_transition.busy:
		await get_tree().process_frame
	var original_state: Dictionary = Global.global_game_state.adventure_state.to_dict()
	AdventureSession.abandon_battle()
	if not _check(Global.game_para != null, "failed to defer map state reset"):
		return
	if not await _wait_for_scene(AdventureSession.MAP_SCENE):
		return
	if not _check(Global.game_para == null and AdventureSession.active_stage_number == 0
			and AdventureSession.adventure_active, "return to map cleared battle state"):
		return
	if not _check(Global.global_game_state.adventure_state.to_dict() == original_state,
			"abandoned battle must not alter player inventory or progress"):
		return
	if not _check(not get_tree().paused and Engine.time_scale == 1.0,
			"battle pause and speed restored"):
		return
	print("PASS: threaded map→battle→map, deferred state handoff, profile continuity")
	get_tree().quit(0)

func _wait_for_scene(path: String) -> bool:
	var limit: int = Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < limit:
		var scene: Node = get_tree().current_scene
		if is_instance_valid(scene) and scene.scene_file_path == path:
			return true
		await get_tree().process_frame
	push_error("FAIL: scene did not activate: " + path)
	get_tree().quit(1)
	return false

func _check(ok: bool, reason: String) -> bool:
	if not ok:
		push_error("FAIL: battle route: " + reason)
		get_tree().quit(1)
	return ok
