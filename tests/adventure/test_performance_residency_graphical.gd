extends SceneTree
## 隔离图形验收：凯莱赫真实动画、图鉴分页、环境合成启停以及音效预算。
## 禁止加载玩家档案，必须提供独立用户目录。
func _initialize() -> void:
	_run.call_deferred()

func _settle(count: int = 8) -> void:
	for index: int in count:
		await process_frame
	await RenderingServer.frame_post_draw

func _mem() -> float:
	return RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0

func _run() -> void:
	assert("performance" in OS.get_user_data_dir(), "isolated user directory required")
	await _settle()
	var base: float = _mem()
	var path := "res://scenes/character/zombie_boss/zombie_boss_006_cailleach.tscn"
	var scene: PackedScene = load(path)
	var boss = scene.instantiate()
	root.add_child(boss)
	await _settle()
	assert(is_instance_valid(boss._visual), "phase one visual")
	assert(boss._visual.sprite_frames.get_frame_count(&"idle") > 0, "phase one idle")
	var phase_one: float = _mem()
	boss._enter_phase_two(false)
	await _settle(15)
	assert(not is_instance_valid(boss._visual), "phase one released")
	var sprite = boss._phase_two_visual
	assert(is_instance_valid(sprite) and sprite.sprite_frames.get_frame_count(&"idle") == 60)
	assert(not ResourceLoader.has_cached("res://scenes/character/zombie_boss/cailleach_visual.tscn"), "phase one packed scene should not stay cached")
	var phase_two: float = _mem()
	var max_pages: int = 0
	var seen: Dictionary = {}
	var end: int = Time.get_ticks_msec() + 9500
	while Time.get_ticks_msec() < end:
		var frame: int = sprite.frame
		var texture: AtlasTexture = sprite.sprite_frames.get_frame_texture(&"idle",frame)
		assert(texture.atlas != null and not texture.atlas is PlaceholderTexture2D, "actual frame must be resident")
		assert(texture.region == Rect2((frame % 12) % 3 * 836, floori(float(frame % 12)/3.0)*470,836,470), "frame rect preserved")
		max_pages = maxi(max_pages,sprite._pages.size())
		seen[frame] = true
		await process_frame
	assert(seen.size() == 60, "all sixty animation frames must play")
	assert(max_pages <= 2 and sprite._fallback_count == 0, "no synchronous page loads in steady playback")
	print("BENCH cailleach baseline=",base," phase1=",phase_one," phase2=",phase_two," pages=",max_pages," frames=",seen.size()," fallback=",sprite._fallback_count)
	boss.queue_free()
	boss = null
	sprite = null
	scene = null
	await _settle(20)
	var final: float = _mem()
	assert(final <= base + 25.0, "boss released")
	print("BENCH cailleach released=", final)
	# 实际环境组件的中性、激活、暂停、恢复与销毁合同。
	var profile = BattleEnvironmentProfile.new()
	profile.screen_refraction_pixels = 2.0
	var renderer = BattleEnvironmentRenderer.new()
	root.add_child(renderer)
	renderer.configure(profile,null,null)
	await _settle(3)
	renderer.apply_state(1.0,0.0,Vector4.ZERO,Vector2.ZERO,false)
	assert(renderer._field.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	for copy: BackBufferCopy in renderer._copies:
		assert(copy.copy_mode == BackBufferCopy.COPY_MODE_DISABLED)
	assert(renderer.lens._copy.copy_mode == BackBufferCopy.COPY_MODE_DISABLED)
	renderer.apply_state(1.0,1.0,Vector4.ZERO,Vector2.ZERO,false)
	await _settle(3)
	assert(renderer._field.render_target_update_mode == SubViewport.UPDATE_ALWAYS)
	for copy: BackBufferCopy in renderer._copies:
		assert(copy.copy_mode == BackBufferCopy.COPY_MODE_VIEWPORT)
	renderer.apply_state(1.0,1.0,Vector4.ZERO,Vector2.ZERO,true)
	assert(renderer._field.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	renderer.apply_state(1.0,0.0,Vector4.ZERO,Vector2.ZERO,false)
	for copy: BackBufferCopy in renderer._copies:
		assert(copy.copy_mode == BackBufferCopy.COPY_MODE_DISABLED)
	renderer.queue_free()
	await _settle()
	print("PASS ENVIRONMENT COPY GATES")
	# 通过真实目录加载全部音效；现有播放器仍独立持有正在使用的流。
	var sound = root.get_node("SoundManager")
	var first: String = sound.SFXOtherMap[&"bleep"]
	var stream: AudioStream = sound._stream(first)
	var player: AudioStreamPlayer = sound.play_sfx_with_pool(stream,0.0,1.0,false)
	var count: int = 0
	for catalog: Dictionary in [sound.SFXBeAttackMap,sound.SFXBulletMap,sound.SFXCharacterMap,sound.SFXCarzyDaveMap,sound.SFXOtherMap]:
		for entry: Variant in catalog.values():
			var paths: Array = entry if entry is Array else [entry]
			for cue: Variant in paths:
				if cue is String:
					assert(sound._stream(cue) != null,"valid sound")
					count += 1
					assert(sound._stream_cache.size() <= sound.SFX_CACHE_MAX_ENTRIES)
					assert(sound._stream_cache_bytes <= sound.SFX_CACHE_MAX_BYTES)
	assert(player.stream == stream, "LRU must not replace playback stream")
	print("PASS AUDIO BUDGET paths=",count," entries=",sound._stream_cache.size()," bytes=",sound._stream_cache_bytes)
	await create_timer(1.0).timeout
	assert(player.stream == null or player.playing, "completed player must release stream")
	print("PASS PERFORMANCE RESIDENCY")
	quit()
