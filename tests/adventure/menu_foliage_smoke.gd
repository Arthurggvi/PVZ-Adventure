extends SceneTree

var failed := false

func _initialize() -> void:
    call_deferred("_check")

func _check() -> void:
    var art := Control.new()
    art.name = "ArtCanvas"
    art.size = Vector2(1920, 1080)
    root.add_child(art)
    var bg := TextureRect.new()
    bg.name = "coastal_yard"
    bg.size = art.size
    bg.texture = load("res://assets/adventure/environment_fx/v1/sky_cleanup_v1/backgrounds/main_menu_sky_clean_1920x1080.png")
    bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    art.add_child(bg)
    var ship := TextureRect.new()
    ship.name = "ship"
    ship.size = Vector2(677, 508)
    art.add_child(ship)
    var fx: Node2D = load("res://scenes/environment/main_menu_fx.tscn").instantiate()
    art.add_child(fx)
    await process_frame
    var foliage: Node2D = fx.get_node("FoliageFX")
    var wind := foliage.get_node("Wind")
    var clusters := foliage.get_node("Clusters")
    var falling := foliage.get_node("FallingLeaves")
    _check_assert(clusters.pivots.size() == 4, "4 independent canopy clusters")
    _check_assert(falling.particles.size() == 20, "bounded falling-leaf pool")
    var underlay := foliage.get_node("Underlay") as Sprite2D
    var leaves := foliage.get_node("Leaves") as Sprite2D
    var material := leaves.material as ShaderMaterial
    _check_assert(bg.material == null, "no legacy menu UV warp")
    _check_assert(fx.get_child(-1) == foliage, "canopy above sky fx")
    _check_assert(leaves.texture.get_size() == Vector2(840, 320), "leaf dimensions")
    foliage.set_environment_state(true, true)
    wind._enter(&"gust")
    wind._process(0.75)
    foliage._process(0.016)
    _check_assert(wind.state == &"gust" and wind.strength > 0.4, "gust envelope")
    _check_assert(material.get_shader_parameter("wind_strength") > 0.4, "GPU wind strength")
    _check_assert(falling.live_count() >= 3, "gust emits falling leaves")
    for _i in range(10):
        falling._gust_burst(1.5)
    _check_assert(falling.live_count() == 20, "pool remains capped under repeated gusts")
    clusters._process(1.0)
    _check_assert(absf(clusters.pivots[2].rotation) > 0.001, "independent pivot motion")
    var clean_leaf := leaves.texture
    foliage.set_environment_state(false, true)
    _check_assert(material.get_shader_parameter("wind_strength") == 0.0, "FX disables safely")
    _check_assert(leaves.visible and underlay.visible, "static reconstruction")
    _check_assert(falling.live_count() == 0 and not falling.active, "leaf pool recycled on FX off")
    foliage.set_environment_state(true, false)
    _check_assert(wind.active and wind._target > 0.5, "re-enabled wind resumes immediately")
    _check_assert(leaves.texture != clean_leaf, "original sky variant")
    _check_assert(clusters.sprites[0].texture != clusters.CLEAN[0], "cluster sky variant")
    foliage.hide()
    _check_assert(material.get_shader_parameter("wind_strength") == 0.0, "hidden stops wind")
    foliage.show()
    _check_assert(wind.active, "visible resumes")
    if not OS.get_cmdline_user_args().has("--no-full-menu"):
        _check_assert(load("res://scenes/main/01StartMenuV8.tscn") != null, "menu scene loads")
    print("MENU_FOLIAGE_SMOKE_FAIL" if failed else "MENU_FOLIAGE_SMOKE_PASS")
    quit(1 if failed else 0)

func _check_assert(ok: bool, reason: String) -> void:
    if not ok:
        failed = true
        push_error(reason)
