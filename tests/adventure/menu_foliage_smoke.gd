extends SceneTree

var failed := false

func _initialize() -> void:
    call_deferred("_check")

func _check() -> void:
    var menu: Control = load("res://scenes/main/01StartMenuV8.tscn").instantiate()
    root.add_child(menu)
    await process_frame
    var art := menu.get_node("ArtCanvas")
    var bg := art.get_node("coastal_yard") as TextureRect
    var foliage := art.get_node("EnvironmentFX/FoliageFX")
    var wind := foliage.get_node("Wind")
    var falling := art.get_node("ForegroundLeaves")
    var material := bg.material as ShaderMaterial
    _expect(material != null and bg.texture.get_size() == Vector2(1920,1080), "original full painting remains")
    _expect(foliage.get_child_count() == 1 and foliage.get_child(0) == wind, "no cropped leaf or opaque repair sprites")
    _expect(falling.wind == wind and falling.particles.size() == 20, "foreground uses same bounded wind source")
    var mask := material.get_shader_parameter("motion_core") as Texture2D
    var pixels := mask.get_image()
    _expect(pixels.get_size() == Vector2i(1920, 1080), "motion mask uses full canvas UV")
    _expect(pixels.get_pixel(900, 120).r < 0.001, "sky never displaced")
    _expect(pixels.get_pixel(200, 300).r < 0.001, "lower foliage edge never displaced")
    _expect(pixels.get_pixel(300, 50).r > 0.3, "interior foliage still responds")
    var original_texture := bg.texture
    wind._enter(&"gust")
    wind._process(0.75)
    foliage._process(0.016)
    _expect(float(material.get_shader_parameter("wind_strength")) > 0.4, "gust feeds shader")
    _expect(falling.live_count() >= 3, "gust spawns foreground leaves")
    menu.environment_fx_enabled = false
    _expect(float(material.get_shader_parameter("wind_strength")) == 0.0, "stop returns original pixel sampling")
    _expect(not falling.active and falling.live_count() == 0, "disable recycles leaf pool")
    _expect(bg.texture == original_texture, "no background substitution on FX off")
    menu.use_clean_sky = false
    _expect(bg.texture != original_texture, "switch to untouched original sky")
    menu.use_clean_sky = true
    _expect(bg.texture == original_texture, "restore clean-sky artwork")
    menu.environment_fx_enabled = true
    _expect(falling.active and wind.active, "enable resumes without rebuilding material")
    print("MENU_FOLIAGE_SMOKE_FAIL" if failed else "MENU_FOLIAGE_SMOKE_PASS")
    menu.queue_free()
    await process_frame
    quit(1 if failed else 0)

func _expect(ok: bool, reason: String) -> void:
    if not ok:
        failed = true
        push_error("FOLIAGE: " + reason)
