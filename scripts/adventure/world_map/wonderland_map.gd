## 奇境大陆唯一拼装入口：高清地形、固定镜头与局部动效共用稳定世界坐标。
## 地区轮廓提供高亮，独立按钮展示情报并负责进入已配置的预览。
extends Node2D

## 返回请求仍交由项目唯一切场器执行。
signal return_requested()
## 声明式资源仓库，不包含存档。
const ASSETS := preload("res://scripts/adventure/world_map/world_map_assets.gd")
const TERRAIN := preload("res://scripts/adventure/world_map/world_map_terrain_residency.gd")
## 地形与区域覆盖共用相机范围的原尺寸图块驻留。
var terrain_root: Node2D
## 低内存世界坐标命中索引。
const HITS := preload("res://scripts/adventure/world_map/world_map_hit_index.gd")
## 固定视野、边缘平移与拖动控制器。
const CAMERA := preload("res://scripts/adventure/world_map/world_map_camera.gd")
## 高清分件及受约束的主体动画。
const SUBJECTS := preload("res://scripts/adventure/world_map/world_map_subjects.gd")
## 地区悬停与高清轮廓蒙版。
const INTERACT := preload("res://scripts/adventure/world_map/world_map_interaction.gd")
## 统一时钟和参数提交入口。
const FX := preload("res://scripts/adventure/world_map/world_map_effect_bus.gd")
## 同一工厂创建水域与新增局部效果，资源枚举也使用这份类型表。
const EFFECT_FACTORY := preload("res://scripts/adventure/world_map/world_map_effect_factory.gd")
## 共用档案头像和独立关卡按钮；不把地区蒙版当作战斗入口。
const PROFILE_HUD := preload("res://scripts/adventure/ui/adventure_profile_hud.gd")
const STAGE_UI := preload("res://scripts/adventure/world_map/world_map_stage_ui.gd")
## 当前场景的只读资源实例。
var assets: RefCounted
## 所有地图导航的唯一镜头。
var camera: Camera2D
## 动态分件持有者，作为 subjects 效果注册。
var subjects: Node2D
## 地标交互持有者，不承载业务进度。
var interaction: Node2D
## 与主菜单相同的先校验后提交、显式时间调度模式。
var fx_bus: Node
## 场景唯一显示时钟；动画关闭时交互渐变仍可正常结束。
var elapsed_seconds := 0.0
## 主体运动开关，禁用时由组件保持当前姿态及相位。
var motion_enabled := true
## 不受地图镜头变换影响的最小返回界面。
var _hud: CanvasLayer
## 持有屏幕关卡按钮，用于优先关闭安卓触摸打开的情报。
var _stage_nodes: Control
## 资源与组件完整就绪后才允许地图操作。
var _ready_for_input := false

## 供已有 SceneTransition 后台准备高清资源；仅读取声明，不在 Autoload 加载地图。
static func get_initial_resource_paths() -> PackedStringArray:
    var paths: PackedStringArray = ASSETS.new().initial_resource_paths() # 沿用唯一后台资源准备通道。
    paths.append_array(PackedStringArray([STAGE_UI.FRAME,"res://assets/fonts/方正少儿_GBK.ttf","res://data/PVZ_theme.tres","res://assets/adventure/audio/mus_town.wav"]))
    return paths

