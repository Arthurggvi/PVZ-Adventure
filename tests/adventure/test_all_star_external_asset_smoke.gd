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
	var whistle: AudioStreamPlayer = zombie.get_node("EntranceWhistle")
	assert(whistle.stream is AudioStreamOggVorbis)
	assert(whistle.bus == &"SFX")
	assert(whistle.stream.get_length() > 0.5 and whistle.stream.get_length() < 0.6)
	assert(not whistle.playing, "Character preview must not sound the entrance whistle")
	var visual: Node2D = zombie.get_node("Body/AllStarVisual")
	var player: AnimationPlayer = zombie.get_node("AnimationPlayer")
	assert(player != null and player.get_node(player.root_node) == visual)
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
	var observed_ratio: float = float(Zombie026AllStar.CHARGE_SPEED) / float(Zombie026AllStar.SPENT_SPEED) # 验证两个速度常量的相对关系。
	assert(is_equal_approx(observed_ratio, 3.125))
	# Source PAM temporarily inserts parts at run 453/456 and walk 164/169.
	# Stable instance slots must retain their own texture across those edits.
	var run_anim: Animation = player.get_animation(&"run")
	var run_texture_track := run_anim.find_track(NodePath("part_11:texture"), Animation.TYPE_VALUE)
	assert(run_texture_track >= 0)
	assert(run_anim.track_get_key_value(run_texture_track, 3) == run_anim.track_get_key_value(run_texture_track, 4))
	assert(run_anim.track_get_key_value(run_texture_track, 6) == run_anim.track_get_key_value(run_texture_track, 7))
	var walk_anim: Animation = player.get_animation(&"walk")
	var walk_texture_track := walk_anim.find_track(NodePath("part_09:texture"), Animation.TYPE_VALUE)
	assert(walk_texture_track >= 0)
	assert(walk_anim.track_get_key_value(walk_texture_track, 63) == walk_anim.track_get_key_value(walk_texture_track, 64))
	assert(walk_anim.track_get_key_value(walk_texture_track, 68) == walk_anim.track_get_key_value(walk_texture_track, 69))
	var appeared_transform := walk_anim.find_track(NodePath("part_14:transform"), Animation.TYPE_VALUE)
	assert(appeared_transform >= 0)
	assert(walk_anim.track_get_key_value(appeared_transform, 68) == walk_anim.track_get_key_value(appeared_transform, 69))
	# PAM retains ref63; it is intentionally retired only when ref65 takes over at frame 169.
	var retired_foot := walk_anim.find_track(NodePath("part_06:visible"), Animation.TYPE_VALUE)
	assert(retired_foot >= 0)
	assert(walk_anim.track_get_key_value(retired_foot, 63))
	assert(walk_anim.track_get_key_value(retired_foot, 64))
	assert(walk_anim.track_get_key_value(retired_foot, 68))
	assert(not walk_anim.track_get_key_value(retired_foot, 69))
	assert(not walk_anim.track_get_key_value(retired_foot, 89))
	var replacement_foot := walk_anim.find_track(NodePath("part_08:visible"), Animation.TYPE_VALUE)
	assert(replacement_foot >= 0)
	assert(walk_anim.track_get_key_value(replacement_foot, 69))
	# Sparse PAM transforms must preserve feet across the entire 259-frame eat.
	var eat_anim: Animation = player.get_animation(&"eat")
	for shoe_slot in [6, 7]:
		var shoe_visibility := eat_anim.find_track(
			NodePath("part_%02d:visible" % shoe_slot), Animation.TYPE_VALUE)
		assert(shoe_visibility >= 0)
		for eat_frame in [0, 12, 85, 170, 258]:
			assert(eat_anim.track_get_key_value(shoe_visibility, eat_frame))
	assert(walk_anim.find_track(NodePath("part_09:z_index"), Animation.TYPE_VALUE) >= 0)
	player.play(&"run")
	player.seek(0.1, true)
	var part: Sprite2D = visual.get_node("part_00")
	assert(part.texture != null and part.visible)
	assert(visual.scale == Vector2(0.6, 0.6))
	# Exercise the original PAM method key at tackle frame 5, without a full battle.
	zombie.charge_state = Zombie026AllStar.ChargeState.TACKLING
	zombie._set_move_speed(0.0)
	player.play(&"tackle")
	player.advance(0.21)
	await get_tree().process_frame
	assert(zombie._tackle_hit_applied, "Source tackle use_action key did not dispatch")
	assert(is_equal_approx(zombie.move_component.curr_speed_move, Zombie026AllStar.SPENT_SPEED))
	zombie._on_visual_animation_finished(&"tackle")
	assert(zombie.charge_state == Zombie026AllStar.ChargeState.SPENT)
	assert(player.current_animation == &"walk")
	zombie.is_attack = true
	zombie._sync_spent_action()
	assert(player.current_animation == &"eat")
	zombie.queue_free()
	await get_tree().process_frame
	print("ALL_STAR_ORIGINAL_30FPS_SOURCE_OK")
	get_tree().quit()
