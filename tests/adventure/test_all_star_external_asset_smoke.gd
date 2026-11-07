extends Node

func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://scenes/character/zombie/zombie_026_all_star.tscn")
	assert(packed != null)
	var zombie: Zombie026AllStar = packed.instantiate() as Zombie026AllStar
	assert(zombie != null and zombie.zombie_type == CharacterRegistry.ZombieType.Z026AllStar)
	zombie.character_init_type = Character000Base.E_CharacterInitType.IsShow
	add_child(zombie)
	await get_tree().process_frame
	var visual: Node2D = zombie.get_node("Body/AllStarVisual")
	var player: AnimationPlayer = visual.get_node("AnimationPlayer")
	assert(player != null and not zombie.get_node("Body/BodyCorrect").visible)
	var clips: Dictionary = {
		"idle": 100, "walk": 90, "eat": 259, "run": 20,
		"tackle": 39, "kick": 48, "die": 55,
	}
	for action in clips:
		assert(player.has_animation(action), "Missing original source action: " + action)
		var anim: Animation = player.get_animation(action)
		assert(is_equal_approx(anim.step, 0.033333))
		assert(is_equal_approx(anim.length, float(clips[action]) / 30.0))
		assert(anim.get_track_count() > 100)
		assert(anim.track_get_type(0) == Animation.TYPE_VALUE)
	assert(is_equal_approx(Zombie026AllStar.CHARGE_SPEED / Zombie026AllStar.SPENT_SPEED, 3.125))
	player.play(&"run")
	player.seek(0.1, true)
	var part: Sprite2D = visual.get_node("part_00")
	assert(part.texture != null and part.visible)
	assert(visual.scale == Vector2(0.6, 0.6))
	# Exercise the original PAM method key at tackle frame 5, without a full battle.
	zombie.charge_state = Zombie026AllStar.ChargeState.TACKLING
	player.play(&"tackle")
	player.advance(0.21)
	await get_tree().process_frame
	assert(zombie._tackle_hit_applied, "Source tackle use_action key did not dispatch")
	zombie.queue_free()
	await get_tree().process_frame
	print("ALL_STAR_ORIGINAL_30FPS_SOURCE_OK")
	get_tree().quit()
