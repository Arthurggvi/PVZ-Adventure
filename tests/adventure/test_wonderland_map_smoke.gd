extends SceneTree
## 奇境大陆独立无存档冒烟：验证场景构造、11处区域索引、镜头及动态主体接口。
## 只读8K运行资源，不能调用关卡奖励、玩家存档或新建档案。
## 地区选择器仍由已有目录决定入口有效性，不另造本地图登记表。

## SceneTree脚本开始时延后初始化，避免根节点未就绪。
func _initialize() -> void:
    call_deferred("_run")

## 返回码0表示基础合同通过；不代表图形观感/用户真实交互已经验收。
func _run() -> void:
    var map_scene: PackedScene = load("res://scenes/adventure/wonderland_map.tscn")
    var destination_catalog: Script = load("res://scripts/adventure/destination_catalog.gd")
    var node: Node2D = map_scene.instantiate() as Node2D # 正式场景，使用同一GDScript与资源清单。
    root.add_child(node)
    await process_frame
    if node.assets == null or node.interaction == null or node.camera == null:
        push_error("Wonderland scene failed to construct")
        quit(1)
        return
    var catalog: Array = node.assets.landmarks["landmarks"] # 只读地标列表。
    if catalog.size() != 11:
        push_error("Wonderland landmark count mismatch")
        quit(1)
        return
    var picker: RefCounted = destination_catalog.new() # 使用正式第三地区布局及许可。
    var picker_layout: Dictionary = picker.load_layout() # 还验证所有卡片贴图与布局。
    var wonderland_entry: Dictionary = {} # 从目录读取，不复制名称或位置信息。
    for destination: Dictionary in picker_layout.get("destinations", []):
        if destination.get("id", "") == "wonderland":
            wonderland_entry = destination
    if wonderland_entry.is_empty() or not destination_catalog.can_enter(wonderland_entry):
        push_error("Wonderland destination picker route invalid")
        quit(1)
        return
    for entry: Dictionary in catalog:
        var point: Array = entry["hit_sample_world"] # 已知在地标有效区内部的样本点。
        var actual: String = node.interaction.static_hit_at(Vector2(point[0], point[1]))
        if actual != str(entry["id"]):
            push_error("Wonderland hit ID mismatch " + str(entry["id"]))
            quit(1)
            return
    if not node.interaction.static_hit_at(Vector2(-1,-1)).is_empty():
        push_error("Wonderland empty-region hit leaked outside map")
        quit(1)
        return
    var school: Dictionary = node.assets.landmark("abandoned_school") # 定点检查裁切高亮的世界坐标。
    var school_point: Array = school["hit_sample_world"]
    var school_origin: Array = school["hover_mask_origin"]
    node.interaction.hover_world(Vector2(school_point[0],school_point[1]))
    node.set_process(false) # 隔离鼠标位置，允许真实批次准备高亮。
    var hover_deadline: int = Time.get_ticks_msec() + 3000
    while not node.interaction.has_node("Hover_abandoned_school") and Time.get_ticks_msec() < hover_deadline:
        node.interaction.set_animation_seconds(node.elapsed_seconds + 0.2)
        await process_frame
    node.interaction.set_animation_seconds(node.elapsed_seconds + 0.4) # 批次交付后显式推进淡入。
    var hover_sprite: Sprite2D = node.interaction.get_node("Hover_abandoned_school") as Sprite2D # 按地标保留裁切显示节点。
    if hover_sprite == null or not hover_sprite.visible or hover_sprite.position != Vector2(school_origin[0],school_origin[1]):
        push_error("Wonderland hover origin misaligned")
        quit(1)
        return
    node.set_motion_enabled(false)
    node.subjects.set_animation_seconds(0.0)
    node.set_motion_enabled(true)
    node.subjects.set_animation_seconds(2.1)
    if not node.subjects.ship_root.position.is_finite():
        push_error("Wonderland movement produced invalid position")
        quit(1)
        return
    print("WONDERLAND_MAP_SMOKE_OK")
    quit(0)