## 创建高清分块与运动件；贴图像素和原世界单位独立，避免先缩小再放大。
func _ready() -> void:
    # 和僵尸岛共用地图音乐入口；从战斗返回也必须接管曲目，不能沿用 Boss 或选卡音乐。
    SoundManager.play_town_bgm()
    _create_hud()
    assets = ASSETS.new()
    if not assets.configure():
        push_error("Wonderland map assets not ready")
        return
    var hits: RefCounted = HITS.new() # 悬停索引不随 8K 纹理膨胀，保持世界单位和身份编码。
    if not hits.configure(assets):
        push_error("Wonderland map index not ready")
        return
    terrain_root = TERRAIN.new()
    terrain_root.name = "Terrain"
    terrain_root.z_index = -100
    add_child(terrain_root)
    if not terrain_root.configure(assets.layout,ASSETS.ROOT):
        return
    subjects = SUBJECTS.new()
    subjects.name = "Subjects"
    add_child(subjects)
    subjects.configure(assets)
    # 塔架前景固定在世界坐标，覆盖移动艇体与阴影；布料仍在其前方摆动。
    for spec: Dictionary in assets.layout.get("static_occluders", []):
        var foreground := Sprite2D.new() # 高清静止遮挡，不能挂在飞艇运动根节点下。
        var origin: Array = spec["origin"] # 塔架裁切的世界原点。
        var extent: Array = spec["size"] # 原世界单位下的宽高。
        foreground.centered = false
        foreground.texture = assets.texture(str(spec["path"]))
        foreground.position = Vector2(float(origin[0]), float(origin[1]))
        foreground.scale = Vector2(float(extent[0]), float(extent[1])) / foreground.texture.get_size()
        foreground.z_index = int(spec["z_index"])
        foreground.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
        add_child(foreground)
    interaction = INTERACT.new()
    interaction.name = "LandmarkInteraction"
    add_child(interaction)
    interaction.configure(assets, hits)
    fx_bus = FX.new()
    fx_bus.name = "RegionEffects"
    add_child(fx_bus)
    fx_bus.register_effect("subjects", subjects)
    var result: Dictionary = fx_bus.apply_profiles({"subjects": assets.layout.get("motion_defaults", {})}) # 参数完整验证后才同时提交。
    if not bool(result.get("ok", false)):
        push_error(str(result.get("error", "Invalid Wonderland motion profile")))
        return
    fx_bus.set_enabled("subjects", motion_enabled)
    # 类型注册与资源准备共用同一工厂；可选区域失败时保留原静态底图。
    for effect_id: String in assets.regions.get("regions", {}):
        var region: Dictionary = assets.regions["regions"][effect_id] # 区域身份、资源及参数来自唯一配置。
        var effect: Node2D = EFFECT_FACTORY.create(region) # 水域继续由原适配器承担，其他类型按机制复用。
        if effect == null:
            continue
        effect.name = ("Water_" if region.get("kind","") == "water" else "Effect_") + effect_id
        add_child(effect)
        if not effect.configure(effect_id, assets, terrain_root):
            effect.queue_free()
            continue
        if not fx_bus.register_effect(effect_id, effect):
            effect.queue_free()
            continue
        var effect_result: Dictionary = fx_bus.apply_profiles({effect_id: region.get("profile", {})}) # 整批参数提交沿用既有事务语义。
        if not bool(effect_result.get("ok", false)):
            fx_bus.set_enabled(effect_id, false)
            push_error(str(effect_result.get("error", "Invalid Wonderland effect profile")))
        effect.set_motion_paused(not motion_enabled)
    camera = CAMERA.new()
    camera.name = "WorldCamera"
    add_child(camera)
    camera.configure(assets.world_size(), assets.layout.get("zoom", {}), _is_map_input_blocked)
    terrain_root.update_camera(camera)
    _ready_for_input = true
    _stage_nodes = STAGE_UI.new()
    _stage_nodes.name = "StageNodes"
    _stage_nodes.host = self
    _hud.add_child(_stage_nodes)
    _hud.move_child(_stage_nodes,0) # 档案与返回按钮始终覆盖地图节点。
    terrain_root.update_camera(camera) # 图标锚点注册后确保首屏图标也接管精确图块。

## 复用僵尸岛的档案头像、等级与返回动作，固定在屏幕左上角。
func _create_hud() -> void:
    _hud = CanvasLayer.new()
    _hud.name = "WorldMapUI"
    add_child(_hud)
    var profile := PROFILE_HUD.new() # 原生头像、档案名、等级及返回动作与僵尸岛共用。
    _hud.add_child(profile)
    profile.add_action("返回主菜单",_on_return_pressed)
    profile.mouse_filter = Control.MOUSE_FILTER_STOP # 头像范围不穿透为背景拖动或边缘移图。

