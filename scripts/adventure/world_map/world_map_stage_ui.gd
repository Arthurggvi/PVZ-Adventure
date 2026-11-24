## 奇境大陆的关卡节点层，复用僵尸岛控件展示情报并进入已注册的正式关卡。
extends Control

## 共享图标按钮、预览面板与字体样式。
const StageButton := preload("res://scripts/adventure/island_stage_button.gd")
const PreviewPanel := preload("res://scripts/adventure/ui/stage_preview_panel.gd")
## 与第一关共用普通通关后解锁的敌人、掉落情报投影。
const PreviewData := preload("res://scripts/adventure/ui/stage_preview_data.gd")
const UI := preload("res://scripts/adventure/island_ui.gd")
## 地图展示资料仅引用正式关卡编号，不维护另一份战斗配置。
const DATA_PATH := "res://resources/adventure/wonderland_map_nodes.json"
## 共用空白节点框，不复制僵尸岛关卡图案。
const FRAME := "res://assets/adventure/zombie_island/buttons/button_frame_blank.png"
## 圆形缩略图共享相机驻留图块；不可见图标不持有额外高清资源。
const ICON_SHADER := preload("res://shaders/adventure/wonderland/stage_icon.gdshader")
## 缩略图直径占按钮边长的比例，略宽于边框内孔，以便边框覆盖裁切边缘。
const ICON_SIZE_RATIO := 0.75
## 原情报面板使用的设计空间。
const DESIGN := Vector2(1920,1080)
## 宿主负责唯一镜头、模态和切场判断。
var host: Node2D
## 单个地图访问的展示数据。
var records: Dictionary = {}
## 节点与世界锚点对应，不受环境动效位移影响。
var buttons: Dictionary = {}
var anchors: Dictionary = {}
## 画布中只创建一个共享情报面板。
var preview: Control
## 已请求展示的地区；阻塞结束时只重新请求一次，不逐帧重启延迟。
var _shown_id := ""
## 一个地形图块可以服务多个图标；每块只连接一次纹理变更信号。
var _tile_icons: Dictionary = {}

## 在正式地图已就绪后建立11个节点；名称与情报不依赖通关记录。
func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    theme = UI.make_theme()
    records = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
    preview = PreviewPanel.new()
    var index := 0 # 仅用于共享控件的标签偏移键，不传入战斗目录。
    for entry: Dictionary in host.assets.landmarks.landmarks: # 使用既有地标的世界锚点。
        var id: String = str(entry.id) # 稳定地区身份。
        var record: Dictionary = records[id] # 本区名称、介绍及Boss标记。
        var point: Array = entry.hit_sample_world # 与原地区命中定义一致。
        anchors[id] = Vector2(point[0],point[1])
        index += 1
        var button := StageButton.new() # 与僵尸岛相同的标题悬停和键盘焦点行为。
        button.name = "Stage_"+id
        add_child(button)
        button.configure({"id":index,"name":record.name,"button_path":FRAME,
            "position_normalized":[0,0]},true,false,_on_stage_pressed.bind(id),{str(index):[0,0]})
        _add_icon(button,record,anchors[id])
        if not OS.has_feature("android"):
            button.mouse_entered.connect(_show_info.bind(id))
            button.mouse_exited.connect(preview.release_hover)
            button.focus_entered.connect(_show_info.bind(id))
            button.focus_exited.connect(preview.release_hover)
        buttons[id] = button
    preview.name = "StagePreview"
    add_child(preview)
    preview.dismissed.connect(_on_preview_dismissed)
    get_viewport().size_changed.connect(_cancel_info)
    if OS.has_feature("android"):
        host.camera.world_clicked.connect(_on_map_background_clicked)
    _process(0.0)

