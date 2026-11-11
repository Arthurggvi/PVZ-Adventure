extends RefCounted
class_name BossTeleportAnimationFactory
## Project ONLY the existing Black General teleport FX tracks to another boss.
## Preserves source clip duration, frame timings, vortex/ripple tracks and poses.
const SOURCE_IN: Animation = preload("res://animation/character/zombie_boss/002_black_general/teleport_in.tres")
const SOURCE_OUT: Animation = preload("res://animation/character/zombie_boss/002_black_general/teleport_out.tres")

static func build(arrival: bool) -> Animation:
	var source: Animation = SOURCE_IN if arrival else SOURCE_OUT
	var result := Animation.new()
	result.length = source.length
	result.step = source.step
	for track in source.get_track_count():
		if source.track_get_type(track) != Animation.TYPE_VALUE:
			continue
		var original := String(source.track_get_path(track))
		if not original.begins_with("Teleport") and original != "Body:scale":
			continue
		var index := result.add_track(Animation.TYPE_VALUE)
		var new_path := original if original == "Body:scale" else "TeleportFX/" + original
		result.track_set_path(index, NodePath(new_path))
		result.track_set_interpolation_type(index, source.track_get_interpolation_type(track))
		result.value_track_set_update_mode(index, source.value_track_get_update_mode(track))
		for key in source.track_get_key_count(track):
			result.track_insert_key(index, source.track_get_key_time(track,key),
				source.track_get_key_value(track,key), source.track_get_key_transition(track,key))
	# Black General's original vortex does not itself fill the ring's centre.
	# Keep the actor present while front smoke occludes it; only then fade.
	var times := [0.0,.26,.36,.43,.49,.56,.70]
	var amount := [0.0,0.0,0.0,.20,.70,1.0,1.0] if arrival \
		else [1.0,1.0,1.0,.92,.65,0.0,0.0]
	for path in ["Body:modulate:a", "Phase2FX:modulate:a"]:
		var index := result.add_track(Animation.TYPE_VALUE)
		result.track_set_path(index, NodePath(path))
		for i in times.size():
			result.track_insert_key(index, times[i], amount[i])
	return result