## [param delta] 为显示帧间隔；单帧最多推进五十毫秒，避免卡顿后动画跳跃。
func _process(delta: float) -> void:
    if not _ready_for_input:
        return
    terrain_root.update_camera(camera) # 相机已先于宿主更新；覆盖层同帧继承原图纹理。
    elapsed_seconds += minf(delta, 0.05)
    fx_bus.set_animation_seconds(elapsed_seconds)
    interaction.set_animation_seconds(elapsed_seconds)
    # 弹窗、导航或窗口之外不能在背景留下悬停，普通 GUI 不阻断已开始的拖动释放。
    if OS.has_feature("android") or _is_map_input_blocked() or camera.is_navigating() or not get_window().has_focus() or not get_viewport_rect().has_point(get_viewport().get_mouse_position()) or get_viewport().gui_get_hovered_control() != null:
        interaction.clear_hover()
    else:
        interaction.hover_world(get_global_mouse_position())

## 返回全局模态、暂停或切场是否阻断地图；普通 UI 悬停由相机单独处理。
func _is_map_input_blocked() -> bool:
    if not _ready_for_input or get_tree().paused:
        return true
    var transition: Node = get_node_or_null("SceneTransition") # 既有切场器拥有遮幕期间的输入锁。
    if transition != null and bool(transition.get("busy")):
        return true
    var toolbar: Node = get_node_or_null("/root/AdventureToolbar") # 共享弹窗服务，不新建另一套模态状态。
    return toolbar != null and bool(toolbar.call("scene_entries_blocked"))

## [param event] 未被窗口处理时，安卓返回先关闭触摸情报，再返回主菜单。
func _unhandled_key_input(event: InputEvent) -> void:
    if not OS.has_feature("android") or not event.is_action_pressed(&"ui_cancel") or _is_map_input_blocked():
        return
    if (is_instance_valid(_stage_nodes) and _stage_nodes.dismiss_touch_preview()) or _on_return_pressed():
        get_viewport().set_input_as_handled()

## 复用项目唯一 SceneTransition 和主场景注册表返回海滨，返回请求是否被接纳。
func _on_return_pressed() -> bool:
    return_requested.emit()
    if camera != null:
        camera.cancel_gesture()
    var transition: Node = get_node_or_null("SceneTransition") # 当前场景持有的统一切场器。
    var game_global: Node = get_node_or_null("/root/Global") # 独立美术运行也允许没有全局业务服务。
    if transition == null or game_global == null:
        push_warning("Wonderland return service unavailable")
        return false
    var registry: Node = game_global.get("main_scene_registry") as Node # 目标路径由权威注册表提供。
    if registry == null:
        push_warning("Wonderland main scene registry unavailable")
        return false
    var paths: Dictionary = registry.get("MainScenesMap") # 仅查询已有场景，不另造路径注册表。
    var target: String = str(paths.get(MainSceneRegistry.MainScenes.StartMenu, "")) # 正式海滨主菜单。
    if target.is_empty() or not bool(transition.call("change_scene", target)):
        push_warning("Wonderland return request was not accepted")
        return false
    return true

## [param enabled] 冻结全部环境当前帧，继续保留镜头与悬停交互和各区域独立开关。
func set_motion_enabled(enabled: bool) -> void:
    motion_enabled = enabled
    if fx_bus != null:
        fx_bus.set_motion_paused(not enabled)

## [param profiles] 通过现有总线进行整体校验；失败保留所有旧参数。
func apply_effect_profiles(profiles: Dictionary) -> Dictionary:
    if fx_bus == null:
        return {"ok": false, "error": "Wonderland effects not ready"}
    return fx_bus.apply_profiles(profiles)
