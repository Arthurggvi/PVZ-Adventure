## Uses the actual SceneTransition threaded route; never touches a player profile.
extends Node

const TRANSITION = preload("res://scenes/ui/transitions/SceneTransition.tscn")

func _ready() -> void:
	get_tree().create_timer(12.0).timeout.connect(func(): get_tree().quit(1))
	_run.call_deferred()

func _run() -> void:
	var transition := TRANSITION.instantiate()
	transition.reveal_on_ready = false
	add_child(transition)
	if transition.change_scene("res://tests/adventure/nonexistent_scene.tscn"):
		push_error("FAIL: invalid scene accepted")
		get_tree().quit(1)
		return
	# A failed legacy action uses the same recovery boundary as a failed
	# threaded load: it must reveal the old scene and unlock input.
	var original: Node = get_tree().current_scene
	var outcome: Dictionary = {"failed": false}
	transition.transition_failed.connect(func(): outcome.failed = true, CONNECT_ONE_SHOT)
	if not transition.run(func() -> bool: return false):
		push_error("FAIL: controlled failure route not accepted")
		get_tree().quit(1)
		return
	await transition.revealed
	if not outcome.failed or transition.busy or get_tree().current_scene != original:
		push_error("FAIL: failed route did not restore source scene and input")
		get_tree().quit(1)
		return
	if not transition.change_scene("res://tests/adventure/test_loading_target.tscn",
			func(): AdventureSession.set_meta("scene_transition_test", true)):
		push_error("FAIL: valid scene not accepted")
		get_tree().quit(1)
		return
	if transition.change_scene("res://tests/adventure/test_loading_target.tscn"):
		push_error("FAIL: duplicate request was accepted during load")
		get_tree().quit(1)
