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
    bg.size = Vector2(1920, 1080)
    bg.texture = load("res://assets/adventure/environment_fx/v1/sky_cleanup_v1/backgrounds/main_menu_sky_clean_1920x1080.png")
    bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    art.add_child(bg)
    var ship := TextureRect.new()
    ship.name = "ship"
    ship.size = Vector2(677, 508)
    art.add_child(ship)
    var packed: PackedScene = load("res://scenes/environment/main_menu_fx.tscn")
    if not _expect(packed != null, "environment scene loads"):
        quit(1)
        return
    var fx := packed.instantiate() as Node2D
    art.add_child(fx)
    await process_frame
    var foliage := fx.get_node_or_null("FoliageFX")
    if not _expect(foliage != null, "foliage exists"):
        quit(1)
        return
    _expect(fx.get_child(fx.get_child_count() - 1) == foliage, "canopy renders above sky overlays")
    _expect(bg.material == null, "old background UV warping no longer active in main menu")
    var underlay := foliage.get_node("Underlay") as Sprite2D
    var leaves := foliage.get_node("Leaves") as Sprite2D
    var material := leaves.material as ShaderMaterial
    _expect(leaves.texture.get_size() == Vector2(840, 320), "leaf art dimensions")
    _expect(underlay.texture.get_size() == Vector2(840, 320), "underlay dimensions")
    foliage.set_environment_state(true, true)
    _expect(material.get_shader_parameter("wind_enabled") == true, "wind runs")
    var clean_texture := leaves.texture
    foliage.set_environment_state(false, true)
    _expect(material.get_shader_parameter("wind_enabled") == false, "wind freezes without hiding canopy")
    _expect(leaves.visible and underlay.visible, "static image still complete")
    foliage.set_environment_state(true, false)
    _expect(leaves.texture != clean_texture, "original-sky artwork matches source")
    _expect(underlay.texture != null, "original-sky underlay available")
    foliage.hide()
    _expect(material.get_shader_parameter("wind_enabled") == false, "hidden foliage stops")
    foliage.show()
    _expect(material.get_shader_parameter("wind_enabled") == true, "visible foliage resumes")
    if not OS.get_cmdline_user_args().has("--no-full-menu"):
        _expect(load("res://scenes/main/01StartMenuV8.tscn") != null, "real start menu still loads")
    if failed:
        print("MENU_FOLIAGE_SMOKE_FAIL")
        quit(1)
    else:
        print("MENU_FOLIAGE_SMOKE_PASS")
        quit(0)

func _expect(ok: bool, label: String) -> bool:
    if not ok:
        failed = true
        push_error("FOLIAGE_CHECK: " + label)
    return ok
