## 历史V6/V8美术探针：对应场景已退役，当前正式入口与验收见main_menu_runtime_pipeline.md；此脚本不作为新菜单通过证据。
extends SceneTree

var failed := false

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var menu: Control = load("res://scenes/main/01StartMenuV8.tscn").instantiate()
    root.add_child(menu)
    await process_frame
    var falling: Node2D = menu.get_node("ArtCanvas/ForegroundLeaves")
    var panel: CanvasItem = menu.get_node("ArtCanvas/utility_console")
    var boat: CanvasItem = menu.get_node("ArtCanvas/ship")
    var btn: CanvasItem = menu.get_node("ArtCanvas/ship_button")
    var title: CanvasItem = menu.get_node("ArtCanvas/ship_button_title")
    var profile: CanvasItem = menu.get_node("AdventureProfileHud") # 头像框直接锚定视口，由场景根节点绘制。
    print("DEPTH_VALUES fall=",falling.z_index," boat=",boat.z_index," button=",btn.z_index," profile=",profile.z_index," panel=",panel.z_index)
    _expect(falling.z_index == 0 and boat.z_index == 0 and boat.get_index() < falling.get_index(), "world under overlay by sibling order")
    _expect(btn.z_index == 0 and title.z_index == 0 and profile.z_index == 0 and panel.z_index == 0, "no UI z-index overrides")
    _expect(btn.get_index() > falling.get_index() and title.get_index() > falling.get_index()
        and profile.get_index() > falling.get_parent().get_index() and panel.get_index() > falling.get_index(), "UI order above overlay")
    falling.set_process(false)
    for particle in falling.particles:
        particle.alive = false
        particle.sprite.visible = false
    var magenta := Image.create(96,96,false,Image.FORMAT_RGBA8)
    magenta.fill(Color.MAGENTA)
    var sprite := Sprite2D.new()
    sprite.texture = ImageTexture.create_from_image(magenta)
    falling.add_child(sprite)
    sprite.position = Vector2(1580, 360)
    await create_timer(2.0).timeout
    await process_frame
    await RenderingServer.frame_post_draw
    var image1: Image = root.get_texture().get_image()
    var world_color := _sample(image1, sprite.position)
    _expect(world_color.r > 0.96 and world_color.b > 0.96 and world_color.g < 0.07, "falling leaf renders above ship")
    sprite.position = Vector2(1620, 570)
    await process_frame
    await RenderingServer.frame_post_draw
    var image2: Image = root.get_texture().get_image()
    var button_color := _sample(image2, sprite.position)
    _expect(not (button_color.r > 0.96 and button_color.b > 0.96 and button_color.g < 0.07), "button occludes falling leaf")
    print("DEPTH_PIXELS ", world_color, " ", button_color, " view ", image2.get_size())
    sprite.queue_free()
    print("MENU_LEAF_LAYER_FAIL" if failed else "MENU_LEAF_LAYER_PASS")
    menu.queue_free()
    await process_frame
    quit(1 if failed else 0)

func _sample(img: Image, design_position: Vector2) -> Color:
    var x := clampi(int(design_position.x * img.get_width()/1920.0),0,img.get_width()-1)
    var y := clampi(int(design_position.y * img.get_height()/1080.0),0,img.get_height()-1)
    return img.get_pixel(x,y)

func _expect(condition: bool, msg: String) -> void:
    if not condition:
        failed = true
        push_error("LEAF_DEPTH: " + msg)
