extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: PackedScene = load("res://scenes/character/zombie/zombie_026_all_star.tscn")
	assert(scene != null, "All-Star scene cannot load")
	var zombie: Zombie026AllStar = scene.instantiate() as Zombie026AllStar
	assert(zombie != null, "All-Star script not attached")
	assert(zombie.zombie_type == CharacterRegistry.ZombieType.Z026AllStar)
	zombie.character_init_type = Character000Base.E_CharacterInitType.IsShow
	add_child(zombie)
	await get_tree().process_frame
	var visual: AnimatedSprite2D = zombie.get_node("Body/AllStarVisual")
	assert(visual.sprite_frames != null, "External sprite frames missing")
	for clip in [&"idle", &"run", &"tackle", &"eat", &"death"]:
		assert(visual.sprite_frames.has_animation(clip), "Missing external clip %s" % clip)
	assert(visual.sprite_frames.get_frame_count(&"run") == 26)
	assert(visual.sprite_frames.get_frame_count(&"tackle") == 2)
	assert(not zombie.get_node("Body/BodyCorrect").visible, "Legacy football visual must be hidden")
	assert(CharacterRegistry.ZombieSpawnPower[CharacterRegistry.ZombieType.Z026AllStar] == 12)
	print("ALL_STAR_EXTERNAL_ASSET_SCENE_OK")
	get_tree().quit()
