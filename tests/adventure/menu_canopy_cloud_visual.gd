extends SceneTree

var failed := false

func _initialize() -> void:
    call_deferred("_check")

func _check() -> void:
    var menu: Control = load("res://scenes/main/01StartMenuV8.tscn").instantiate()
    root.add_child(menu)
    var fx: Node2D = menu.get_node("ArtCanvas/EnvironmentFX")
    var cloud := fx.get_node("Cloud3") as AnimatedSprite2D
    var foliage := fx.get_node("FoliageFX")
    await create_timer(2.1).timeout
    # Pin one authentic cloudy sprite across the historical 840px underlay border.
    for entry in fx.effects:
        if entry.settings.get("cloud", false):
            entry.visible = false
            entry.set_process(false)
    cloud.settings["mode"] = "drift"
    cloud.settings["drift"] = [0.0, 0.0]
    cloud.base_position = Vector2(550.0, 70.0)
    cloud._process(0.0)
    cloud.set_process(false)
    cloud.visible = false
    await process_frame
    await RenderingServer.frame_post_draw
    var without_cloud := root.get_texture().get_image()
    cloud.visible = true
    await process_frame
    await RenderingServer.frame_post_draw
    var with_cloud := root.get_texture().get_image()
    # These samples are on both sides of the historical opaque underlay edge.
    var left_change := _difference(without_cloud, with_cloud, Vector2(750, 160))
    var right_change := _difference(without_cloud, with_cloud, Vector2(850, 160))
    _expect(left_change > 0.04, "cloud visible before old 840px rectangle edge")
    _expect(right_change > 0.04, "cloud continues past the old 840px edge")
    _expect(not foliage.has_node("Clusters"), "no overlapping leaf-cluster sprites")
    var png_result := with_cloud.save_png("user://menu_canopy_cloud_boundary_v4.png")
    print("CLOUD_BOUNDARY left=",left_change," right=",right_change," image=",png_result)
    print("CANOPY_CLOUD_FAIL" if failed else "CANOPY_CLOUD_PASS")
    menu.queue_free()
    await process_frame
    quit(1 if failed else 0)

func _difference(a: Image, b: Image, pos: Vector2) -> float:
    var x := clampi(roundi(pos.x * a.get_width() / 1920.0), 0, a.get_width()-1)
    var y := clampi(roundi(pos.y * a.get_height() / 1080.0), 0, a.get_height()-1)
    var c1 := a.get_pixel(x, y)
    var c2 := b.get_pixel(x, y)
    return absf(c1.r-c2.r)+absf(c1.g-c2.g)+absf(c1.b-c2.b)

func _expect(ok: bool, why: String) -> void:
    if not ok:
        failed = true
        push_error("CANOPY_QA: " + why)