## [param button] 保留原共享边框与点击区域；[param record] 声明正方形原画世界裁切。
## 只选完整包含裁切的既有图块；无效数据局部拒绝，不能把相邻地区错作图标。
func _add_icon(button: Control, record: Dictionary, anchor: Vector2) -> void:
    var values: Array = record.get("icon_crop_world",[]) # 原画代表景物的左上角及正方形边长。
    if values.size() != 3:
        push_error("Wonderland missing icon crop: "+str(record.get("name","")))
        return
    var density: float = float(host.assets.layout.terrain.pixels_per_world) # 世界到原生地形像素密度。
    var crop := Rect2(Vector2(values[0],values[1])*density,Vector2.ONE*float(values[2])*density) # 不从低清命中图采样。
    if crop.size.x <= 0.0:
        return
    var tiles: Array = host.assets.layout.terrain.tiles
    for index: int in tiles.size():
        var tile: Dictionary = tiles[index] # 使用同一索引定位驻留地形精灵。
        var origin := Vector2(tile.pixel_origin[0],tile.pixel_origin[1]) # 包括图块采样留边。
        var extent := Vector2(tile.pixel_size[0],tile.pixel_size[1]) # 实际纹理尺寸。
        if not Rect2(origin,extent).encloses(crop):
            continue
        var icon := TextureRect.new() # 只绘制圆形内部，不拦截按钮鼠标事件。
        icon.name = "RegionIcon"
        var source: Sprite2D = host.terrain_root.get_child(index) as Sprite2D
        icon.texture = source.texture
        if not _tile_icons.has(index):
            _tile_icons[index]=[]
            source.texture_changed.connect(_sync_icon_textures.bind(index))
        _tile_icons[index].append(icon)
        host.terrain_root.register_icon(index,anchor) # 图标可见时，即使裁切点位于邻块也保证驻留。
        icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        icon.stretch_mode = TextureRect.STRETCH_SCALE
        icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
        icon.size = button.size * ICON_SIZE_RATIO
        icon.position = (button.size - icon.size) * 0.5
        icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
        icon.show_behind_parent = true # 原有金属边框盖住圆形裁切的接缝。
        var material := ShaderMaterial.new() # 每个图标只持有自己的裁切参数。
        material.shader = ICON_SHADER
        var start: Vector2 = (crop.position-origin)/extent # 归一化图块内位置。
        var span: Vector2 = crop.size/extent # 归一化采样尺寸。
        material.set_shader_parameter("crop_uv",Vector4(start.x,start.y,span.x,span.y))
        icon.material = material
        button.add_child(icon)
        return
    push_error("Wonderland icon crop crosses tiles: "+str(record.get("name","")))

## [param _delta] 不推进地图动作；每帧将世界锚点投影到屏幕，UI尺寸独立于相机倍率。
func _process(_delta: float) -> void:
    var viewport_size: Vector2 = get_viewport_rect().size # 真实窗口坐标。
    var factor: float = minf(viewport_size.x/DESIGN.x,viewport_size.y/DESIGN.y) # 共享UI设计缩放。
    scale = Vector2.ONE*factor
    position = (viewport_size-DESIGN*factor)*0.5
    var blocked: bool = host._is_map_input_blocked() # 模态、暂停或切场必须关闭情报并禁用节点。
    for id: String in buttons: # 只投影固定数量的节点，不创建每帧控件。
        var button: Control = buttons[id] # 当前地区的共享按钮。
        var screen: Vector2 = host.get_canvas_transform()*anchors[id] # 相机世界到视口。
        button.position = (screen-position)/factor-button.size*0.5
        button.visible = Rect2(Vector2.ZERO,viewport_size).has_point(screen)
        button.disabled = blocked
    if blocked or host.camera.is_navigating() or not get_window().has_focus():
        _cancel_info()
        return
    if OS.has_feature("android"):
        return # 触摸主动打开情报，不使用模拟鼠标遗留的悬停或焦点。
    if preview.is_pointer_over():
        return # 移入情报阅读时，不能被仍留在旧按钮上的键盘焦点切走。
    var active := "" # 轮询只恢复真实悬停；键盘预览由 focus_entered 单独驱动。
    for id: String in buttons: # 不让旧按钮焦点抢走移向面板空隙中的预览，或在关闭后重新弹出。
        var button: Control = buttons[id] # 只恢复仍可见且可用的节点。
        if not button.visible or button.disabled:
            continue
        if button.is_hovered():
            active = id
            break
    if not active.is_empty():
        _show_info(active)

