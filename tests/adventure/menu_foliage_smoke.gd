extends SceneTree

var failed := false

func _initialize() -> void:
    call_deferred("_check")

func _check() -> void:
    var menu: Control = load("res://scenes/main/01StartMenuV8.tscn").instantiate()
    root.add_child(menu)
    await process_frame
    var art := menu.get_node("ArtCanvas")
    var foliage := art.get_node("EnvironmentFX/FoliageFX")
    var wind := foliage.get_node("Wind")
    var falling := art.get_node("ForegroundLeaves")
    var leaves := foliage.get_node("Leaves") as Sprite2D
    var material := leaves.material as ShaderMaterial
    _expect(falling.get_parent() == art and falling.z_index == 0, "explicit sibling leaf layer")
    _expect(falling.wind == wind, "shared wind injected by menu composition root")
    _expect(falling.particles.size() == 20, "bounded falling leaf pool")
    _expect(not foliage.has_node("Clusters"), "no duplicate transparent clusters")
    var underlay := foliage.get_node("Underlay") as Sprite2D
    var underlay_image := underlay.texture.get_image()
    _expect(underlay_image.get_format() != Image.FORMAT_RGB8, "underlay uses transparent pixels")
    _expect(underlay_image.get_pixel(839, 190).a < 0.01, "clouds not hidden by a rectangular patch")
    var clean_patch := underlay.texture
    menu.use_clean_sky = false
    _expect(underlay.texture != clean_patch, "original-sky underlay switches with background")
    _expect(underlay.texture.get_image().get_pixel(839, 190).a < 0.01, "original-sky sky pixels remain transparent")
    menu.use_clean_sky = true
    for name in ["coastal_yard","EnvironmentFX","home","ship","research","supply","CrowFlyby"]:
        _expect(art.get_node(name).get_index() < falling.get_index(), "world under leaves: " + name)
    for name in ["home_button","ship_button","research_button","supply_button",
        "home_button_title","ship_button_title","utility_console","options_button","exit_button","WoodSign"]:
        var ui := art.get_node(name)
        _expect(ui.get_index() > falling.get_index() and (ui as CanvasItem).z_index == 0, "UI over leaves: " + name)
    _expect(menu.get_node("ArtCanvas/ship_button").pressed.get_connections().size() > 0, "native button callback retained")
    wind._enter(&"gust")
    wind._process(0.75)
    foliage._process(0.016)
    _expect(wind.strength > 0.4 and material.get_shader_parameter("wind_strength") > 0.4, "wind feeds canopy GPU")
    _expect(falling.live_count() >= 3, "gust starts falling leaves")
    falling._random.seed = 314159
    for i in range(12):
        falling._spawn()
    _expect(falling.live_count() <= 20, "pool remains bounded")
    var first_vel: Vector2 = falling.particles[0].velocity
    var different := false
    for i in range(1,falling.live_count()):
        if falling.particles[i].velocity.distance_to(first_vel) > 15.0:
            different = true
    _expect(different, "different leaf initial speeds")
    var before: Vector2 = falling.particles[0].sprite.position
    for i in range(45):
        wind._process(0.033333)
        falling._process(0.033333)
    var moved: Vector2 = falling.particles[0].sprite.position
    _expect(before.distance_to(moved) > 20.0, "time-integrated leaf movement")
    menu.environment_fx_enabled = false
    _expect(falling.live_count() == 0 and not falling.active, "FX off recycles all leaves")
    _expect(material.get_shader_parameter("wind_strength") == 0.0, "FX off restores static canopy")
    menu.environment_fx_enabled = true
    _expect(falling.active and wind.active and falling.wind == wind, "FX on resumes without rebind")
    print("MENU_FOLIAGE_SMOKE_FAIL" if failed else "MENU_FOLIAGE_SMOKE_PASS")
    menu.queue_free()
    await process_frame
    quit(1 if failed else 0)

func _expect(ok: bool, reason: String) -> void:
    if not ok:
        failed = true
        push_error("FOLIAGE: " + reason)
