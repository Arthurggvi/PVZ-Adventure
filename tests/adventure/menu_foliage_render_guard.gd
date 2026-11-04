extends SceneTree

var failed := false

func _initialize() -> void:
    call_deferred("_check")

func _check() -> void:
    var menu: Control = load("res://scenes/main/01StartMenuV8.tscn").instantiate()
    root.add_child(menu)
    var art := menu.get_node("ArtCanvas")
    var environment := art.get_node("EnvironmentFX")
    var foliage := environment.get_node("FoliageFX")
    art.get_node("ForegroundLeaves").set_active(false)
    art.get_node("CrowFlyby").hide()
    for effect in environment.effects:
        effect.set_process(false)
        effect.hide()
    environment.set_process(false)
    foliage.set_process(false)
    await create_timer(2.4).timeout
    var mat := (art.get_node("coastal_yard") as TextureRect).material as ShaderMaterial
    mat.set_shader_parameter("wind_strength",0.0)
    await process_frame
    await RenderingServer.frame_post_draw
    var still := root.get_texture().get_image()
    mat.set_shader_parameter("wind_strength",1.45)
    mat.set_shader_parameter("wind_time",2.65)
    await process_frame
    await RenderingServer.frame_post_draw
    var moving := root.get_texture().get_image()
    var size := still.get_size()
    _expect(size.x > 500 and size.y > 300,"valid graphics viewport")
    var moving_count := _changed(still,moving,Rect2i(10,10,430,125))
    var sky_count := _changed(still,moving,Rect2i(480,12,400,115))
    var ground_count := _changed(still,moving,Rect2i(200,275,320,160))
    print("FOLIAGE_PIXEL_DELTA inside=",moving_count," sky=",sky_count,
        " ground=",ground_count," viewport=",size)
    _expect(moving_count > 400,"visible internal canopy movement")
    _expect(sky_count == 0,"sky untouched by foliage shader")
    _expect(ground_count == 0,"ground untouched by foliage shader")
    menu.queue_free()
    await process_frame
    print("FOLIAGE_RENDER_FAIL" if failed else "FOLIAGE_RENDER_PASS")
    quit(1 if failed else 0)

func _changed(a: Image,b: Image,rect: Rect2i) -> int:
    var count := 0
    for yy in range(rect.position.y,min(rect.end.y,a.get_height())):
        for xx in range(rect.position.x,min(rect.end.x,a.get_width())):
            var x := a.get_pixel(xx,yy)
            var y := b.get_pixel(xx,yy)
            if absf(x.r-y.r)+absf(x.g-y.g)+absf(x.b-y.b) > 0.04:
                count += 1
    return count

func _expect(ok: bool, reason: String) -> void:
    if not ok:
        failed = true
        push_error("FOLIAGE_RENDER: " + reason)