## 取消显示并释放请求身份，允许之后的鼠标或焦点进入重新请求情报。
func _cancel_info() -> void:
    _shown_id = ""
    preview.cancel()

## 悬停宽限结束后同步清除地图身份，允许再次进入同一节点。
func _on_preview_dismissed() -> void:
    _shown_id = ""

## [param _position] 是背景短按位置；关闭已有情报，不选择地区。
func _on_map_background_clicked(_position: Vector2) -> void:
    dismiss_touch_preview()

## 有触摸情报时关闭并返回 true，供地图返回键优先处理。
func dismiss_touch_preview() -> bool:
    if _shown_id.is_empty():
        return false
    _cancel_info()
    return true

## [param id] 有正式关卡编号时走统一会话、选卡及结算；其余地区只展示情报。
func _on_stage_pressed(id: String) -> void:
    var stage_number: int = int(records[id].get("stage_number", 0)) # 由唯一关卡目录解释身份。
    if stage_number == 0:
        _show_info(id)
        return
    if host._is_map_input_blocked() or host.camera.is_navigating() or not get_window().has_focus():
        return
    if OS.has_feature("android") and _shown_id != id and AdventureStageCatalog.is_cleared(
            Global.global_game_state.adventure_state, AdventureStageRegistry.stage_id(stage_number),
            StagePhaseDefinition.Kind.NORMAL):
        _show_info(id)
        return
    var transition: Node = host.get_node(^"SceneTransition") # 沿用地图的异步切换与失败恢复。
    if AdventureSession.prepare_adventure() and AdventureSession.enter_stage(stage_number, StagePhaseDefinition.Kind.NORMAL, transition):
        _cancel_info()
    else:
        var message := AcceptDialog.new() # 入场失败保留地图并给出实际原因。
        message.dialog_text = AdventureSession.error_message if not AdventureSession.error_message.is_empty() else AdventureSession.entry_error
        message.confirmed.connect(message.queue_free)
        message.canceled.connect(message.queue_free)
        add_child(message)
        message.popup_centered(Vector2i(520, 160))

## [param id] 显示地区资料，并提示当前关卡按钮的可用操作。
func _show_info(id: String) -> void:
    if host._is_map_input_blocked() or host.camera.is_navigating() or not get_window().has_focus() or id == _shown_id:
        return
    _shown_id = id
    var record: Dictionary = records[id] # 同一个来源驱动标题、Boss类型和介绍。
    var button: Control = buttons[id] # 面板锚点采用投影后的UI坐标。
    var subtitle: String = ("BOSS关卡" if record.boss else "普通关卡")+" · 战斗暂未开放" # 仅有情报时显示地区类型。
    if record.has("stage_number"):
        var number: int = int(record.stage_number) # 正式编号与存档身份一致。
        var cleared: bool = AdventureStageCatalog.is_cleared(Global.global_game_state.adventure_state, AdventureStageRegistry.stage_id(number), StagePhaseDefinition.Kind.NORMAL) # 不借用第一关通关事实。
        var data: Dictionary = PreviewData.build(AdventureStageRegistry.resolve(number) if cleared else null,
            record.name, cleared) # 首通前沿用原有情报限制。
        if OS.has_feature("android") and cleared:
            data["subtitle"] = "普通阶段已通关 · 再次轻触关卡进入"
        preview.request(data, Rect2(button.position, button.size))
        return
    preview.request({"state":"region","title":record.name,"description":record.description,
        "subtitle":subtitle},Rect2(button.position,button.size))

## 地形换入与释放同帧更新图标；不创建其他纹理引用或复制像素。
func _sync_icon_textures(index: int) -> void:
    var source: Sprite2D=host.terrain_root.get_child(index) as Sprite2D
    for icon: TextureRect in _tile_icons[index]:
        if is_instance_valid(icon):
            icon.texture=source.texture
