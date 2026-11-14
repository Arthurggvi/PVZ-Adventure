## Destination observes the handoff before its own _ready, then closes the isolated test.
extends Node

func _ready() -> void:
	if AdventureSession.get_meta("scene_transition_test", false):
		print("PASS: threaded scene loaded; callback ran before destination _ready")
		AdventureSession.remove_meta("scene_transition_test")
		get_tree().quit(0)
	else:
		push_error("FAIL: threaded scene change callback was not executed before _ready")
		get_tree().quit(1)
