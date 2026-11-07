extends Node

func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load("res://scenes/character/zombie/zombie_026_all_star.tscn")
	assert(scene != null, "All-Star scene must load")
	var zombie: Zombie026AllStar = scene.instantiate() as Zombie026AllStar
	assert(zombie != null)
	assert(zombie.zombie_type == CharacterRegistry.ZombieType.Z026AllStar)
	zombie.character_init_type = Character000Base.E_CharacterInitType.IsShow
	add_child(zombie)
	await get_tree().process_frame
	var visual: Node2D = zombie.get_node("Body/AllStarVisual")
	var player: AnimationPlayer = visual.get_node("AnimationPlayer")
	assert(player != null)
	assert(not zombie.get_node("Body/BodyCorrect").visible)
	for clip in [&"idle", &"run", &"walk", &"tackle", &"eat", &"death"]:
		assert(player.has_animation(clip), "Missing native animation " + clip)
	var run: Animation = player.get_animation(&"run")
	assert(run.step > 0.083 and run.step < 0.084)
	assert(run.get_track_count() > 50, "Source part transforms missing")
	assert(run.track_get_type(0) == Animation.TYPE_VALUE)
	assert(is_equal_approx(Zombie026AllStar.CHARGE_SPEED / Zombie026AllStar.SPENT_SPEED, 3.125))
	assert(run.value_track_get_update_mode(0) == Animation.UPDATE_CONTINUOUS)
	assert(run.track_get_key_value(0, 0) is Transform2D)
	var sprite: Sprite2D = visual.get_node("anim_head1")
	assert(sprite.texture != null)
	player.play(&"run")
	player.seek(0.5, true)
	assert(sprite.visible)
	print("ALL_STAR_NATIVE_ANIMATION_OK")
	get_tree().quit()
