extends Node
## Native animation QA. Copy only visual Sprite2D nodes, never gameplay components.
const FOOTBALL: PackedScene = preload("res://scenes/character/zombie/zombie_008_football.tscn")
const OUTPUT := "user://native_football_reference"
func _ready() -> void:
	call_deferred("_run")
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var f := FileAccess.open(OUTPUT + "/progress.txt",FileAccess.WRITE)
	f.store_string("START\n")
	f.flush()
	var donor := FOOTBALL.instantiate()
	var host := Node2D.new()
	host.name = "Host"
	var body := Node2D.new()
	body.name = "Body"
	host.add_child(body)
	var donor_parts: Node2D = donor.get_node("Body/BodyCorrect")
	var parts := Node2D.new()
	parts.name = "BodyCorrect"
	parts.position = donor_parts.position
	body.add_child(parts)
	for child in donor_parts.get_children():
		if child is Sprite2D:
			var source: Sprite2D = child
			var target := Sprite2D.new()
			target.name = source.name
			target.texture = source.texture
			target.position = source.position
			target.rotation = source.rotation
			target.scale = source.scale
			target.skew = source.skew
			target.centered = source.centered
			target.visible = source.visible
			parts.add_child(target)
	f.store_string("SPRITES_CLONED\n")
	f.flush()
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	host.add_child(ap)
	ap.root_node = NodePath("..")
	var library := AnimationLibrary.new()
	var raw_ap: AnimationPlayer = donor.get_node("AnimationPlayer")
	for anim_name in raw_ap.get_animation_list():
		var anim := raw_ap.get_animation(anim_name).duplicate(true) as Animation
		for k in range(anim.get_track_count()-1,-1,-1):
			var path := String(anim.track_get_path(k))
			if not path.begins_with("Body/BodyCorrect/"):
				anim.remove_track(k)
			else:
				var node_name := path.split(":")[0].trim_prefix("Body/BodyCorrect/")
				if parts.get_node_or_null(node_name) == null:
					anim.remove_track(k)
		library.add_animation(anim_name,anim)
	ap.add_animation_library(&"",library)
	f.store_string("ANIMATION_LIBRARY_READY\n")
	f.flush()
	var vp := SubViewport.new()
	vp.size = Vector2i(480,360)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_tree().root.add_child(vp)
	vp.add_child(host)
	host.position = Vector2(230,285)
	donor.free()
	f.store_string("VIEWPORT_READY\n")
	f.flush()
	await get_tree().process_frame
	for action in [&"Zombie_football_walk",&"Zombie_football_idle"]:
		ap.play(action)
		var anim: Animation = ap.get_animation(action)
		for k in range(12):
			ap.seek(anim.length*float(k)/12.0,true)
			await get_tree().process_frame
			await get_tree().process_frame
			var path := "%s/%s_%02d.png" % [OUTPUT,action,k]
			vp.get_texture().get_image().save_png(path)
	f.store_string("BLACK_GENERAL_NATIVE_REFERENCE_OK\n")
	f.flush()
	print("BLACK_GENERAL_NATIVE_REFERENCE_OK")
	get_tree().quit()
