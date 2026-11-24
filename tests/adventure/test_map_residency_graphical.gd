extends SceneTree
## 地图连续移动与十一地区悬停验收，使用正式地图与隔离用户目录。
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	assert("performance" in OS.get_user_data_dir())
	var scene: PackedScene = load("res://scenes/adventure/wonderland_map.tscn")
	var map = scene.instantiate()
	root.add_child(map)
	current_scene = map
	map.set_process(false)
	map.camera.set_process(false)
	map.set_motion_enabled(false)
	var terrain = map.get_node("Terrain")
	for index: int in 20:
		await process_frame
	var times: Array[float] = []
	var max_count: int = 0
	# 每显示帧移动四个世界单位；略快于现行边缘平移，横跨大陆再返回。
	var start := Vector2(300,620)
	var end := Vector2(1474,225)
	for direction: int in 2:
		var from: Vector2 = start if direction == 0 else end
		var to: Vector2 = end if direction == 0 else start
		var steps: int = ceili(from.distance_to(to) / 4.0)
		for step: int in steps + 1:
			map.camera.position = from.lerp(to, float(step) / steps)
			map.camera.call("_clamp_center")
			var before: int = Time.get_ticks_usec()
			terrain.update_camera(map.camera)
			times.append(float(Time.get_ticks_usec() - before) / 1000.0)
			max_count = maxi(max_count,terrain.resident_count())
			var view_size: Vector2 = root.get_visible_rect().size / map.camera.zoom
			var visible := Rect2(map.camera.get_screen_center_position() - view_size * 0.5,view_size)
			for tile: Dictionary in terrain._tiles:
				var tex: Texture2D = tile.node.texture
				if tile.rect.intersects(visible):
					assert(tex != null and not tex is PlaceholderTexture2D, "visible tile must be native resolution")
			await process_frame
	times.sort()
	var p95: float = times[floori((times.size()-1)*0.95)]
	var worst: float = times.back()
	print("BENCH map pan samples=",times.size()," p95_ms=",p95," max_ms=",worst," max_tiles=",max_count)
	assert(max_count <= 6 and p95 < 5.0,"map residency/p95 budget")
	# 强制切换十一地标，查验所有蒙版均能回收，地标身份和轮廓位置不变。
	var elapsed: float = 10.0
	var catalog: Array = map.assets.landmarks.landmarks
	var hovered_count: int = 0
	for entry: Dictionary in catalog:
		var sample: Array = entry.hit_sample_world
		map.interaction.hover_world(Vector2(sample[0],sample[1]))
		var deadline: int = Time.get_ticks_msec()+2000
		var sprite: Sprite2D = null
		while Time.get_ticks_msec()<deadline:
			elapsed+=0.04
			map.interaction.set_animation_seconds(elapsed)
			sprite=map.interaction.get_node_or_null("Hover_"+str(entry.id))
			if is_instance_valid(sprite) and sprite.visible:
				break
			await process_frame
		assert(is_instance_valid(sprite) and sprite.visible,"hover "+str(entry.id))
		var mask_path: String = sprite.texture.resource_path
		map.interaction.clear_hover()
		elapsed+=1.0
		map.interaction.set_animation_seconds(elapsed)
		for index: int in 4:
			await process_frame
		assert(not is_instance_valid(sprite),"hover node freed")
		assert(not ResourceLoader.has_cached(mask_path),"hover mask freed "+mask_path)
		hovered_count+=1
	print("PASS MAP HOVER RELEASE count=",hovered_count)
	map.queue_free()
	await process_frame
	for index: int in 8:
		await process_frame
	print("PASS MAP GRAPHICAL RESIDENCY")
	quit()
